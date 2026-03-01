#!/usr/bin/env bash
# cache_shared.sh - Inter-process shared cache (5s TTL)
# Source guard: prevent double-sourcing
if [ -n "${__LIB_CACHE_SHARED_LOADED:-}" ]; then return 0; fi
__LIB_CACHE_SHARED_LOADED=1

# Dependencies
source "${BASH_SOURCE[0]%/*}/platform.sh"

# ==============================================================================
# Shared Cache Management (5s TTL)
# ==============================================================================
# 共有キャッシュ（ai_agent_status.sh → select_claude.sh）
# select_claude.sh の高速化のため、ai_agent_status.sh が収集した
# プロセス情報を共有キャッシュに書き出す
SHARED_CACHE_FILE="/tmp/ai_agent_shared_process_cache"
SHARED_CACHE_TTL=5  # キャッシュ有効期間（秒）

# 共有キャッシュにプロセス情報を書き出す
# $1: プロセス情報（get_all_claude_info_batch形式: pid|pane_id|session|window|tty|terminal|cwd）
# フォーマット:
#   1行目: タイムスタンプ
#   2行目: tmuxオプション（TAB区切り: working_dot idle_dot terminal_iterm terminal_wezterm terminal_ghostty terminal_windows terminal_vscode terminal_alacritty terminal_unknown）
#   3行目: TTY stat情報（"tty_path mtime;tty_path2 mtime2;..."形式）
#   4行目以降: プロセス情報
write_shared_cache() {
    local process_info="$1"
    local timestamp
    timestamp=$(get_current_timestamp)

    # tmuxオプションを一括取得（9回の呼び出しを1回に最適化）
    local tmux_opts
    tmux_opts=$(tmux show-options -g 2>/dev/null | awk '
        /@ai_agent_working_dot/ { gsub(/@ai_agent_working_dot /,""); wd=$0 }
        /@ai_agent_idle_dot/ { gsub(/@ai_agent_idle_dot /,""); id=$0 }
        /@ai_agent_terminal_iterm/ { gsub(/@ai_agent_terminal_iterm /,""); ti=$0 }
        /@ai_agent_terminal_wezterm/ { gsub(/@ai_agent_terminal_wezterm /,""); tw=$0 }
        /@ai_agent_terminal_ghostty/ { gsub(/@ai_agent_terminal_ghostty /,""); tg=$0 }
        /@ai_agent_terminal_windows/ { gsub(/@ai_agent_terminal_windows /,""); twin=$0 }
        /@ai_agent_terminal_vscode/ { gsub(/@ai_agent_terminal_vscode /,""); tvs=$0 }
        /@ai_agent_terminal_alacritty/ { gsub(/@ai_agent_terminal_alacritty /,""); tala=$0 }
        /@ai_agent_terminal_unknown/ { gsub(/@ai_agent_terminal_unknown /,""); tu=$0 }
        END {
            if (wd=="") wd="🤖"
            if (id=="") id="🔔"
            if (ti=="") ti="🍎"
            if (tw=="") tw="⚡"
            if (tg=="") tg="👻"
            if (twin=="") twin="🪟"
            if (tvs=="") tvs="📝"
            if (tala=="") tala="🔲"
            if (tu=="") tu="❓"
            print wd "\t" id "\t" ti "\t" tw "\t" tg "\t" twin "\t" tvs "\t" tala "\t" tu
        }
    ')

    # TTY stat情報を収集（プロセス情報からTTYパスを抽出）
    local tty_stat=""
    if [ -n "$process_info" ]; then
        local tty_paths
        tty_paths=$(echo "$process_info" | awk -F'|' '{print $5}' | sort -u | grep -v '^$')
        if [ -n "$tty_paths" ]; then
            # stat結果を"path mtime;path2 mtime2"形式に変換
            if [[ "$(get_os)" == "Darwin" ]]; then
                tty_stat=$(echo "$tty_paths" | xargs stat -f "%N %m" 2>/dev/null | tr '\n' ';' | sed 's/;$//')
            else
                tty_stat=$(echo "$tty_paths" | xargs stat -c "%n %Y" 2>/dev/null | tr '\n' ';' | sed 's/;$//')
            fi
        fi
    fi

    {
        echo "$timestamp"
        echo "$tmux_opts"
        echo "$tty_stat"
        echo "$process_info"
    } > "$SHARED_CACHE_FILE" 2>/dev/null
}

# fzf表示用プリレンダーファイルを書き出す
# $1: process_info (pid|pane_id|session|window|tty|terminal|cwd 形式、複数行可)
# $2: status_cache パス (デフォルト: /tmp/ai_agent_pane_status_cache)
# $3: 出力ファイルパス (デフォルト: /tmp/ai_agent_fzf_prerender)
# 出力形式: 各行 "表示文字列\tpane_id"
# atomic write: .tmp → mv -f
# macOS bash 3.2 互換 (declare -A 不可)
write_fzf_prerender() {
    local process_info="$1"
    local status_cache="${2:-/tmp/ai_agent_pane_status_cache}"
    local output_file="${3:-/tmp/ai_agent_fzf_prerender}"
    local tmp_file="${output_file}.tmp"

    # 空入力は空ファイルを生成して正常終了
    if [ -z "$process_info" ]; then
        > "$tmp_file" 2>/dev/null && mv -f "$tmp_file" "$output_file" 2>/dev/null
        return 0
    fi

    # awk で process_info と status_cache を結合して表示文字列を生成
    # macOS bash 3.2 互換: awk 内部でハッシュを使用
    awk -F'|' -v status_cache="$status_cache" '
    BEGIN {
        # status_cache を読み込み: pane_id|detailed_status
        while ((getline line < status_cache) > 0) {
            n = index(line, "|")
            if (n > 0) {
                pid_key = substr(line, 1, n - 1)
                detailed = substr(line, n + 1)
                # base_status を抽出 (running:2m30s → running)
                m = index(detailed, ":")
                if (m > 0) {
                    base_st[pid_key] = substr(detailed, 1, m - 1)
                    rest = substr(detailed, m + 1)
                    # elapsed と mode を抽出
                    m2 = index(rest, ":")
                    if (m2 > 0) {
                        pane_elapsed[pid_key] = substr(rest, 1, m2 - 1)
                        pane_mode[pid_key] = substr(rest, m2 + 1)
                    } else if (rest == "plan_mode" || rest == "accept_edits") {
                        pane_elapsed[pid_key] = ""
                        pane_mode[pid_key] = rest
                    } else {
                        pane_elapsed[pid_key] = rest
                        pane_mode[pid_key] = ""
                    }
                } else {
                    base_st[pid_key] = detailed
                    pane_elapsed[pid_key] = ""
                    pane_mode[pid_key] = ""
                }
            }
        }
        close(status_cache)
    }
    {
        pane_id = $2
        if (pane_id == "" || pane_id in seen) next
        seen[pane_id] = 1

        session_name = $3
        window_index = $4
        terminal_name = $6
        cwd = $7

        # ターミナル絵文字 (case相当をif-elseで実現)
        if (terminal_name == "iTerm2" || terminal_name == "Terminal") {
            emoji = "🍎"
        } else if (terminal_name == "WezTerm") {
            emoji = "⚡"
        } else if (terminal_name == "Ghostty") {
            emoji = "👻"
        } else if (terminal_name == "WindowsTerminal") {
            emoji = "🪟"
        } else if (terminal_name == "VSCode") {
            emoji = "📝"
        } else if (terminal_name == "Alacritty") {
            emoji = "🔲"
        } else {
            emoji = "❓"
        }

        # プロジェクト名 (cwd の最後のディレクトリ)
        n = split(cwd, parts, "/")
        proj = parts[n]
        if (proj == "" || proj == "/") proj = "claude"
        if (length(proj) > 18) proj = substr(proj, 1, 15) "..."

        # ステータスアイコン
        st = (pane_id in base_st) ? base_st[pane_id] : "unknown"
        if (st == "running") {
            icon = "🟢"
        } else if (st == "waiting") {
            icon = "🟡"
        } else if (st == "idle") {
            icon = "🔵"
        } else {
            icon = "❓"
        }

        # 経過時間・モード表示
        elapsed = (pane_id in pane_elapsed) ? pane_elapsed[pane_id] : ""
        mode = (pane_id in pane_mode) ? pane_mode[pane_id] : ""

        status_prefix = icon
        if (elapsed != "") status_prefix = status_prefix elapsed
        if (mode == "plan_mode") status_prefix = status_prefix " ⏸"
        else if (mode == "accept_edits") status_prefix = status_prefix " ⏵⏵"

        # 表示行を構築
        pidx = "#" window_index
        line = status_prefix " " emoji " " pidx " " proj
        if (session_name != "") line = line " [" session_name "]"

        print line "\t" pane_id
    }
    ' <<< "$process_info" > "$tmp_file" 2>/dev/null

    mv -f "$tmp_file" "$output_file" 2>/dev/null
    return 0
}

# 共有キャッシュからプロセス情報行のみを取得
# 戻り値: プロセス情報（4行目以降）
read_shared_cache_process_info() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return
    fi

    # 4行目以降がプロセス情報
    tail -n +4 "$SHARED_CACHE_FILE" 2>/dev/null
}

