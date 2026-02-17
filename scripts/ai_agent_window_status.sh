#!/usr/bin/env bash
# ai_agent_window_status.sh - Window-specific AI agent status
# Outputs agent status for use in window-status-current-format / window-status-format
# Arguments: $1=window_index, $2=session_name

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/shared.sh"
source "$CURRENT_DIR/session_tracker.sh"

# Arguments
window_index="$1"
session_name="$2"

# Default configuration (same as ai_agent_status.sh)
DEFAULT_RUNNING_DOT="●"
DEFAULT_WAITING_DOT="◐"
DEFAULT_IDLE_DOT="○"
DEFAULT_UNKNOWN_DOT="?"

DEFAULT_RUNNING_COLOR="green"
DEFAULT_WAITING_COLOR="yellow"
DEFAULT_IDLE_COLOR="colour240"
DEFAULT_UNKNOWN_COLOR="colour244"

# Exit silently if no arguments
if [ -z "$window_index" ] || [ -z "$session_name" ]; then
    exit 0
fi

main() {
    # Try to read shared cache
    if ! read_shared_cache_all; then
        # No cache available - exit silently
        exit 0
    fi

    # Process info format: pid|pane_id|session_name|window_index|tty_path|terminal|cwd|proc_type
    if [ -z "$_SHARED_CACHE_PROCESSES" ]; then
        exit 0
    fi

    # Load user configuration
    local running_dot waiting_dot idle_dot unknown_dot
    local running_color waiting_color idle_color unknown_color
    local show_process_name

    running_dot=$(get_tmux_option "@ai_agent_running_dot" "$DEFAULT_RUNNING_DOT")
    waiting_dot=$(get_tmux_option "@ai_agent_waiting_dot" "$DEFAULT_WAITING_DOT")
    idle_dot=$(get_tmux_option "@ai_agent_idle_dot_new" "$DEFAULT_IDLE_DOT")
    unknown_dot=$(get_tmux_option "@ai_agent_unknown_dot" "$DEFAULT_UNKNOWN_DOT")
    running_color=$(get_tmux_option "@ai_agent_running_color" "$DEFAULT_RUNNING_COLOR")
    waiting_color=$(get_tmux_option "@ai_agent_waiting_color" "$DEFAULT_WAITING_COLOR")
    idle_color=$(get_tmux_option "@ai_agent_idle_color_new" "$DEFAULT_IDLE_COLOR")
    unknown_color=$(get_tmux_option "@ai_agent_unknown_color" "$DEFAULT_UNKNOWN_COLOR")

    # Window status specific option: show process name (default: on)
    show_process_name=$(get_tmux_option "@ai_agent_window_show_process" "on")

    # Filter processes for this window
    local output=""
    local found=0

    while IFS='|' read -r pid pane_id sess win tty terminal cwd proc_type; do
        # Skip if not matching session and window
        if [ "$sess" != "$session_name" ] || [ "$win" != "$window_index" ]; then
            continue
        fi

        found=1

        # Detect status from pane content
        local status=""
        local elapsed=""
        local mode=""

        if [ -n "$pane_id" ]; then
            local detailed
            detailed=$(detect_claude_status_from_pane "$pane_id" 2>/dev/null)
            if [ -n "$detailed" ]; then
                # Parse: "running:1m30s:plan_mode" or "idle" etc.
                local temp="$detailed"
                status="${temp%%:*}"
                temp="${temp#*:}"
                if [ "$temp" != "$status" ]; then
                    local second="${temp%%:*}"
                    if [[ "$second" == "plan_mode" || "$second" == "accept_edits" ]]; then
                        mode="$second"
                    else
                        elapsed="$second"
                        temp="${temp#*:}"
                        if [ "$temp" != "$second" ]; then
                            mode="$temp"
                        fi
                    fi
                fi
            fi
        fi

        # Default to unknown if no status detected
        if [ -z "$status" ]; then
            status="unknown"
        fi

        # Select dot and color based on status
        local dot color
        case "$status" in
            running)
                dot="$running_dot"
                color="$running_color"
                ;;
            waiting)
                dot="$waiting_dot"
                color="$waiting_color"
                ;;
            idle)
                dot="$idle_dot"
                color="$idle_color"
                ;;
            *)
                dot="$unknown_dot"
                color="$unknown_color"
                ;;
        esac

        # Format with color - status icon only
        if [ -n "$color" ]; then
            output+=" #[fg=$color]${dot}#[fg=default]"
        else
            output+=" ${dot}"
        fi

        # Only show first agent per window (avoid clutter)
        break
    done <<< "$_SHARED_CACHE_PROCESSES"

    if [ "$found" = "1" ]; then
        echo "$output"
    fi
}

main "$@"
