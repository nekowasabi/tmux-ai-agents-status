#!/usr/bin/env bash
# session_tracker.sh - Claude Codeセッション追跡
# 各セッションのworking/idle状態を判定

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/shared.sh"

# working判定の閾値（秒）
# この秒数以内にdebugファイルが更新されていればworking
WORKING_THRESHOLD="${CLAUDECODE_WORKING_THRESHOLD:-5}"

# Claude Codeプロセスの PID 一覧を取得
# 戻り値: スペース区切りのPID一覧
get_claude_pids() {
    local pids

    # 方法1: pgrep（最も確実・高速）
    pids=$(pgrep -d ' ' "^claude$" 2>/dev/null)

    if [ -z "$pids" ]; then
        # 方法2: ps経由（フォールバック）
        pids=$(ps aux 2>/dev/null | grep -E "[n]ode.*claude" | awk '{print $2}' | tr '\n' ' ')
    fi

    echo "$pids"
}

# PIDからtmuxペイン情報を取得
# $1: PID
# 戻り値: "pane_id:pane_name" または空文字列（見つからない場合）
get_pane_info_for_pid() {
    local target_pid="$1"

    # tmuxが起動していない場合は空を返す
    if ! tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null >/dev/null; then
        echo ""
        return
    fi

    # 各tmuxペインを走査してPIDを確認
    while IFS=' ' read -r pane_pid pane_id; do
        # ペインのプロセスツリーをチェック
        # 対象PIDがペインのPIDの子孫かを確認
        if is_descendant_of "$target_pid" "$pane_pid"; then
            # ペイン名を取得（window名を使用）
            local pane_name
            pane_name=$(tmux display-message -p -t "$pane_id" '#{window_name}' 2>/dev/null)
            if [ -n "$pane_name" ]; then
                # pane_id:pane_name 形式で返す
                echo "${pane_id}:${pane_name}"
                return
            fi
        fi
    done < <(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null)

    # 見つからない場合は空
    echo ""
}

# 後方互換性のためのラッパー
get_pane_name_for_pid() {
    local info
    info=$(get_pane_info_for_pid "$1")
    if [ -n "$info" ]; then
        echo "${info#*:}"
    else
        echo ""
    fi
}

# PIDからプロジェクト名（作業ディレクトリ名）を取得
# $1: PID
# $2: 最大文字数（デフォルト: 18）
# 戻り値: プロジェクト名（長い場合は省略）
get_project_name_for_pid() {
    local pid="$1"
    local max_length="${2:-18}"
    local cwd_link="/proc/$pid/cwd"
    local project_name=""

    # /proc/PID/cwd から作業ディレクトリを取得
    if [ -L "$cwd_link" ]; then
        local cwd
        cwd=$(readlink "$cwd_link" 2>/dev/null)
        if [ -n "$cwd" ]; then
            project_name=$(basename "$cwd")
        fi
    fi

    # フォールバック: pwdx コマンドを使用
    if [ -z "$project_name" ]; then
        local cwd
        cwd=$(pwdx "$pid" 2>/dev/null | cut -d: -f2 | tr -d ' ')
        if [ -n "$cwd" ]; then
            project_name=$(basename "$cwd")
        fi
    fi

    # 取得できない場合はデフォルト名
    if [ -z "$project_name" ] || [ "$project_name" = "/" ]; then
        project_name="claude"
    fi

    # 長すぎる場合は省略
    if [ "${#project_name}" -gt "$max_length" ]; then
        project_name="${project_name:0:$((max_length - 3))}..."
    fi

    echo "$project_name"
}

# プロセスが別のプロセスの子孫かを確認
# $1: チェック対象PID
# $2: 祖先候補PID
# 戻り値: 0 (子孫), 1 (非子孫)
is_descendant_of() {
    local check_pid="$1"
    local ancestor_pid="$2"
    local current_pid="$check_pid"

    # 同一の場合はtrue
    if [ "$current_pid" = "$ancestor_pid" ]; then
        return 0
    fi

    # 親プロセスを辿る（最大20階層）
    local max_depth=20
    local depth=0
    while [ "$depth" -lt "$max_depth" ]; do
        local ppid
        ppid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')

        # 親が取得できない or PID 1 に到達
        if [ -z "$ppid" ] || [ "$ppid" = "1" ] || [ "$ppid" = "0" ]; then
            return 1
        fi

        # 祖先候補と一致
        if [ "$ppid" = "$ancestor_pid" ]; then
            return 0
        fi

        current_pid="$ppid"
        ((depth++))
    done

    return 1
}

