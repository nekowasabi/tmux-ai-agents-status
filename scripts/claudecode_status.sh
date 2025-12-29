#!/usr/bin/env bash
# claudecode_status.sh - Claude Code status information for tmux
# Outputs formatted status for display in tmux statusline

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"
source "$CURRENT_DIR/session_tracker.sh"

# Default configuration
DEFAULT_ICON=""                    # Nerd Font: robot
DEFAULT_WORKING_DOT="●"
DEFAULT_IDLE_DOT="○"
# tmux 3.x requires hex colors without # prefix for #[fg=] syntax
# idle=赤、working=緑
DEFAULT_WORKING_COLOR="colour46"    # green (tmux colour46 ≈ #00ff00) - 作業中
DEFAULT_IDLE_COLOR="colour196"      # red (tmux colour196 ≈ #ff0000) - アイドル
DEFAULT_ICON_COLOR="colour135"      # purple (tmux colour135 ≈ #af5fff)
DEFAULT_SEPARATOR=" | "             # ペイン間のセパレータ

# Cache configuration
CACHE_DIR="/tmp"
CACHE_FILE="$CACHE_DIR/claudecode_status_cache_$$"
CACHE_TTL=2

# Clean up cache on exit
cleanup_cache() {
    rm -f "$CACHE_FILE"
}
trap cleanup_cache EXIT

main() {
    # Check cache
    if [ -f "$CACHE_FILE" ]; then
        local cache_age
        cache_age=$(( $(get_current_timestamp) - $(get_file_mtime "$CACHE_FILE") ))
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
            cat "$CACHE_FILE"
            return
        fi
    fi

    # Get session details (新形式: pane_name:status|pane_name:status|...)
    local details
    details=$(get_session_details)

    # No sessions
    if [ -z "$details" ]; then
        echo "" > "$CACHE_FILE"
        cat "$CACHE_FILE"
        return
    fi

    # Load user configuration
    local working_dot idle_dot working_color idle_color separator
    working_dot=$(get_tmux_option "@claudecode_working_dot" "$DEFAULT_WORKING_DOT")
    idle_dot=$(get_tmux_option "@claudecode_idle_dot" "$DEFAULT_IDLE_DOT")
    working_color=$(get_tmux_option "@claudecode_working_color" "$DEFAULT_WORKING_COLOR")
    idle_color=$(get_tmux_option "@claudecode_idle_color" "$DEFAULT_IDLE_COLOR")
    separator=$(get_tmux_option "@claudecode_separator" "$DEFAULT_SEPARATOR")

    # Generate output: "● ● ○" 形式（ドットのみ）
    local output=""
    local first=1

    # Parse details (project_name:status|project_name:status|...)
    IFS='|' read -ra entries <<< "$details"
    for entry in "${entries[@]}"; do
        local project_name status dot color

        # Parse entry (project_name:status)
        project_name="${entry%%:*}"
        status="${entry##*:}"

        # 状態に応じてドットと色を選択
        if [ "$status" = "working" ]; then
            dot="$working_dot"
            color="$working_color"
        else
            dot="$idle_dot"
            color="$idle_color"
        fi

        # セパレータを追加（最初以外）
        if [ "$first" = "1" ]; then
            first=0
            output+="  "  # Left margin
        else
            output+=" "  # Space between dots
        fi

        # ドットのみを追加（プロジェクト名は表示しない）
        output+="#[fg=$color]${dot}#[default]"
    done

    output+="  "  # Right margin

    echo "$output" > "$CACHE_FILE"
    cat "$CACHE_FILE"
}

main "$@"
