#!/usr/bin/env bash
# preview_pane.sh - Display pane content for fzf preview
# Called by fzf --preview option

set -euo pipefail

# 引数: fzfから渡される選択行
SELECTED_LINE="${1:-}"

if [ -z "$SELECTED_LINE" ]; then
    echo "No selection"
    exit 0
fi

# CLAUDECODE_PANE_DATA 環境変数からpane_idを検索
# フォーマット: "display_line\tpane_id\n" の繰り返し
if [ -z "${CLAUDECODE_PANE_DATA:-}" ]; then
    echo "Preview data not available"
    exit 0
fi

# 選択行に対応するpane_idを検索
PANE_ID=""
while IFS=$'\t' read -r display_line pane_id; do
    if [ "$display_line" = "$SELECTED_LINE" ]; then
        PANE_ID="$pane_id"
        break
    fi
done <<< "$CLAUDECODE_PANE_DATA"

if [ -z "$PANE_ID" ]; then
    echo "Pane not found for selection"
    exit 0
fi

# tmux capture-pane でペイン内容を取得
# -p: 出力を標準出力に
# -t: ターゲットペイン指定
# -S: 開始行（負の値で末尾から）
# Use fzf's preview lines variable for dynamic sizing
# This ensures the most recent output (bottom) is always visible
PREVIEW_LINES="${FZF_PREVIEW_LINES:-30}"
CAPTURE_LINES=$((PREVIEW_LINES + 10))

if ! tmux capture-pane -p -t "$PANE_ID" -S -"$CAPTURE_LINES" 2>/dev/null | tail -n "$PREVIEW_LINES"; then
    echo "Failed to capture pane content"
    echo "Pane ID: $PANE_ID"
fi
