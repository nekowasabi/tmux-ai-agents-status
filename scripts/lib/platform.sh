#!/usr/bin/env bash
# platform.sh - Platform detection: get_os, get_file_mtime, get_current_timestamp
# Source guard: prevent double-sourcing
if [ -n "${__LIB_PLATFORM_LOADED:-}" ]; then return 0; fi
__LIB_PLATFORM_LOADED=1

# ==============================================================================
# Cache Variables
# ==============================================================================
# OS判定をキャッシュ（unameの呼び出しを1回に削減）
_CACHED_OS="${_CACHED_OS:-}"

# ==============================================================================
# Platform Detection and Utilities
# ==============================================================================

# OS判定をキャッシュして返す（unameの呼び出しを最小化）
get_os() {
    if [ -z "$_CACHED_OS" ]; then
        _CACHED_OS=$(uname)
    fi
    echo "$_CACHED_OS"
}

# クロスプラットフォーム対応のファイル更新時刻取得
# $1: ファイルパス
# 戻り値: Unixタイムスタンプ（秒）
get_file_mtime() {
    local file="$1"
    if [[ "$(get_os)" == "Darwin" ]]; then
        # macOS
        stat -f %m "$file" 2>/dev/null
    else
        # Linux
        stat -c %Y "$file" 2>/dev/null
    fi
}

# 現在のUnixタイムスタンプを取得（EPOCHSECONDSがあれば使用）
get_current_timestamp() {
    if [ -n "${EPOCHSECONDS:-}" ]; then
        echo "$EPOCHSECONDS"
    else
        date +%s
    fi
}
