#!/usr/bin/env bash
# ai_agent_status.sh - Claude Code status information for tmux
# Outputs formatted status for display in tmux statusline

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"
source "$CURRENT_DIR/session_tracker.sh"

# Default configuration
DEFAULT_ICON=""                    # Nerd Font: robot
DEFAULT_WORKING_DOT="🤖"
DEFAULT_IDLE_DOT="🔔"
DEFAULT_SEPARATOR=" "              # セッション間のセパレータ
DEFAULT_WORKING_COLOR=""           # 作業中の色（空の場合は色なし）
DEFAULT_IDLE_COLOR=""              # アイドル中の色（空の場合は色なし）
DEFAULT_LEFT_SEP=""                # 左側の囲み文字
DEFAULT_RIGHT_SEP=""               # 右側の囲み文字
DEFAULT_WORKING_THRESHOLD=30       # 作業中と判定する時間閾値（秒）

# 4段階状態表示のデフォルト
DEFAULT_RUNNING_DOT="●"            # 実行中
DEFAULT_WAITING_DOT="◐"           # 待機中
DEFAULT_IDLE_DOT_NEW="○"           # アイドル
DEFAULT_UNKNOWN_DOT="?"            # 不明

DEFAULT_RUNNING_COLOR="green"
DEFAULT_WAITING_COLOR="yellow"
DEFAULT_IDLE_COLOR_NEW="colour240"  # dim gray
DEFAULT_UNKNOWN_COLOR="colour244"

# モード表示のデフォルト
DEFAULT_PLAN_MODE_INDICATOR="⏸"
DEFAULT_ACCEPT_EDITS_INDICATOR="⏵⏵"

# Note: get_status_priority and get_terminal_priority are now in shared.sh

