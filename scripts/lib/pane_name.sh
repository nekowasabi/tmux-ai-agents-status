#!/usr/bin/env bash
# pane_name.sh - resolve display name from tmux pane title
# Why: adopted reading #{pane_title} via tmux instead of a Claude Code hook —
# the hook approach requires JSON persistence, context-compaction handling, and
# cross-tool coordination, while tmux's set-titles/allow-rename pipe already
# captures the OSC 2 escape sequence emitted by Claude Code's /rename. Minimal
# implementation, no extra processes, works for any tool that emits OSC 2.

# Source guard: prevent double-sourcing
if [ -n "${__LIB_PANE_NAME_LOADED:-}" ]; then return 0; fi
__LIB_PANE_NAME_LOADED=1

# Default values that indicate the pane title is NOT a /rename result
# (typical shell or process names that tmux/terminals set automatically).
# Why: avoid mistaking a default shell prompt for a user-chosen rename label.
__PANE_NAME_DEFAULT_TITLES=(
    ""
    "zsh"
    "bash"
    "fish"
    "sh"
    "tmux"
    "claude"
    "codex"
)

# Returns 0 if the given title looks like a default (non-renamed) value.
__pane_name_is_default_title() {
    local title="$1"
    local default
    for default in "${__PANE_NAME_DEFAULT_TITLES[@]}"; do
        if [ "$title" = "$default" ]; then
            return 0
        fi
    done
    return 1
}

# Resolve the display name for a tmux pane.
# $1: pane_id (e.g., "%42")
# $2: fallback_name (returned when pane_title is unavailable / looks default)
# $3: max_length (optional, default 18)
# Returns: pane_title when @ai_agent_pane_title_sync = on AND the title differs
#          from known defaults; fallback_name otherwise.
get_pane_display_name() {
    local pane_id="$1"
    local fallback_name="$2"
    local max_length="${3:-18}"

    # Opt-in: only consult pane_title when the user explicitly enables sync.
    # Why: tmux set-titles / allow-rename interact with other plugins and
    # user tmux.conf settings. Default off keeps existing behaviour intact.
    local sync_enabled
    sync_enabled=$(get_tmux_option "@ai_agent_pane_title_sync" "off")
    if [ "$sync_enabled" != "on" ]; then
        echo "$fallback_name"
        return
    fi

    # Guard: skip when pane_id is missing or synthetic (process without pane).
    if [ -z "$pane_id" ] || [[ "$pane_id" == unknown_* ]]; then
        echo "$fallback_name"
        return
    fi

    local pane_title
    pane_title=$(tmux display-message -p -t "$pane_id" '#{pane_title}' 2>/dev/null)

    if __pane_name_is_default_title "$pane_title"; then
        echo "$fallback_name"
        return
    fi

    # Truncate consistently with get_project_name_for_pid for layout stability.
    if [ "${#pane_title}" -gt "$max_length" ]; then
        pane_title="${pane_title:0:$((max_length - 3))}..."
    fi

    echo "$pane_title"
}
