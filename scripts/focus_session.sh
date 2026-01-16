#!/usr/bin/env bash
# focus_session.sh - Focus terminal app and switch to tmux session/pane
# Activates the terminal application and switches to the specified tmux pane
#
# Usage:
#   focus_session.sh <pane_id>
#   focus_session.sh %3  # Focus pane %3
#
# Arguments:
#   pane_id: tmux pane ID (e.g., %0, %3, %15)

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"

# Check for WSL environment
IS_WSL=0
if grep -qEi "(microsoft|wsl)" /proc/version 2>/dev/null; then
    IS_WSL=1
fi

# Terminal application names for osascript activation
# Returns app name for osascript based on terminal name
get_terminal_app_name() {
    local terminal_name="$1"
    case "$terminal_name" in
        iTerm2) echo "iTerm" ;;
        WezTerm) echo "WezTerm" ;;
        Ghostty) echo "Ghostty" ;;
        Terminal) echo "Terminal" ;;
        *) echo "$terminal_name" ;;
    esac
}

# ==============================================================================
# WSL-specific functions
# ==============================================================================

# Get Windows process name from terminal name
# $1: terminal_name (WindowsTerminal, WezTerm, VSCode, Alacritty)
# Returns: Windows process name for SetForegroundWindow
get_windows_process_name() {
    local terminal_name="$1"
    case "$terminal_name" in
        WindowsTerminal) echo "WindowsTerminal" ;;
        WezTerm) echo "wezterm-gui" ;;
        VSCode) echo "Code" ;;
        Alacritty) echo "alacritty" ;;
        *) echo "" ;;
    esac
}

# Focus Windows terminal using PowerShell WScript.Shell AppActivate
# Uses window title partial matching instead of SetForegroundWindow API
# which doesn't work reliably in WSL2 environments
# For Windows Terminal, uses wt.exe CLI for more reliable focus control
# $1: Search term (window title substring to match, or "WindowsTerminal" for Windows Terminal)
# Returns: 0 on success, 1 on failure
focus_windows_terminal() {
    local search_term="$1"

    if [ -z "$search_term" ]; then
        return 1
    fi

    # Check if powershell.exe is available
    if ! command -v powershell.exe &>/dev/null; then
        return 1
    fi

    # Windows Terminal の場合は wt.exe を使用
    if [ "$search_term" = "WindowsTerminal" ]; then
        # wt.exe でフォーカスを取得
        if command -v wt.exe &>/dev/null; then
            wt.exe -w 0 focus-tab -t 0 2>/dev/null
            return $?
        fi
        # wt.exe がない場合はフォールバック
    fi

    # WScript.Shell の AppActivate を使用（ウィンドウタイトルの部分一致）
    powershell.exe -NoProfile -NonInteractive -Command "
        \$wshell = New-Object -ComObject WScript.Shell
        \$result = \$wshell.AppActivate('$search_term')
        if (\$result) { exit 0 } else { exit 1 }
    " 2>/dev/null

    return $?
}

# Activate terminal in WSL environment
# $1: pane_id (tmux pane ID)
# Returns: 0 on success, 1 on failure
activate_terminal_wsl() {
    local pane_id="$1"

    # Get session name from pane_id
    local session_name
    session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)

    if [ -z "$session_name" ]; then
        return 1
    fi

    # First: Detect terminal name to determine the best focus method
    local terminal_name
    terminal_name=$(get_terminal_for_session_wsl "$session_name" 2>/dev/null)

    if [ -z "$terminal_name" ] || [ "$terminal_name" = "Unknown" ]; then
        # Fallback: guess from environment variables
        if [ -n "$WT_SESSION" ]; then
            terminal_name="WindowsTerminal"
        elif [ -n "$TERM_PROGRAM" ] && [ "$TERM_PROGRAM" = "WezTerm" ]; then
            terminal_name="WezTerm"
        fi
    fi

    # For Windows Terminal: MUST use wt.exe (AppActivate doesn't work for UWP apps)
    if [ "$terminal_name" = "WindowsTerminal" ]; then
        if command -v wt.exe &>/dev/null; then
            wt.exe -w 0 focus-tab -t 0 2>/dev/null
            return $?
        fi
        # wt.exe not available, try AppActivate as last resort
    fi

    # For other terminals: use AppActivate with various search terms
    # Try 1: Focus using session name (AppActivate uses window title partial match)
    if focus_windows_terminal "$session_name"; then
        return 0
    fi

    # Try 2: Focus using "tmux" keyword (most tmux windows have "tmux" in title)
    if focus_windows_terminal "tmux"; then
        return 0
    fi

    # Try 3: Focus using process name
    if [ -n "$terminal_name" ]; then
        local process_name
        process_name=$(get_windows_process_name "$terminal_name")
        if [ -n "$process_name" ]; then
            if focus_windows_terminal "$process_name"; then
                return 0
            fi
        fi
    fi

    return 1
}

# Detect terminal application from tmux client
# Returns: Terminal app name (iTerm2, WezTerm, Ghostty, Terminal, or empty)
detect_terminal_app() {
    local pane_id="$1"
    local terminal_name=""

    if [[ "$(uname)" != "Darwin" ]]; then
        echo ""
        return
    fi

    # Get session name from pane_id
    local session_name
    session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)

    if [ -z "$session_name" ]; then
        echo ""
        return
    fi

    # Get client PID attached to the session
    local client_pid
    client_pid=$(tmux list-clients -t "$session_name" -F '#{client_pid}' 2>/dev/null | head -1)

    if [ -z "$client_pid" ]; then
        echo ""
        return
    fi

    # Walk up the process tree to find terminal app
    local current_pid="$client_pid"
    local max_depth=10
    local depth=0

    while [ "$depth" -lt "$max_depth" ]; do
        local pname
        pname=$(ps -p "$current_pid" -o comm= 2>/dev/null)

        terminal_name=$(_detect_terminal_from_pname "$pname")
        if [ -n "$terminal_name" ]; then
            break
        fi

        # Get parent PID
        local ppid
        ppid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')

        if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
            break
        fi

        current_pid="$ppid"
        ((depth++))
    done

    echo "$terminal_name"
}

