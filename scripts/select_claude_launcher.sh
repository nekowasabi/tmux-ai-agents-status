#!/usr/bin/env bash
# select_claude_launcher.sh - Prepare data first, THEN launch popup
# This prevents the empty window flicker by preparing data before popup appears

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMP_DATA="/tmp/ai_agent_fzf_$$"
RESULT_FILE="/tmp/ai_agent_result_$$"
ORIGINAL_PANE=$(tmux display-message -p '#{pane_id}')

# Step 1: Get process list using internal format (runs OUTSIDE popup)
source "$CURRENT_DIR/shared.sh"
source "$CURRENT_DIR/session_tracker.sh"

# Initialize batch cache for efficient data gathering
init_batch_cache

# Get raw process data
process_data=$(get_all_claude_info_batch 2>/dev/null)

if [ -z "$process_data" ]; then
    tmux display-message "No Claude Code processes found."
    exit 0
fi

# Get working/idle status icons from tmux options (legacy, kept for backward compat)
working_dot=$(get_tmux_option "@ai_agent_working_dot" "🤖")
idle_dot=$(get_tmux_option "@ai_agent_idle_dot" "🔔")

# 4-state status icons (colorful emoji for better visibility)
running_icon=$(get_tmux_option "@ai_agent_running_icon" "🟢")
waiting_icon=$(get_tmux_option "@ai_agent_waiting_icon" "🟡")
idle_icon_new=$(get_tmux_option "@ai_agent_idle_icon_new" "🔵")
unknown_icon=$(get_tmux_option "@ai_agent_unknown_icon" "❓")
plan_mode_indicator=$(get_tmux_option "@ai_agent_plan_mode_indicator" "⏸")
accept_edits_indicator=$(get_tmux_option "@ai_agent_accept_edits_indicator" "⏵⏵")

# Get working threshold
working_threshold=$(get_tmux_option "@ai_agent_working_threshold" "5")

# Get current time once
current_time="${EPOCHSECONDS:-$(date +%s)}"

# Prepare display lines and pane IDs
> "$TEMP_DATA"
> "${TEMP_DATA}_panes"

# Format: pid|pane_id|session_name|window_index|tty_path|terminal_name|cwd
while IFS='|' read -r pid pane_id session_name window_index tty_path terminal_name cwd; do
    [ -z "$pane_id" ] && continue
    # Create display line
    project_name=$(basename "$cwd" 2>/dev/null || echo "unknown")
    # Truncate if too long
    [ ${#project_name} -gt 18 ] && project_name="${project_name:0:15}..."

    # Get terminal emoji
    case "$terminal_name" in
        iTerm2|Terminal) emoji="🍎" ;;
        WezTerm) emoji="⚡" ;;
        Ghostty) emoji="👻" ;;
        WindowsTerminal) emoji="🪟" ;;
        VSCode) emoji="📝" ;;
        Alacritty) emoji="🔲" ;;
        *) emoji="❓" ;;
    esac

    # 4-state status detection using pane content analysis
    detailed_status=$(detect_claude_status_from_pane "$pane_id")

    # Parse: "running:1m30s:plan_mode" or "idle:plan_mode" or "idle" etc.
    IFS=':' read -r base_st elapsed_st mode_st <<< "$detailed_status"
    if [[ "$elapsed_st" == "plan_mode" || "$elapsed_st" == "accept_edits" ]]; then
        mode_st="$elapsed_st"
        elapsed_st=""
    fi

    # Map to icon
    case "$base_st" in
        running) status_prefix="$running_icon" ;;
        waiting) status_prefix="$waiting_icon" ;;
        idle)    status_prefix="$idle_icon_new" ;;
        *)       status_prefix="$unknown_icon" ;;
    esac

    # Append elapsed time and mode indicator
    [ -n "$elapsed_st" ] && status_prefix="${status_prefix}${elapsed_st}"
    if [ "$mode_st" = "plan_mode" ]; then
        status_prefix="${status_prefix} ${plan_mode_indicator}"
    elif [ "$mode_st" = "accept_edits" ]; then
        status_prefix="${status_prefix} ${accept_edits_indicator}"
    fi

    # Include session name for cross-session visibility and status icon
    display_line="  ${status_prefix} ${emoji} #${window_index} ${project_name} [${session_name}]"
    echo "$display_line" >> "$TEMP_DATA"
    echo "$pane_id" >> "${TEMP_DATA}_panes"
