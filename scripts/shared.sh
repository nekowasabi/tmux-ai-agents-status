#!/usr/bin/env bash
# shared.sh - 共通ユーティリティ関数（ファサード）
# tmuxオプションの読み書きとプラットフォーム共通処理を提供
# バッチ処理用キャッシュ機能を含む（Bash 3.2互換）
#
# NOTE: 実装は scripts/lib/ 以下のモジュールに分割済み
# このファイルは後方互換性のためのファサードです

# Resolve lib directory relative to this script
_SHARED_LIB_DIR="${BASH_SOURCE[0]%/*}/lib"

# Source all modules in dependency order
source "${_SHARED_LIB_DIR}/platform.sh"
source "${_SHARED_LIB_DIR}/tmux_options.sh"
source "${_SHARED_LIB_DIR}/terminal.sh"
source "${_SHARED_LIB_DIR}/cache_shared.sh"
source "${_SHARED_LIB_DIR}/cache_batch.sh"
source "${_SHARED_LIB_DIR}/pane_utils.sh"
