#!/usr/bin/env bash
# ai_agent_status.tmux - TPM entry point for Claude Code status plugin
# Integrates Claude Code status display into tmux statusline

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/scripts/shared.sh"

# Format string interpolation setup
ai_agent_status="#($CURRENT_DIR/scripts/ai_agent_status.sh)"
ai_agent_status_interpolation="\#{ai_agent_status}"

# Window-specific status (uses tmux's #{window_index} and #{session_name} expansion)
ai_agent_window_status="#($CURRENT_DIR/scripts/ai_agent_window_status.sh '#{window_index}' '#{session_name}')"
ai_agent_window_status_interpolation="\#{ai_agent_window_status}"

# Interpolate format strings
do_interpolation() {
    local string="$1"
    string="${string/$ai_agent_status_interpolation/$ai_agent_status}"
    string="${string/$ai_agent_window_status_interpolation/$ai_agent_window_status}"
    echo "$string"
}

# Update tmux option with interpolation
update_tmux_option() {
    local option="$1"
    local option_value
    option_value="$(get_tmux_option "$option")"

    # Skip if option is empty
    if [ -z "$option_value" ]; then
        return
    fi

    local new_value
    new_value="$(do_interpolation "$option_value")"
    set_tmux_option "$option" "$new_value"
}

# Setup keybinding for Claude Code process selection
setup_select_keybinding() {
    local select_key selector
    select_key=$(get_tmux_option "@ai_agent_select_key" "")

    # Skip if no key is configured
    if [ -z "$select_key" ]; then
        return
    fi

    selector=$(get_tmux_option "@ai_agent_selector" "fzf")

    if [ "$selector" = "menu" ]; then
        # Phase 2: Use tmux native display-menu (fast, no fzf required)
        tmux bind-key "$select_key" run-shell "$CURRENT_DIR/scripts/select_claude_menu.sh"
    else
        # Phase 1 / default: fzf popup (available in tmux 3.2+)
        local tmux_version
        tmux_version=$(tmux -V | sed 's/[^0-9.]//g' | cut -d. -f1-2)

        local use_popup=false
        if [ -n "$tmux_version" ]; then
            local major minor
            major=$(echo "$tmux_version" | cut -d. -f1)
            minor=$(echo "$tmux_version" | cut -d. -f2)
            if [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 2 ]; }; then
                use_popup=true
            fi
        fi

        local select_script="$CURRENT_DIR/scripts/select_claude.sh"
        local launcher_script="$CURRENT_DIR/scripts/select_claude_launcher.sh"

        if [ "$use_popup" = true ]; then
            tmux bind-key "$select_key" run-shell "$launcher_script"
        else
            tmux bind-key "$select_key" split-window -v "$select_script"
        fi
    fi
}

setup_pane_title_sync() {
    local sync_enabled
    sync_enabled=$(get_tmux_option "@ai_agent_pane_title_sync" "")

    if [ "$sync_enabled" != "on" ]; then
        return
    fi

    # Why: enable tmux pane_title pipeline so /rename's OSC 2 reaches #{pane_title}; opt-in to avoid clashing with user/plugin tmux.conf
    tmux set-option -g set-titles on
    tmux set-option -g allow-rename on
    tmux set-option -g automatic-rename off
}

main() {
    setup_pane_title_sync

    update_tmux_option "status-right"
    update_tmux_option "status-left"
    update_tmux_option "status-format[0]"
    update_tmux_option "status-format[1]"
    update_tmux_option "pane-border-format"

    # Window status options (for #{ai_agent_window_status})
    update_tmux_option "window-status-current-format"
    update_tmux_option "window-status-format"

    # Setup optional keybindings
    setup_select_keybinding
}

main "$@"