# Activate terminal application
# $1: Terminal app name (iTerm2, WezTerm, Ghostty, Terminal, WindowsTerminal, etc.)
# $2: pane_id (optional, required for WSL)
activate_terminal_app() {
    local terminal_name="$1"
    local pane_id="${2:-}"

    # WSL environment: use PowerShell to focus Windows terminal
    if [ "$IS_WSL" = "1" ]; then
        if [ -n "$pane_id" ]; then
            activate_terminal_wsl "$pane_id"
            return $?
        fi
        # If no pane_id, try to focus based on terminal_name directly
        local process_name
        process_name=$(get_windows_process_name "$terminal_name")
        if [ -n "$process_name" ]; then
            focus_windows_terminal "$process_name"
            return $?
        fi
        return 1
    fi

    # macOS: use AppleScript
    if [[ "$(uname)" != "Darwin" ]]; then
        return 0
    fi

    local app_name
    app_name=$(get_terminal_app_name "$terminal_name")

    if [ -n "$app_name" ]; then
        osascript -e "tell application \"$app_name\" to activate" 2>/dev/null
        return $?
    fi

    return 1
}

# Get the terminal app for a specific session's client
# $1: session_name
# Returns: Terminal app name or empty if no client attached
get_terminal_for_session() {
    local session_name="$1"
    local terminal_name=""

    if [[ "$(uname)" != "Darwin" ]]; then
        echo ""
        return
    fi

    # Get client PID attached to the session
    local client_pid
    client_pid=$(tmux list-clients -t "$session_name" -F '#{client_pid}' 2>/dev/null | head -1)

    if [ -z "$client_pid" ]; then
        echo ""
        return
    fi

    # Walk up the process tree to find terminal app
    local current_pid="$client_pid"
    local max_depth=10
    local depth=0

    while [ "$depth" -lt "$max_depth" ]; do
        local pname
        pname=$(ps -p "$current_pid" -o comm= 2>/dev/null)

        terminal_name=$(_detect_terminal_from_pname "$pname")
        if [ -n "$terminal_name" ]; then
            break
        fi

        # Get parent PID
        local ppid
        ppid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')

        if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
            break
        fi

        current_pid="$ppid"
        ((depth++))
    done

    echo "$terminal_name"
}

# Switch to the specified tmux pane
# $1: pane_id (e.g., %0, %3)
# Handles cross-session switching and terminal activation
# Intelligently manages cross-session switching:
# - If target session has an attached client, activates that terminal
# - If target session is detached, switches current client to it
switch_to_pane() {
    local pane_id="$1"

    if [ -z "$pane_id" ]; then
        echo "Error: pane_id is required" >&2
        return 1
    fi

    # Get session and window info for the pane
    local session_name window_index
    session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)
    window_index=$(tmux display-message -p -t "$pane_id" '#{window_index}' 2>/dev/null)

    if [ -z "$session_name" ]; then
        echo "Error: Could not find session for pane $pane_id" >&2
        return 1
    fi

    # Check if target session has a client attached
    local target_client_tty
    target_client_tty=$(tmux list-clients -t "$session_name" -F '#{client_tty}' 2>/dev/null | head -1)

    if [ -n "$target_client_tty" ]; then
        # Target session has a client attached in another terminal
        # Activate that terminal and select window/pane there
        local target_terminal_name

        # Use appropriate function based on environment
        if [ "$IS_WSL" = "1" ]; then
            target_terminal_name=$(get_terminal_for_session_wsl "$session_name")
        else
            target_terminal_name=$(get_terminal_for_session "$session_name")
        fi

        if [ -n "$target_terminal_name" ]; then
            activate_terminal_app "$target_terminal_name" "$pane_id"
        elif [ "$IS_WSL" = "1" ]; then
            # WSL fallback: try to activate using pane_id directly
            activate_terminal_wsl "$pane_id"
        fi

        # Select window and pane (switch-client not needed - already attached)
        tmux select-window -t "$session_name:$window_index" 2>/dev/null || true
        tmux select-pane -t "$pane_id" 2>/dev/null
    else
        # Target session is detached, switch current client to it
        tmux switch-client -t "$session_name" 2>/dev/null || true
        tmux select-window -t "$session_name:$window_index" 2>/dev/null || true
        tmux select-pane -t "$pane_id" 2>/dev/null
    fi

    return $?
}

# Main function
main() {
    local pane_id="$1"

    if [ -z "$pane_id" ]; then
        echo "Usage: focus_session.sh <pane_id>" >&2
        echo "Example: focus_session.sh %3" >&2
        exit 1
    fi

    # Detect and activate terminal app
    local terminal_name

    # Use appropriate detection based on environment
    if [ "$IS_WSL" = "1" ]; then
        # For WSL, get session name first and use WSL-specific detection
        local session_name
        session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)
        if [ -n "$session_name" ]; then
            terminal_name=$(get_terminal_for_session_wsl "$session_name")
        fi
    else
        terminal_name=$(detect_terminal_app "$pane_id")
    fi

    if [ -n "$terminal_name" ]; then
        activate_terminal_app "$terminal_name" "$pane_id"
    elif [ "$IS_WSL" = "1" ]; then
        # WSL fallback: try to activate using pane_id directly
        activate_terminal_wsl "$pane_id"
    fi

    # Switch to the pane
    switch_to_pane "$pane_id"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
