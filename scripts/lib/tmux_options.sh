#!/usr/bin/env bash
# tmux_options.sh - tmux option read/write utilities
# Source guard: prevent double-sourcing
if [ -n "${__LIB_TMUX_OPTIONS_LOADED:-}" ]; then return 0; fi
__LIB_TMUX_OPTIONS_LOADED=1

# ==============================================================================
# tmux Option Management
# ==============================================================================

# tmuxオプションの値を取得
# $1: オプション名
# $2: デフォルト値（オプション）
get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value="$(tmux show-option -gqv "$option" 2>/dev/null)"
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# tmuxオプションを設定
# $1: オプション名
# $2: 値
set_tmux_option() {
    tmux set-option -gq "$1" "$2"
}

# バッチ版: tmuxオプションの値を取得（キャッシュ使用）
# $1: オプション名
# $2: デフォルト値（オプション）
get_tmux_option_cached() {
    local option="$1"
    local default_value="$2"

    # キャッシュが初期化されていない場合は元の関数を使用
    if [ "$BATCH_INITIALIZED" != "1" ] || [ -z "$BATCH_TMUX_OPTIONS_FILE" ] || [ ! -f "$BATCH_TMUX_OPTIONS_FILE" ]; then
        get_tmux_option "$option" "$default_value"
        return
    fi

    # キャッシュから取得
    # フォーマット: "@ai_agent_option_name value"
    local option_value
    option_value=$(awk -v opt="$option" '$1 == opt { $1=""; print substr($0, 2); exit }' "$BATCH_TMUX_OPTIONS_FILE")

    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# バッチ版: 複数のtmuxオプションを一括取得（高速化）
# 引数: "オプション名=デフォルト値" のペアを複数指定
# 戻り値: "オプション名=値" 形式の行を出力（evalで変数に展開可能）
# 使用例: eval "$(get_tmux_options_bulk "@ai_agent_working_dot=working" "@ai_agent_idle_dot=idle")"
get_tmux_options_bulk() {
    # キャッシュが利用可能かチェック
    if [ "$BATCH_INITIALIZED" != "1" ] || [ -z "$BATCH_TMUX_OPTIONS_FILE" ] || [ ! -f "$BATCH_TMUX_OPTIONS_FILE" ]; then
        # フォールバック: 個別に取得
        for arg in "$@"; do
            local opt="${arg%%=*}"
            local default="${arg#*=}"
            local val
            val=$(get_tmux_option "$opt" "$default")
            # オプション名から@ai_agent_を除去して変数名に
            local varname="${opt#@ai_agent_}"
            echo "${varname}='${val}'"
        done
        return
    fi

    # 1回のawk呼び出しで全オプションを取得
    awk -v args="$*" '
    BEGIN {
        n = split(args, pairs, " ")
        for (i = 1; i <= n; i++) {
            split(pairs[i], kv, "=")
            opt = kv[1]
            default_val = kv[2]
            defaults[opt] = default_val
            # 変数名は@ai_agent_を除去
            varname = opt
            gsub(/^@ai_agent_/, "", varname)
            varnames[opt] = varname
        }
    }
    {
        opt = $1
        if (opt in defaults) {
            $1 = ""
            val = substr($0, 2)
            gsub(/'\''/, "'\''\\'\'''\''", val)  # シングルクォートをエスケープ
            print varnames[opt] "='\''" val "'\''"
            found[opt] = 1
        }
    }
    END {
        for (opt in defaults) {
            if (!(opt in found)) {
                val = defaults[opt]
                gsub(/'\''/, "'\''\\'\'''\''", val)
                print varnames[opt] "='\''" val "'\''"
            }
        }
    }
    ' "$BATCH_TMUX_OPTIONS_FILE"
}
