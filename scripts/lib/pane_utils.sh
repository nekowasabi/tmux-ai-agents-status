#!/usr/bin/env bash
# pane_utils.sh - Pane index, terminal/status priority sorting
# Source guard: prevent double-sourcing
if [ -n "${__LIB_PANE_UTILS_LOADED:-}" ]; then return 0; fi
__LIB_PANE_UTILS_LOADED=1

# Dependencies
# get_terminal_priority() is already in terminal.sh, so we source it
source "${BASH_SOURCE[0]%/*}/terminal.sh"

# ==============================================================================
# Pane Utilities and Sorting
# ==============================================================================

# Status priority for sorting (working processes displayed first)
get_status_priority() {
    local status="$1"
    case "$status" in
        working) echo 0 ;;  # Working first
        idle) echo 1 ;;
        *) echo 2 ;;
    esac
}

# tmuxペインのウィンドウインデックス番号を取得
# $1: pane_id（例: %0, %1）
# 戻り値: "#1", "#2" 形式の文字列（ウィンドウ番号）
# 注: 各ウィンドウに1ペインの場合、pane_indexは常に0になるため
#     より意味のあるwindow_indexを返す
get_pane_index() {
    local pane_id="$1"

    if [ -z "$pane_id" ] || [ "$pane_id" = "unknown" ]; then
        echo ""
        return
    fi

    # tmuxからウィンドウインデックスを取得
    local window_index
    window_index=$(tmux display-message -p -t "$pane_id" '#{window_index}' 2>/dev/null)

    if [ -n "$window_index" ]; then
        echo "#${window_index}"
    else
        echo ""
    fi
}

# Note: get_terminal_priority() is sourced from terminal.sh
# Note: get_pane_index_cached() is in cache_batch.sh
