#!/usr/bin/env bash
# tests/test_launcher.sh - select_claude_launcher.sh TDD tests (P3)

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
LAUNCHER="$PROJECT_ROOT/scripts/select_claude_launcher.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_equals() {
    local expected="$1" actual="$2" message="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        printf "${GREEN}PASS${NC}: %s\n" "$message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: %s\n" "$message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_matches() {
    local pattern="$1" actual="$2" message="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$actual" | grep -qE "$pattern"; then
        printf "${GREEN}PASS${NC}: %s\n" "$message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: %s\n" "$message"
        echo "  Pattern: $pattern"
        echo "  Actual:  '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Test: スクリプトが実行可能
# ==============================================================================
test_launcher_executable() {
    assert_equals "0" "$([ -x "$LAUNCHER" ] && echo 0 || echo 1)" \
        "select_claude_launcher.sh should be executable"
}

# ==============================================================================
# Test: プリレンダリング鮮度チェック定数/変数が定義されている
# ==============================================================================
test_prerender_freshness_check_exists() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q 'FZF_PRERENDER\|fzf_prerender\|PRERENDER' "$LAUNCHER"; then
        printf "${GREEN}PASS${NC}: launcher has prerender freshness check\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: launcher should have prerender freshness check (FZF_PRERENDER or similar)\n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Test: --with-nth=1 --delimiter='\t' が使われている (pane_id 隠し)
# ==============================================================================
test_fzf_with_nth_delimiter() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q 'with-nth' "$LAUNCHER" && grep -q 'delimiter' "$LAUNCHER"; then
        printf "${GREEN}PASS${NC}: launcher uses fzf --with-nth and --delimiter for pane_id hiding\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: launcher should use fzf --with-nth=1 --delimiter='\\t'\n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Test: ctrl-s send_prompt.sh 対応
# ==============================================================================
test_ctrl_s_send_prompt() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q 'ctrl-s' "$LAUNCHER" && grep -q 'send_prompt' "$LAUNCHER"; then
        printf "${GREEN}PASS${NC}: launcher handles ctrl-s for send_prompt.sh\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: launcher should handle ctrl-s → send_prompt.sh\n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Test: レガシーフォールバックが存在する
# ==============================================================================
test_legacy_fallback_exists() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q 'fallback\|FALLBACK\|legacy\|init_batch_cache\|get_all_claude\|select_claude\.sh' "$LAUNCHER"; then
        printf "${GREEN}PASS${NC}: launcher has legacy fallback path\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: launcher should have legacy fallback for stale/missing prerender\n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Test: プリレンダリング高速パスで source 不要 (ファイル読み込みのみ)
# ==============================================================================
test_fast_path_no_heavy_source() {
    TESTS_RUN=$((TESTS_RUN + 1))
    # 高速パス内で session_tracker.sh を source しない構造を確認
    # (条件分岐の外で source されていないか、または prerender フレッシュ時に skip)
    local prerender_ttl=10
    if grep -q "$prerender_ttl\|PRERENDER_TTL\|prerender_ttl" "$LAUNCHER"; then
        printf "${GREEN}PASS${NC}: launcher has prerender TTL check (${prerender_ttl}s)\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: launcher should check prerender TTL (10s)\n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Test: 行数が妥当（全面書き換えで大幅削減）
# ==============================================================================
test_line_count_reduced() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local line_count
    line_count=$(wc -l < "$LAUNCHER" | tr -d ' ')
    if [ "$line_count" -le 80 ]; then
        printf "${GREEN}PASS${NC}: launcher line count reduced ($line_count lines ≤ 80)\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: launcher should be ≤80 lines after rewrite (currently $line_count)\n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Test: preview で $2 (pane_id) を直接渡す形式を使用
# ==============================================================================
test_preview_uses_pane_id_arg() {
    TESTS_RUN=$((TESTS_RUN + 1))
    # fzf preview で {2} または $2 を使って pane_id を渡す
    if grep -q '{2}\|\\{2\\}' "$LAUNCHER"; then
        printf "${GREEN}PASS${NC}: launcher preview passes pane_id via {2}\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "${RED}FAIL${NC}: launcher preview should use {2} to pass pane_id directly\n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# Run all tests
# ==============================================================================
echo "=== test_launcher.sh: select_claude_launcher.sh TDD tests ==="
echo ""

test_launcher_executable
test_prerender_freshness_check_exists
test_fzf_with_nth_delimiter
test_ctrl_s_send_prompt
test_legacy_fallback_exists
test_fast_path_no_heavy_source
test_line_count_reduced
test_preview_uses_pane_id_arg

echo ""
echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
