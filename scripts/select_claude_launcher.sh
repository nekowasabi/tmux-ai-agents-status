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

# 共有キャッシュを確認（ai_agent_status.shが生成したもの）
# 新鮮なキャッシュがあればバッチ初期化をスキップして高速化
SHARED_CACHE_DATA=""
SHARED_CACHE_OPTIONS=""
SHARED_CACHE_TTY_STAT=""
if read_shared_cache_all; then
    SHARED_CACHE_DATA="$_SHARED_CACHE_PROCESSES"
    SHARED_CACHE_OPTIONS="$_SHARED_CACHE_OPTIONS"
    SHARED_CACHE_TTY_STAT="$_SHARED_CACHE_TTY_STAT"
fi

# 共有キャッシュがない場合のみバッチ処理キャッシュを初期化
if [ -z "$SHARED_CACHE_DATA" ]; then
    init_batch_cache
else
    # 共有キャッシュヒット時でも tmux options ファイルは必要
    # (get_tmux_options_bulk が BATCH_INITIALIZED チェックするため)
    BATCH_TMUX_OPTIONS_FILE=$(mktemp /tmp/ai_agent_tmux_opts_XXXXXX)
    tmux show-options -g 2>/dev/null > "$BATCH_TMUX_OPTIONS_FILE"
    BATCH_INITIALIZED=1
fi

# Get raw process data (use shared cache if available, otherwise batch)
if [ -n "$SHARED_CACHE_DATA" ]; then
    process_data="$SHARED_CACHE_DATA"
else
    process_data=$(get_all_claude_info_batch 2>/dev/null)
fi

if [ -z "$process_data" ]; then
    tmux display-message "No Claude Code processes found."
    exit 0
fi

# Get all tmux options in one batch (replaces 9 individual get_tmux_option calls)
eval "$(get_tmux_options_bulk \
    "@ai_agent_working_dot=🤖" \
    "@ai_agent_idle_dot=🔔" \
    "@ai_agent_running_icon=🟢" \
    "@ai_agent_waiting_icon=🟡" \
    "@ai_agent_idle_icon_new=🔵" \
    "@ai_agent_unknown_icon=❓" \
    "@ai_agent_plan_mode_indicator=⏸" \
    "@ai_agent_accept_edits_indicator=⏵⏵" \
    "@ai_agent_working_threshold=5" \
    "@ai_agent_fzf_preview=on" \
    "@ai_agent_fzf_preview_position=down" \
    "@ai_agent_fzf_preview_size=50%")"

# Get current time once
current_time="${EPOCHSECONDS:-$(date +%s)}"

# Prepare display lines and pane IDs
> "$TEMP_DATA"
> "${TEMP_DATA}_panes"

# ペインステータスキャッシュを確認（ai_agent_status.shが2秒毎に更新）
_STATUS_CACHE_FILE="/tmp/ai_agent_pane_status_cache"
_USE_STATUS_CACHE=0
if [ -f "$_STATUS_CACHE_FILE" ]; then
    _cache_mtime=$(stat -f %m "$_STATUS_CACHE_FILE" 2>/dev/null || echo 0)
    _cache_age=$(( current_time - _cache_mtime ))
    if [ "$_cache_age" -le 5 ]; then
        _USE_STATUS_CACHE=1
        # 改行区切りで囲んで bash 文字列検索用に整形（grep不要）
        _STATUS_CACHE_CONTENT=$'\n'"$(cat "$_STATUS_CACHE_FILE")"$'\n'
    fi
fi

# ステータスキャッシュがない場合のみ、ペインコンテンツを並列キャプチャ
_CAPTURE_DIR=""
if [ "$_USE_STATUS_CACHE" != "1" ]; then
    _CAPTURE_DIR="/tmp/ai_agent_capture_$$"
    mkdir -p "$_CAPTURE_DIR"
    while IFS='|' read -r _pid _pane_id _rest; do
        [ -z "$_pane_id" ] && continue
        (LC_ALL=C.UTF-8 tmux capture-pane -t "$_pane_id" -p -S -30 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' > "$_CAPTURE_DIR/$_pane_id") &
    done <<< "$process_data"
    wait
fi

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

    # 4-state status detection (キャッシュ優先、なければpre-captured content)
    if [ "$_USE_STATUS_CACHE" = "1" ]; then
        # ステータスキャッシュから取得（純bash文字列操作、サブシェル不要）
        if [[ "$_STATUS_CACHE_CONTENT" == *$'\n'"${pane_id}|"* ]]; then
            _match="${_STATUS_CACHE_CONTENT#*$'\n'${pane_id}|}"
            detailed_status="${_match%%$'\n'*}"
        else
            detailed_status="unknown"
        fi
    else
        _pane_content=$(cat "$_CAPTURE_DIR/$pane_id" 2>/dev/null)
        detailed_status=$(_detect_status_from_content "$_pane_content")
    fi

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
    rm -rf "$_CAPTURE_DIR"
    exit 0
fi

# Preview settings (already fetched via get_tmux_options_bulk)
PREVIEW_ENABLED="$fzf_preview"
PREVIEW_POSITION="$fzf_preview_position"
PREVIEW_SIZE="$fzf_preview_size"
PREVIEW_SCRIPT="$CURRENT_DIR/preview_pane.sh"

# Build AI_AGENT_PANE_DATA for preview script
# Format: "display_line\tpane_id\n" for each entry
PANE_DATA_FILE="${TEMP_DATA}_pane_data"
paste "$TEMP_DATA" "${TEMP_DATA}_panes" > "$PANE_DATA_FILE"

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
    rm -rf '$_CAPTURE_DIR'
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