# 共有キャッシュからTTY stat情報を取得
# 戻り値: "tty_path mtime;tty_path2 mtime2;..."形式
read_shared_cache_tty_stat() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return
    fi

    # 3行目がTTY stat情報
    sed -n '3p' "$SHARED_CACHE_FILE" 2>/dev/null
}

# 共有キャッシュからtmuxオプション行のみを取得
# 戻り値: "working_dot\tidle_dot\tterminal_iterm\tterminal_wezterm\tterminal_ghostty\tterminal_unknown"
read_shared_cache_tmux_opts() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return
    fi

    # 2行目がtmuxオプション
    sed -n '2p' "$SHARED_CACHE_FILE" 2>/dev/null
}

# 共有キャッシュを一括読み込み（最適化版）
# 1回のファイル読み込みで全フィールドを取得（awkで1パス処理）
# 戻り値: 成功時0（グローバル変数に値を設定）、失敗時1
# 設定されるグローバル変数:
#   _SHARED_CACHE_OPTIONS: tmuxオプション
#   _SHARED_CACHE_TTY_STAT: TTY stat情報
#   _SHARED_CACHE_PROCESSES: プロセス情報
read_shared_cache_all() {
    _SHARED_CACHE_OPTIONS=""
    _SHARED_CACHE_TTY_STAT=""
    _SHARED_CACHE_PROCESSES=""

    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        return 1
    fi

    local current_time="${EPOCHSECONDS:-$(date +%s)}"

    # awkで1パス処理: タイムスタンプ検証と全フィールド抽出を同時に実行
    local result
    result=$(awk -v now="$current_time" -v ttl="$SHARED_CACHE_TTL" '
        NR==1 {
            if (now - $0 > ttl) { print "EXPIRED"; exit }
            next
        }
        NR==2 { opts=$0; next }
        NR==3 { tty=$0; next }
        NR>3 { procs = procs (procs=="" ? "" : "\n") $0 }
        END {
            if (opts != "") {
                print "OPTIONS:" opts
                print "TTY:" tty
                print "PROCESSES:" procs
            }
        }
    ' "$SHARED_CACHE_FILE" 2>/dev/null)

    if [ "$result" = "EXPIRED" ] || [ -z "$result" ]; then
        return 1
    fi

    # 結果をパース
    _SHARED_CACHE_OPTIONS="${result#OPTIONS:}"
    _SHARED_CACHE_OPTIONS="${_SHARED_CACHE_OPTIONS%%TTY:*}"
    _SHARED_CACHE_OPTIONS="${_SHARED_CACHE_OPTIONS%$'\n'}"

    local rest="${result#*TTY:}"
    _SHARED_CACHE_TTY_STAT="${rest%%PROCESSES:*}"
    _SHARED_CACHE_TTY_STAT="${_SHARED_CACHE_TTY_STAT%$'\n'}"

    _SHARED_CACHE_PROCESSES="${rest#*PROCESSES:}"

    return 0
}

# 共有キャッシュの年齢を取得（秒）
# 戻り値: キャッシュの経過秒数、存在しない場合は999999
get_shared_cache_age() {
    if [ ! -f "$SHARED_CACHE_FILE" ]; then
        echo 999999
        return
    fi

    local current_time
    current_time=$(get_current_timestamp)

    local cache_time
    cache_time=$(head -1 "$SHARED_CACHE_FILE" 2>/dev/null)

    if [ -z "$cache_time" ]; then
        echo 999999
        return
    fi

    echo $((current_time - cache_time))
}

# 共有キャッシュが有効かどうかをチェック
# 戻り値: 0=有効（TTL以内）、1=無効（期限切れまたは存在しない）
is_shared_cache_valid() {
    local age
    age=$(get_shared_cache_age)
    [ "$age" -le "$SHARED_CACHE_TTL" ]
}

# ==============================================================================
# Backward Compatibility Aliases
# ==============================================================================
# Aliases for old function names (from shared.sh before refactor)
read_shared_cache_options() { read_shared_cache_tmux_opts "$@"; }
read_shared_cache_processes() { read_shared_cache_process_info "$@"; }

# Old read_shared_cache() returned all data (options + processes)
# Now split into read_shared_cache_all() which is more efficient
read_shared_cache() {
    if read_shared_cache_all; then
        # Return options on first line, then processes
        echo "$_SHARED_CACHE_OPTIONS"
        echo "$_SHARED_CACHE_PROCESSES"
    fi
}
