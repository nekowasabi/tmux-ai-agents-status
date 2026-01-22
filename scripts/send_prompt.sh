#!/usr/bin/env bash
# send_prompt.sh - Send a prompt to a Claude Code session via popup

PANE_ID="$1"

if [ -z "$PANE_ID" ]; then
    echo "Usage: send_prompt.sh <pane_id>" >&2
    exit 1
fi

# Validate pane exists
if ! tmux display-message -p -t "$PANE_ID" '#{pane_id}' &>/dev/null; then
    tmux display-message "Error: Pane $PANE_ID not found"
    exit 1
fi

# Use popup with bash read to avoid command-prompt %1 issues
# Approach: Use tmux buffer (paste-buffer) instead of send-keys for reliable text input
tmux popup -E -w 60 -h 5 -T " Send to Claude " \
    "printf '> '; read input; if [ -n \"\$input\" ]; then printf '%s' \"\$input\" | tmux load-buffer -; tmux paste-buffer -t '$PANE_ID'; tmux send-keys -t '$PANE_ID' Enter; fi"
