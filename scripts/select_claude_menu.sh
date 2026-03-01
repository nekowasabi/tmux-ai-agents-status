#!/usr/bin/env bash
# select_claude_menu.sh - Native tmux menu selector (Phase 2)
# Uses prerendered data to show tmux display-menu without fzf dependency
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PRERENDER_FILE="${PRERENDER_OVERRIDE:-/tmp/ai_agent_fzf_prerender}"

if [ ! -f "$PRERENDER_FILE" ]; then
    tmux display-message "No agent data. Please wait..."
    exit 0
fi

# 鮮度チェック: 10秒以上古いキャッシュは警告 (OS別 stat 分岐)
_now="${EPOCHSECONDS:-$(date +%s)}"
if [[ "$(uname)" == "Darwin" ]]; then
    _mtime=$(stat -f %m "$PRERENDER_FILE" 2>/dev/null || echo 0)
else
    _mtime=$(stat -c %Y "$PRERENDER_FILE" 2>/dev/null || echo 0)
fi
PRERENDER_AGE=$(( _now - _mtime ))
if [ "$PRERENDER_AGE" -gt 10 ]; then
    tmux display-message "Agent data is stale (${PRERENDER_AGE}s old). Showing cached data..."
fi

# display-menuの引数を構築
# 形式: "表示文字列" "" "run-shell 'focus_session.sh pane_id'"
# C-3: シェルインジェクション対策: display_line のシングルクォートをエスケープ
menu_args=()
while IFS=$'\t' read -r display_line pane_id; do
    [ -z "$pane_id" ] && continue
    # pane_id は %N:M.L 形式で安全だが、display_line はユーザーデータ由来のためサニタイズ
    safe_display=$(printf '%s' "$display_line" | sed "s/'/'\\\\''/g")
    menu_args+=("$safe_display" "" "run-shell '\"$CURRENT_DIR/focus_session.sh\" \"$pane_id\"'")
done < "$PRERENDER_FILE"

if [ ${#menu_args[@]} -eq 0 ]; then
    tmux display-message "No Claude agents found."
    exit 0
fi

tmux display-menu -T "Select AI Agent" "${menu_args[@]}"
