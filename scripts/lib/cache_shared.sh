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
# 共有キャッシュ（claudecode_status.sh → select_claude.sh）
# select_claude.sh の高速化のため、claudecode_status.sh が収集した
# プロセス情報を共有キャッシュに書き出す
SHARED_CACHE_FILE="/tmp/claudecode_shared_process_cache"
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
        /@claudecode_working_dot/ { gsub(/@claudecode_working_dot /,""); wd=$0 }
        /@claudecode_idle_dot/ { gsub(/@claudecode_idle_dot /,""); id=$0 }
        /@claudecode_terminal_iterm/ { gsub(/@claudecode_terminal_iterm /,""); ti=$0 }
        /@claudecode_terminal_wezterm/ { gsub(/@claudecode_terminal_wezterm /,""); tw=$0 }
        /@claudecode_terminal_ghostty/ { gsub(/@claudecode_terminal_ghostty /,""); tg=$0 }
        /@claudecode_terminal_windows/ { gsub(/@claudecode_terminal_windows /,""); twin=$0 }
        /@claudecode_terminal_vscode/ { gsub(/@claudecode_terminal_vscode /,""); tvs=$0 }
        /@claudecode_terminal_alacritty/ { gsub(/@claudecode_terminal_alacritty /,""); tala=$0 }
        /@claudecode_terminal_unknown/ { gsub(/@claudecode_terminal_unknown /,""); tu=$0 }
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