# 単一プロセスのworking状態を判定
# $1: PID
# 戻り値: "working" または "idle"
check_process_status() {
    local pid="$1"
    local current_time
    current_time=$(get_current_timestamp)
    local debug_dir="$HOME/.claude/debug"

    # Linux: /proc/{pid}/fd から開いているdebugファイルを特定
    if [ -d "/proc/$pid/fd" ]; then
        local debug_file
        debug_file=$(ls -l "/proc/$pid/fd" 2>/dev/null | grep "$debug_dir" | head -1 | awk '{print $NF}')

        if [ -n "$debug_file" ] && [ -f "$debug_file" ]; then
            local mtime
            mtime=$(get_file_mtime "$debug_file")
            if [ -n "$mtime" ]; then
                local diff=$((current_time - mtime))
                # 閾値内ならworking、超過ならidle
                if [ "$diff" -lt "$WORKING_THRESHOLD" ]; then
                    echo "working"
                    return
                else
                    echo "idle"
                    return
                fi
            fi
        fi
    fi

    # フォールバック: CPU使用率で判定（5%以上ならworking、それ以下ならidle）
    local cpu
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' | cut -d. -f1)
    if [ -n "$cpu" ] && [ "$cpu" -gt 5 ] 2>/dev/null; then
        echo "working"
        return
    fi

    # 全ての判定でworkingでない場合はidle
    echo "idle"
}

# 全セッションの状態を取得（旧形式・後方互換用）
# 戻り値: "working:N,idle:M" 形式
get_session_states() {
    local pids working_count=0 idle_count=0
    pids=$(get_claude_pids)

    if [ -z "$pids" ]; then
        echo "working:0,idle:0"
        return
    fi

    for pid in $pids; do
        local status
        status=$(check_process_status "$pid")
        if [ "$status" = "working" ]; then
            ((working_count++))
        else
            ((idle_count++))
        fi
    done

    echo "working:$working_count,idle:$idle_count"
}

# 全セッションの詳細情報を取得（新形式）
# 戻り値: "project_name:status|project_name:status|..." 形式
# statusは "working" または "idle"
# 同じプロジェクト名でも異なるセッションの場合は番号付きで表示
get_session_details() {
    local pids
    pids=$(get_claude_pids)

    if [ -z "$pids" ]; then
        echo ""
        return
    fi

    local details=""
    local seen_pane_ids=""
    declare -A name_counts  # プロジェクト名ごとのカウント

    for pid in $pids; do
        local pane_info pane_id project_name status

        # ペイン情報を取得（重複チェック用）
        pane_info=$(get_pane_info_for_pid "$pid")
        if [ -z "$pane_info" ]; then
            pane_id="unknown_$$_$pid"
        else
            pane_id="${pane_info%%:*}"
        fi

        # 同じペインIDの重複を避ける
        if [[ "$seen_pane_ids" == *"|$pane_id|"* ]]; then
            continue
        fi
        seen_pane_ids+="|$pane_id|"

        # プロジェクト名を取得（作業ディレクトリ名）
        project_name=$(get_project_name_for_pid "$pid")

        # プロジェクト名の出現回数をカウント
        if [ -n "${name_counts[$project_name]:-}" ]; then
            ((name_counts[$project_name]++))
            # 同じ名前が既に存在する場合、番号を付ける
            project_name="${project_name}#${name_counts[$project_name]}"
        else
            name_counts[$project_name]=1
        fi

        # 状態を取得
        status=$(check_process_status "$pid")

        # 詳細を追加
        if [ -n "$details" ]; then
            details+="|"
        fi
        details+="${project_name}:${status}"
    done

    echo "$details"
}

# 直接実行時のテスト用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Claude PIDs: $(get_claude_pids)"
    echo "Session states: $(get_session_states)"
fi
