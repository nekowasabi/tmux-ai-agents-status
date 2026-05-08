#!/usr/bin/env bash
# Why: stub get_tmux_option/tmux instead of integration test — pane_title resolution is a pure routing function; mock-based unit tests give fastest feedback.
# tests/test_pane_name.sh - Unit tests for scripts/lib/pane_name.sh

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# テスト結果カウンター
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# テストユーティリティ関数
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

# =============================================================================
# Mock setup
# =============================================================================
# Why: stub get_tmux_option as a function so pane_name.sh's call resolves to
# our test value without touching the real tmux server. Same approach for tmux
# itself — we override the binary lookup via a shell function.

# State variables driven per-test.
MOCK_SYNC_ENABLED="off"
MOCK_PANE_TITLE=""

get_tmux_option() {
    local option="$1"
    local default="${2:-}"
    if [ "$option" = "@ai_agent_pane_title_sync" ]; then
        echo "$MOCK_SYNC_ENABLED"
        return 0
    fi
    echo "$default"
}

# Shadow the tmux command. pane_name.sh uses:
#   tmux display-message -p -t "$pane_id" '#{pane_title}'
# We only react to that specific subcommand and emit MOCK_PANE_TITLE.
tmux() {
    if [ "${1:-}" = "display-message" ]; then
        echo "$MOCK_PANE_TITLE"
        return 0
    fi
    return 0
}

# Source the unit under test AFTER the mocks are defined so any lookups
# during sourcing (none here, but defensive) hit the stubs.
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/pane_name.sh"

# =============================================================================
# Test cases
# =============================================================================

test_optin_off_returns_fallback() {
    echo -e "${YELLOW}--- Test: opt-in OFF returns fallback even when pane_title set ---${NC}"
    MOCK_SYNC_ENABLED="off"
    MOCK_PANE_TITLE="my-renamed-pane"
    local result
    result=$(get_pane_display_name "%1" "fallback-name" 18)
    assert_equals "fallback-name" "$result" "opt-in off ignores pane_title"
}

test_optin_on_empty_title_returns_fallback() {
    echo -e "${YELLOW}--- Test: opt-in ON with empty pane_title returns fallback ---${NC}"
    MOCK_SYNC_ENABLED="on"
    MOCK_PANE_TITLE=""
    local result
    result=$(get_pane_display_name "%1" "fallback-name" 18)
    assert_equals "fallback-name" "$result" "empty pane_title falls through to fallback"
}

test_optin_on_default_zsh_returns_fallback() {
    echo -e "${YELLOW}--- Test: opt-in ON with pane_title=zsh returns fallback ---${NC}"
    MOCK_SYNC_ENABLED="on"
    MOCK_PANE_TITLE="zsh"
    local result
    result=$(get_pane_display_name "%1" "fallback-name" 18)
    assert_equals "fallback-name" "$result" "default title 'zsh' is treated as non-rename"
}

test_optin_on_default_claude_returns_fallback() {
    echo -e "${YELLOW}--- Test: opt-in ON with pane_title=claude returns fallback ---${NC}"
    MOCK_SYNC_ENABLED="on"
    MOCK_PANE_TITLE="claude"
    local result
    result=$(get_pane_display_name "%1" "fallback-name" 18)
    assert_equals "fallback-name" "$result" "default title 'claude' is treated as non-rename"
}

test_optin_on_renamed_title_returns_title() {
    echo -e "${YELLOW}--- Test: opt-in ON with renamed pane_title returns title ---${NC}"
    MOCK_SYNC_ENABLED="on"
    MOCK_PANE_TITLE="feature-x"
    local result
    result=$(get_pane_display_name "%1" "fallback-name" 18)
    assert_equals "feature-x" "$result" "renamed pane_title is returned"
}

test_optin_on_long_title_is_truncated() {
    echo -e "${YELLOW}--- Test: opt-in ON with long pane_title gets truncated with '...' ---${NC}"
    MOCK_SYNC_ENABLED="on"
    # 30 chars, max_length=18 → keeps first 15 chars + "..."
    MOCK_PANE_TITLE="abcdefghijklmnopqrstuvwxyz1234"
    local result
    result=$(get_pane_display_name "%1" "fallback-name" 18)
    assert_equals "abcdefghijklmno..." "$result" "long pane_title truncated to max_length-3 + '...'"
}

test_empty_pane_id_returns_fallback() {
    echo -e "${YELLOW}--- Test: empty pane_id returns fallback ---${NC}"
    MOCK_SYNC_ENABLED="on"
    MOCK_PANE_TITLE="should-be-ignored"
    local result
    result=$(get_pane_display_name "" "fallback-name" 18)
    assert_equals "fallback-name" "$result" "empty pane_id short-circuits to fallback"
}

test_unknown_pane_id_returns_fallback() {
    echo -e "${YELLOW}--- Test: synthetic 'unknown_*' pane_id returns fallback ---${NC}"
    MOCK_SYNC_ENABLED="on"
    MOCK_PANE_TITLE="should-be-ignored"
    local result
    result=$(get_pane_display_name "unknown_42" "fallback-name" 18)
    assert_equals "fallback-name" "$result" "unknown_* pane_id short-circuits to fallback"
}

# =============================================================================
# Main
# =============================================================================

setup() {
    echo -e "${YELLOW}=== Test pane_name.sh Suite ===${NC}"
    echo ""
}

teardown() {
    echo ""
    echo -e "${YELLOW}=== Test Results ===${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}

main() {
    setup

    test_optin_off_returns_fallback
    test_optin_on_empty_title_returns_fallback
    test_optin_on_default_zsh_returns_fallback
    test_optin_on_default_claude_returns_fallback
    test_optin_on_renamed_title_returns_title
    test_optin_on_long_title_is_truncated
    test_empty_pane_id_returns_fallback
    test_unknown_pane_id_returns_fallback

    teardown
}

main "$@"
