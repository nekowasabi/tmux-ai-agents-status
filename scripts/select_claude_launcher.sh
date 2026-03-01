#!/usr/bin/env bash
# select_claude_launcher.sh - Prerender fast path (TTL=10s) + legacy fallback

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESULT_FILE="/tmp/ai_agent_result_$$"
ORIGINAL_PANE=$(tmux display-message -p '#{pane_id}')
FZF_PRERENDER_FILE="/tmp/ai_agent_fzf_prerender"
PRERENDER_TTL=10

# Check prerender freshness (no source needed in fast path)
_use_prerender=0
if [ -f "$FZF_PRERENDER_FILE" ]; then
    _now="${EPOCHSECONDS:-$(date +%s)}"
    _mtime=$([[ "$(uname)" == "Darwin" ]] && stat -f %m "$FZF_PRERENDER_FILE" 2>/dev/null || stat -c %Y "$FZF_PRERENDER_FILE" 2>/dev/null || echo 0)
    [ $(( _now - _mtime )) -le "$PRERENDER_TTL" ] && _use_prerender=1
fi

# Legacy fallback: regenerate prerender via shared.sh when stale/missing
if [ "$_use_prerender" != "1" ]; then
    source "$CURRENT_DIR/shared.sh"
    source "$CURRENT_DIR/session_tracker.sh"
    _batch=$(get_all_claude_info_batch 2>/dev/null)
    if [ -z "$_batch" ]; then
        tmux display-message "No Claude Code processes found."; exit 0
    fi
    write_fzf_prerender "$_batch" 2>/dev/null || true
fi

[ ! -s "$FZF_PRERENDER_FILE" ] && { tmux display-message "No Claude Code processes found."; exit 0; }

# Preview: preview_pane.sh receives selected line as $1, pane_id ({2}) as $2
PREVIEW_OPT=""
PREVIEW_SCRIPT="$CURRENT_DIR/preview_pane.sh"
if [ -x "$PREVIEW_SCRIPT" ] && [ "$(tmux show-options -gv @ai_agent_fzf_preview 2>/dev/null || echo on)" = "on" ]; then
    _pos=$(tmux show-options -gv @ai_agent_fzf_preview_position 2>/dev/null || echo "down")
    _size=$(tmux show-options -gv @ai_agent_fzf_preview_size 2>/dev/null || echo "50%")
    PREVIEW_OPT="--preview='$(printf '%q' "$PREVIEW_SCRIPT") {} {2}' --preview-window=${_pos}:${_size}:wrap"
fi

# Launch popup: --with-nth=1 hides pane_id (tab-delimited col 2)
tmux popup -E -w 80% -h 60% "
    trap 'rm -f '$RESULT_FILE'; exit 130' INT TERM
    selected_output=\$(cat '$FZF_PRERENDER_FILE' | fzf --height=100% --reverse \
        --with-nth=1 --delimiter='\t' \
        --prompt='Select Claude: ' \
        --header='Enter: Switch | Ctrl+S: Send Prompt' \
        --expect=ctrl-s \
        $PREVIEW_OPT)
    key=\$(echo \"\$selected_output\" | head -1)
    selected=\$(echo \"\$selected_output\" | tail -n +2 | head -1)
    if [ -n \"\$selected\" ]; then
        pane_id=\$(echo \"\$selected\" | awk -F'\t' '{print \$NF}')
        echo \"\$key|\$pane_id\" > '$RESULT_FILE'
    fi
"

# Handle result
if [ -f "$RESULT_FILE" ]; then
    result=$(cat "$RESULT_FILE"); rm -f "$RESULT_FILE"
    key="${result%%|*}"; pane_id="${result#*|}"
    if [ -n "$pane_id" ]; then
        [ "$key" = "ctrl-s" ] && "$CURRENT_DIR/send_prompt.sh" "$pane_id" || "$CURRENT_DIR/focus_session.sh" "$pane_id"
    fi
else
    tmux select-pane -t "$ORIGINAL_PANE" 2>/dev/null || true
fi
