#!/usr/bin/env bash
# tests/test_codex_detection.sh - Codex detection tests

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# テスト結果カウンター
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# テストユーティリティ関数
PASS() {
    local message="${1:-}"
    ((TESTS_RUN++))
    echo -e "${GREEN}PASS${NC}: $message"
    ((TESTS_PASSED++))
    return 0
}

FAIL() {
    local message="${1:-}"
    ((TESTS_RUN++))
    echo -e "${RED}FAIL${NC}: $message"
    ((TESTS_FAILED++))
    return 1
}

SKIP() {
    local message="${1:-}"
    ((TESTS_RUN++))
    echo -e "${YELLOW}SKIP${NC}: $message"
    ((TESTS_SKIPPED++))
    return 0
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_function_exists() {
    local func_name="$1"
    local message="${2:-}"
    ((TESTS_RUN++))

    if declare -f "$func_name" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Function '$func_name' does not exist"
        ((TESTS_FAILED++))
        return 1
    fi
}

# --- テストケース ---

# T1.1: get_ai_pids 関数が存在する
test_get_ai_pids_function_exists() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    assert_function_exists "get_ai_pids" "get_ai_pids function exists"
}

# T1.2: get_ai_pids がフィルターなしで両方を返す
test_get_ai_pids_returns_both_types() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_ai_pids)
    # 結果が空か、数値のスペース区切りであることを確認
    if [ -z "$result" ] || [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        PASS "get_ai_pids returns valid format (empty or space-separated PIDs)"
    else
        FAIL "Invalid format: $result"
    fi
}

# T1.3: get_ai_pids "claude" フィルターが動作する
test_get_ai_pids_claude_filter() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_ai_pids "claude")
    # claude フィルターの結果が空か数値のみ
    if [ -z "$result" ] || [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        PASS "get_ai_pids with 'claude' filter returns valid format"
    else
        FAIL "Invalid format with claude filter: $result"
    fi
}

# T1.4: get_ai_pids "codex" フィルターが動作する
test_get_ai_pids_codex_filter() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_ai_pids "codex")
    if [ -z "$result" ] || [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        PASS "get_ai_pids with 'codex' filter returns valid format"
    else
        FAIL "Invalid format with codex filter: $result"
    fi
}

# T1.5: get_process_type 関数が存在する
test_get_process_type_function_exists() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    assert_function_exists "get_process_type" "get_process_type function exists"
}

# T1.6: get_process_type_cached 関数が存在する
test_get_process_type_cached_function_exists() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    assert_function_exists "get_process_type_cached" "get_process_type_cached function exists"
}

# T1.7: get_claude_pids は後方互換性を保つ
test_get_claude_pids_backward_compatible() {
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    local result
    result=$(get_claude_pids)
    # 既存のフォーマットを維持: 空か数値のスペース区切り
    if [ -z "$result" ] || [[ "$result" =~ ^[0-9\ ]+$ ]]; then
        PASS "get_claude_pids maintains backward compatibility"
    else
        FAIL "get_claude_pids format changed: $result"
    fi
}

# T1.8: batch 出力に process_type フィールドが含まれる
test_batch_output_includes_process_type() {
    source "$PROJECT_ROOT/scripts/shared.sh"
    source "$PROJECT_ROOT/scripts/session_tracker.sh"
    init_batch_cache
    local result
    result=$(get_all_claude_info_batch)
    # 結果が空でなければ、8フィールド目にprocess_typeがある
    if [ -n "$result" ]; then
        local field_count
        field_count=$(echo "$result" | head -1 | awk -F'|' '{print NF}')
        assert_equals "8" "$field_count" "batch output has 8 fields (including process_type)"
    else
        PASS "No processes running (acceptable)"
    fi
    cleanup_batch_cache
}

# --- テスト実行 ---

echo "========================================"
echo "Running Codex Detection Tests"
echo "========================================"
echo

test_get_ai_pids_function_exists
test_get_ai_pids_returns_both_types
test_get_ai_pids_claude_filter
test_get_ai_pids_codex_filter
test_get_process_type_function_exists
test_get_process_type_cached_function_exists
test_get_claude_pids_backward_compatible
test_batch_output_includes_process_type

echo
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total:   $TESTS_RUN"
echo -e "Passed:  ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:  ${RED}$TESTS_FAILED${NC}"
echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
echo "========================================"

# 失敗があれば終了コード1を返す
[ "$TESTS_FAILED" -eq 0 ]
