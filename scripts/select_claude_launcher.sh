#!/usr/bin/env bash
# select_claude_launcher.sh - Prepare data first, THEN launch popup
# This prevents the empty window flicker by preparing data before popup appears

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMP_DATA="/tmp/claudecode_fzf_$$"

# Step 1: Get process list using internal format (runs OUTSIDE popup)
source "$CURRENT_DIR/shared.sh"

# Try to use shared cache first
if try_use_shared_cache 2>/dev/null; then
    : # Cache loaded
else
    init_batch_cache
fi

# Get raw process data
process_data=$(get_all_claude_info_batch 2>/dev/null)

if [ -z "$process_data" ]; then
    tmux display-message "No Claude Code processes found."
    exit 0
fi

# Prepare display lines and pane IDs
> "$TEMP_DATA"
> "${TEMP_DATA}_panes"

# Format: pid|pane_id|pane_index|window_index|tty_path|terminal_name|cwd
while IFS='|' read -r pid pane_id pane_index window_index tty_path terminal_name cwd; do
    [ -z "$pane_id" ] && continue
    # Create display line
    project_name=$(basename "$cwd" 2>/dev/null || echo "unknown")
    # Truncate if too long
    [ ${#project_name} -gt 18 ] && project_name="${project_name:0:15}..."
    display_line="  🍎 #${window_index} ${project_name} [${pane_index}]"
    echo "$display_line" >> "$TEMP_DATA"
    echo "$pane_id" >> "${TEMP_DATA}_panes"
done <<< "$process_data"

# Check if we have any data
if [ ! -s "$TEMP_DATA" ]; then
    tmux display-message "No Claude Code processes found."
    rm -f "$TEMP_DATA" "${TEMP_DATA}_panes"
    exit 0
fi

# Step 2: Launch popup with pre-prepared data (instant display!)
tmux popup -E -w 60% -h 40% "
    selected=\$(cat '$TEMP_DATA' | fzf --height=100% --reverse --prompt='Select Claude: ')
    if [ -n \"\$selected\" ]; then
        line_num=\$(grep -nF \"\$selected\" '$TEMP_DATA' | head -1 | cut -d: -f1)
        if [ -n \"\$line_num\" ]; then
            pane_id=\$(sed -n \"\${line_num}p\" '${TEMP_DATA}_panes')
            tmux select-window -t \"\${pane_id%%.*}\" 2>/dev/null
            tmux select-pane -t \"\$pane_id\" 2>/dev/null
        fi
    fi
    rm -f '$TEMP_DATA' '${TEMP_DATA}_panes'
"
