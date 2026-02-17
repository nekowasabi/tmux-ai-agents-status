#!/usr/bin/env bash
# tests/status_detection_test.sh - Status detection logic tests
# Tests for detect_claude_status_from_pane() content parsing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the module under test
source "$PROJECT_ROOT/scripts/session_tracker.sh"

# テスト結果カウンター
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
    fi
}

assert_matches() {
    local pattern="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))
    if [[ "$actual" =~ $pattern ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $message"
        echo "  Pattern: $pattern"
        echo "  Actual:  $actual"
    fi
}

# =====================================================
# Mock: tmux capture-pane をオーバーライドして
# detect_claude_status_from_pane をコンテンツベースでテスト
# =====================================================
MOCK_PANE_CONTENT=""

# tmux コマンドをモック（capture-pane のみ）
tmux() {
    if [[ "${1:-}" == "capture-pane" ]]; then
        echo "$MOCK_PANE_CONTENT"
        return 0
    fi
    # その他の tmux コマンドは空を返す
    return 0
}
export -f tmux

# モックコンテンツで detect_claude_status_from_pane をテスト
test_with_content() {
    local content="$1"
    local expected="$2"
    local test_name="$3"
    MOCK_PANE_CONTENT="$content"
    local result
    result=$(detect_claude_status_from_pane "%0")
    assert_equals "$expected" "$result" "$test_name"
}

# =====================================================
# Running 状態テスト
# =====================================================
test_running_spinner_time_after() {
    test_with_content \
        "✢ Reading files… (3 files · 1m30s)" \
        "running:1m30s" \
        "Running: spinner with time after separator"
}

test_running_spinner_short_time() {
    test_with_content \
        "✽ Working… (2 items · 10s)" \
        "running:10s" \
        "Running: spinner with short elapsed time"
}

test_running_spinner_hours() {
    test_with_content \
        "✶ Processing… (large task · 2h5m30s)" \
        "running:2h5m30s" \
        "Running: spinner with hours"
}

test_running_interrupt_esc() {
    test_with_content \
        $'Processing some work\nesc to interrupt' \
        "running" \
        "Running: esc to interrupt"
}

test_running_interrupt_ctrlc() {
    test_with_content \
        $'Working on something\nctrl+c to interrupt' \
        "running" \
        "Running: ctrl+c to interrupt"
}

# =====================================================
# Waiting 状態テスト
# =====================================================
test_waiting_permission_allow() {
    test_with_content \
        $'Allow this action?\n  Allow once  Allow always  Deny' \
        "waiting" \
        "Waiting: permission dialog (Allow once)"
}

test_waiting_permission_deny() {
    test_with_content \
        $'Do you want to proceed?\n  Allow once  Deny' \
        "waiting" \
        "Waiting: permission dialog (Deny)"
}

test_waiting_menu_select() {
    test_with_content \
        $'Select an option:\n❯ 1. Option A\n  2. Option B' \
        "waiting" \
        "Waiting: menu selection"
}

test_waiting_navigation() {
    test_with_content \
        $'Choose:\n↑/↓ to navigate, enter to select' \
        "waiting" \
        "Waiting: navigation prompt"
}

test_waiting_continue() {
    test_with_content \
        $'Changes detected.\nContinue?' \
        "waiting" \
        "Waiting: Continue? prompt"
}

test_waiting_proceed() {
    test_with_content \
        $'Ready to apply changes.\nProceed?' \
        "waiting" \
        "Waiting: Proceed? prompt"
}

# =====================================================
# Idle 状態テスト
# =====================================================
test_idle_prompt() {
    test_with_content \
        $'Previous output here\n\n❯ ' \
        "idle" \
        "Idle: empty prompt"
}

test_idle_prompt_bare() {
    test_with_content \
        "❯ " \
        "idle" \
        "Idle: bare prompt line"
}

test_idle_with_statusbar() {
    # Claude Code の実際のペイン構造をシミュレート
    # プロンプト行が最終行ではなく、ステータスバーが最終行のケース
    test_with_content \
        $'Previous output here\n\n❯ \n────────────────────────────────────\n  🤖 claude-opus-4-5 | 💰 $0.50\n  ⏵⏵ bypass permissions on (shift+tab to toggle)' \
        "idle" \
        "Idle: prompt above statusbar"
}

# =====================================================
# Mode 検出テスト
# =====================================================
test_plan_mode_idle() {
    test_with_content \
        $'⏸ plan mode on\n\n❯ ' \
        "idle:plan_mode" \
        "Mode: plan_mode + idle"
}

test_plan_mode_running() {
    test_with_content \
        $'⏸ plan mode on\n✢ Working… (5 files · 30s)' \
        "running:30s:plan_mode" \
        "Mode: plan_mode + running with time"
}

test_plan_mode_waiting() {
    test_with_content \
        $'⏸ plan mode on\nAllow this action?\n  Allow once  Deny' \
        "waiting:plan_mode" \
        "Mode: plan_mode + waiting"
}

test_accept_edits_running() {
    test_with_content \
        $'⏵⏵ accept edits on\n✢ Working… (task · 10s)' \
        "running:10s:accept_edits" \
        "Mode: accept_edits + running"
}

test_accept_edits_idle() {
    test_with_content \
        $'⏵⏵ accept edits on\n\n❯ ' \
        "idle:accept_edits" \
        "Mode: accept_edits + idle"
}

# =====================================================
# Unknown / Edge case テスト
# =====================================================
test_empty_content() {
    MOCK_PANE_CONTENT=""
    local result
    result=$(detect_claude_status_from_pane "%0")
    assert_equals "unknown" "$result" "Edge: empty pane content"
}

test_random_content() {
    test_with_content \
        "Some random text without any patterns" \
        "unknown" \
        "Edge: no matching pattern"
}

test_running_interrupt_with_plan_mode() {
    test_with_content \
        $'⏸ plan mode on\nDoing work\nesc to interrupt' \
        "running:plan_mode" \
        "Edge: interrupt + plan_mode"
}

# =====================================================
# テスト実行
# =====================================================
run_all_tests() {
    echo "=== Status Detection Tests ==="
    echo ""

    echo "--- Running State ---"
    test_running_spinner_time_after
    test_running_spinner_short_time
    test_running_spinner_hours
    test_running_interrupt_esc
    test_running_interrupt_ctrlc

    echo ""
    echo "--- Waiting State ---"
    test_waiting_permission_allow
    test_waiting_permission_deny
    test_waiting_menu_select
    test_waiting_navigation
    test_waiting_continue
    test_waiting_proceed

    echo ""
    echo "--- Idle State ---"
    test_idle_prompt
    test_idle_prompt_bare
    test_idle_with_statusbar

    echo ""
    echo "--- Mode Detection ---"
    test_plan_mode_idle
    test_plan_mode_running
    test_plan_mode_waiting
    test_accept_edits_running
    test_accept_edits_idle

    echo ""
    echo "--- Edge Cases ---"
    test_empty_content
    test_random_content
    test_running_interrupt_with_plan_mode

    echo ""
    echo "================================"
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
    [[ $TESTS_FAILED -eq 0 ]] && exit 0 || exit 1
}

run_all_tests