# Cache configuration
CACHE_DIR="/tmp"
CACHE_FILE="$CACHE_DIR/ai_agent_status_cache_$$"
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

    # バッチキャッシュを初期化（select_claude.sh用の共有キャッシュ生成のため）
    init_batch_cache

    # Get session details (新形式: terminal_emoji:pane_index:project_name:status|...)
    local details
    details=$(get_session_details)

    # select_claude.sh用の共有キャッシュを更新
    # get_all_claude_info_batch()のデータを書き出す
    local batch_info
    batch_info=$(get_all_claude_info_batch)
    if [ -n "$batch_info" ]; then
        write_shared_cache "$batch_info"
        write_fzf_prerender "$batch_info" 2>/dev/null || true
    fi

    # No sessions
    if [ -z "$details" ]; then
        echo "" > "$CACHE_FILE"
        cat "$CACHE_FILE"
        return
    fi

    # Load user configuration
    local working_dot idle_dot working_color idle_color separator
    local show_terminal show_pane
    local left_sep right_sep
    local working_threshold
    working_dot=$(get_tmux_option "@ai_agent_working_dot" "$DEFAULT_WORKING_DOT")
    idle_dot=$(get_tmux_option "@ai_agent_idle_dot" "$DEFAULT_IDLE_DOT")
    working_color=$(get_tmux_option "@ai_agent_working_color" "$DEFAULT_WORKING_COLOR")
    idle_color=$(get_tmux_option "@ai_agent_idle_color" "$DEFAULT_IDLE_COLOR")
    separator=$(get_tmux_option "@ai_agent_separator" "$DEFAULT_SEPARATOR")
    left_sep=$(get_tmux_option "@ai_agent_left_sep" "$DEFAULT_LEFT_SEP")
    right_sep=$(get_tmux_option "@ai_agent_right_sep" "$DEFAULT_RIGHT_SEP")
    # 新オプション: ターミナル絵文字とペイン番号の表示制御
    show_terminal=$(get_tmux_option "@ai_agent_show_terminal" "on")
    show_pane=$(get_tmux_option "@ai_agent_show_pane" "on")
    working_threshold=$(get_tmux_option "@ai_agent_working_threshold" "$DEFAULT_WORKING_THRESHOLD")

    # Phase 4: Codex display options
    show_codex=$(get_tmux_option "@ai_agent_show_codex" "on")
    codex_icon=$(get_tmux_option "@ai_agent_codex_icon" "🦾")
    claude_icon=$(get_tmux_option "@ai_agent_claude_icon" "")

    # 4段階状態表示オプション（running_dot は working_dot をフォールバックとして使用）
    local running_dot waiting_dot_opt idle_dot_new unknown_dot
    local running_color waiting_color idle_color_new unknown_color
    running_dot=$(get_tmux_option "@ai_agent_running_dot" "$DEFAULT_RUNNING_DOT")
    waiting_dot_opt=$(get_tmux_option "@ai_agent_waiting_dot" "$DEFAULT_WAITING_DOT")
    idle_dot_new=$(get_tmux_option "@ai_agent_idle_dot_new" "$DEFAULT_IDLE_DOT_NEW")
    unknown_dot=$(get_tmux_option "@ai_agent_unknown_dot" "$DEFAULT_UNKNOWN_DOT")
    running_color=$(get_tmux_option "@ai_agent_running_color" "$DEFAULT_RUNNING_COLOR")
    waiting_color=$(get_tmux_option "@ai_agent_waiting_color" "$DEFAULT_WAITING_COLOR")
    idle_color_new=$(get_tmux_option "@ai_agent_idle_color_new" "$DEFAULT_IDLE_COLOR_NEW")
    unknown_color=$(get_tmux_option "@ai_agent_unknown_color" "$DEFAULT_UNKNOWN_COLOR")

    # モード表示オプション
    local plan_mode_indicator accept_edits_indicator
    plan_mode_indicator=$(get_tmux_option "@ai_agent_plan_mode_indicator" "$DEFAULT_PLAN_MODE_INDICATOR")
    accept_edits_indicator=$(get_tmux_option "@ai_agent_accept_edits_indicator" "$DEFAULT_ACCEPT_EDITS_INDICATOR")

    # Export working threshold for session_tracker.sh
    export AI_AGENT_WORKING_THRESHOLD="$working_threshold"

    # Phase 4: Export show_codex for session_tracker.sh
    export SHOW_CODEX="$show_codex"

    # Generate output: "🍎#0 project-name... ●" 形式
    local output=""
    local first=1

    # Parse details (proc_type:terminal_emoji:pane_index:project_name:compat_status:base_status:elapsed:mode|...)
    IFS='|' read -ra entries <<< "$details"

    # Sort entries: first by status priority, then by terminal emoji priority, then by pane index
    # Build sortable list with priority prefix
    local sort_input=""
    for entry in "${entries[@]}"; do
        # 8フィールドからソート用にcompat_statusを抽出
        local temp="${entry}"
        local _pt="${temp%%:*}"; temp="${temp#*:}"
        local terminal_emoji="${temp%%:*}"; temp="${temp#*:}"
        local pane_index="${temp%%:*}"; temp="${temp#*:}"
        local _pn="${temp%%:*}"; temp="${temp#*:}"
        local status="${temp%%:*}"

        # Get priorities from helper functions
        local status_priority
        status_priority=$(get_status_priority "$status")
        local terminal_priority
        terminal_priority=$(get_terminal_priority "$terminal_emoji")

        # Extract numeric part from pane_index (e.g., "#3" -> "3")
        local pane_num="${pane_index#\#}"
        # Default to 999 if empty or not a number
        if ! [[ "$pane_num" =~ ^[0-9]+$ ]]; then
            pane_num=999
        fi

        # Append to sort input: status_priority:terminal_priority:pane_num:original_entry (with newline)
        sort_input+="$(printf '%d:%d:%03d:%s' "$status_priority" "$terminal_priority" "$pane_num" "$entry")"$'\n'
    done

    # Sort and extract original entries (Phase 5: 8 fields)
    local sorted_entries=()
    while IFS= read -r line; do
        [ -n "$line" ] && sorted_entries+=("$line")
    done < <(echo -n "$sort_input" | sort -t: -k1,1n -k2,2n -k3,3n | cut -d: -f4-)

    # Use sorted entries
    for entry in "${sorted_entries[@]}"; do
        local proc_type terminal_emoji pane_index project_name compat_status base_status elapsed mode
        local dot color prefix type_indicator mode_indicator elapsed_display

        # Parse entry (8フィールド: proc_type:terminal_emoji:pane_index:project_name:compat_status:base_status:elapsed:mode)
        local temp="${entry}"
        proc_type="${temp%%:*}"; temp="${temp#*:}"
        terminal_emoji="${temp%%:*}"; temp="${temp#*:}"
        pane_index="${temp%%:*}"; temp="${temp#*:}"
        project_name="${temp%%:*}"; temp="${temp#*:}"
        compat_status="${temp%%:*}"; temp="${temp#*:}"
        base_status="${temp%%:*}"; temp="${temp#*:}"
        elapsed="${temp%%:*}"; temp="${temp#*:}"
        mode="${temp}"

        # 4段階状態に応じてドットと色を選択
        case "$base_status" in
            running)
                dot="$running_dot"
                color="$running_color"
                ;;
            waiting)
                dot="$waiting_dot_opt"
                color="$waiting_color"
                ;;
            idle)
                dot="$idle_dot_new"
                color="$idle_color_new"
                ;;
            *)
                dot="$unknown_dot"
                color="$unknown_color"
                ;;
        esac

        # モードインジケータを構築
        mode_indicator=""
        if [ "$mode" = "plan_mode" ]; then
            mode_indicator="$plan_mode_indicator"
        elif [ "$mode" = "accept_edits" ]; then
            mode_indicator="$accept_edits_indicator"
        fi

        # 経過時間表示
        elapsed_display=""
        if [ -n "$elapsed" ]; then
            elapsed_display="$elapsed"
        fi

        # Phase 4: プロセスタイプに応じたアイコンを追加
        type_indicator=""
        if [ "$proc_type" = "codex" ] && [ -n "$codex_icon" ]; then
            type_indicator="$codex_icon"
        elif [ "$proc_type" = "claude" ] && [ -n "$claude_icon" ]; then
            type_indicator="$claude_icon"
        fi

        # プレフィックスを構築（プロセスタイプアイコン + ターミナル絵文字 + ペイン番号）
        prefix=""
        if [ -n "$type_indicator" ]; then
            prefix+="$type_indicator"
        fi
        if [ "$show_terminal" = "on" ] && [ -n "$terminal_emoji" ]; then
            prefix+="$terminal_emoji"
        fi
        if [ "$show_pane" = "on" ] && [ -n "$pane_index" ]; then
            prefix+="$pane_index"
        fi
        # プレフィックスがあれば末尾にスペースを追加
        if [ -n "$prefix" ]; then
            prefix+=" "
        fi

        # セパレータを追加（最初以外）
        if [ "$first" = "1" ]; then
            first=0
        else
            output+="$separator"
        fi

        # 色に応じた形式を調整
        local formatted_dot
        if [ -n "$color" ]; then
            formatted_dot="#[fg=$color]${dot}"
        else
            formatted_dot="${dot}"
        fi

        # 新形式: prefix + project_name + mode_indicator + dot + elapsed_time
        output+="${left_sep}${prefix}${project_name} ${mode_indicator}${formatted_dot}${elapsed_display}#[default]${right_sep}"
    done

    output+="  "  # Right margin

    echo "$output" > "$CACHE_FILE"
    cat "$CACHE_FILE"
}

main "$@"