done <<< "$process_data"

# Check if we have any data
if [ ! -s "$TEMP_DATA" ]; then
    tmux display-message "No Claude Code processes found."
    rm -f "$TEMP_DATA" "${TEMP_DATA}_panes"
    exit 0
fi

# Get preview setting
PREVIEW_ENABLED=$(get_tmux_option "@ai_agent_fzf_preview" "on")
PREVIEW_SCRIPT="$CURRENT_DIR/preview_pane.sh"

# Build AI_AGENT_PANE_DATA for preview script
# Format: "display_line\tpane_id\n" for each entry
PANE_DATA_FILE="${TEMP_DATA}_pane_data"
paste "$TEMP_DATA" "${TEMP_DATA}_panes" > "$PANE_DATA_FILE"

# Read preview position and size from tmux options
PREVIEW_POSITION=$(tmux show-option -gqv "@ai_agent_fzf_preview_position" 2>/dev/null)
PREVIEW_POSITION="${PREVIEW_POSITION:-down}"
PREVIEW_SIZE=$(tmux show-option -gqv "@ai_agent_fzf_preview_size" 2>/dev/null)
PREVIEW_SIZE="${PREVIEW_SIZE:-50%}"

# Build preview option
PREVIEW_OPT=""
if [ "$PREVIEW_ENABLED" = "on" ] && [ -x "$PREVIEW_SCRIPT" ]; then
    # Escape paths for shell embedding
    ESCAPED_SCRIPT=$(printf '%q' "$PREVIEW_SCRIPT")
    ESCAPED_PANE_DATA=$(printf '%q' "$PANE_DATA_FILE")
    PREVIEW_OPT="--preview='AI_AGENT_PANE_DATA=\$(cat $ESCAPED_PANE_DATA) $ESCAPED_SCRIPT {}' --preview-window=${PREVIEW_POSITION}:${PREVIEW_SIZE}:wrap"
fi

# Step 2: Launch popup with pre-prepared data (instant display!)
# Popup writes result to file, then parent process handles focus_session.sh
tmux popup -E -w 80% -h 60% "
    trap 'rm -f '$TEMP_DATA' '${TEMP_DATA}_panes' '$PANE_DATA_FILE' '$RESULT_FILE'; exit 130' INT TERM

    selected_output=\$(cat '$TEMP_DATA' | fzf --height=100% --reverse \
        --prompt='Select Claude: ' \
        --header='Enter: Switch | Ctrl+S: Send Prompt' \
        --expect=ctrl-s \
        $PREVIEW_OPT)
    key=\$(echo \"\$selected_output\" | head -1)
    selected=\$(echo \"\$selected_output\" | tail -n +2 | head -1)
    if [ -n \"\$selected\" ]; then
        line_num=\$(grep -nF \"\$selected\" '$TEMP_DATA' | head -1 | cut -d: -f1)
        if [ -n \"\$line_num\" ]; then
            pane_id=\$(sed -n \"\${line_num}p\" '${TEMP_DATA}_panes')
            echo \"\$key|\$pane_id\" > '$RESULT_FILE'
        fi
    fi
    rm -f '$TEMP_DATA' '${TEMP_DATA}_panes' '$PANE_DATA_FILE'
"

# Step 3: After popup closes, execute action based on key pressed
if [ -f "$RESULT_FILE" ]; then
    result=$(cat "$RESULT_FILE")
    rm -f "$RESULT_FILE"

    key="${result%%|*}"
    pane_id="${result#*|}"

    if [ -n "$pane_id" ]; then
        if [ "$key" = "ctrl-s" ]; then
            "$CURRENT_DIR/send_prompt.sh" "$pane_id"
        else
            "$CURRENT_DIR/focus_session.sh" "$pane_id"
        fi
    fi
else
    # キャンセル時は元のペインにフォーカスを確実に戻す
    tmux select-pane -t "$ORIGINAL_PANE" 2>/dev/null || true
fi
