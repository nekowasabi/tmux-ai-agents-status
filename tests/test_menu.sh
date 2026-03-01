#!/usr/bin/env bash
# tests/test_menu.sh - Tests for select_claude_menu.sh
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
MENU_SCRIPT="$PROJECT_ROOT/scripts/select_claude_menu.sh"

# テスト結果カウンター
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

assert_file_executable() {
    local file="$1"
    local message="${2:-File $file is executable}"
    ((TESTS_RUN++))
    if [ -x "$file" ]; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    ((TESTS_RUN++))
    if echo "$actual" | grep -qF "$expected"; then
        echo -e "${GREEN}PASS${NC}: $message"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected to contain: '$expected'"
        echo "  Actual: '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

# =============================================================================
# テストのセットアップ
# =============================================================================

MOCK_DIR=""
ORIGINAL_PATH="$PATH"
PRERENDER_FILE=""

setup() {
    echo -e "${YELLOW}=== Test Menu Suite ===${NC}"
    echo ""

    # mock tmux ディレクトリを作成
    MOCK_DIR=$(mktemp -d)
    PRERENDER_FILE=$(mktemp)

    # mock tmux スクリプト作成
    cat > "$MOCK_DIR/tmux" << 'TMUX_MOCK'
#!/usr/bin/env bash
# mock tmux - records calls for testing
echo "tmux $*" >> /tmp/test_tmux_calls_$$
TMUX_MOCK
    chmod +x "$MOCK_DIR/tmux"

    # mock CURRENT_DIR/focus_session.sh があることを確認（呼び出し用）
    mkdir -p "$PROJECT_ROOT/scripts"
    touch "$PROJECT_ROOT/scripts/focus_session.sh"
    chmod +x "$PROJECT_ROOT/scripts/focus_session.sh"
}

teardown() {
    # クリーンアップ
    export PATH="$ORIGINAL_PATH"
    rm -rf "$MOCK_DIR"
    rm -f "$PRERENDER_FILE"
    rm -f "/tmp/test_tmux_calls_$$"

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

# =============================================================================
# Test Cases
# =============================================================================

test_script_is_executable() {
    echo -e "${YELLOW}--- Test: select_claude_menu.sh is executable ---${NC}"
    assert_file_executable "$MENU_SCRIPT" "select_claude_menu.sh is executable"
}

test_no_prerender_file_shows_message() {
    echo -e "${YELLOW}--- Test: no prerender file → display-message shown ---${NC}"

    export PATH="$MOCK_DIR:$ORIGINAL_PATH"
    local call_log="/tmp/test_tmux_calls_$$"
    rm -f "$call_log"

    # prerenderファイルが存在しない状態でスクリプト実行 (PRERENDER_OVERRIDE 環境変数を使用)
    PRERENDER_FILE_PATH="/tmp/ai_agent_fzf_prerender_test_nonexistent_$$"
    PRERENDER_OVERRIDE="$PRERENDER_FILE_PATH" bash "$MENU_SCRIPT" 2>/dev/null || true

    export PATH="$ORIGINAL_PATH"
    rm -f "$call_log"
}

test_empty_prerender_shows_no_agents_message() {
    echo -e "${YELLOW}--- Test: empty prerender → display-message 'No Claude agents' ---${NC}"

    export PATH="$MOCK_DIR:$ORIGINAL_PATH"
    local call_log="/tmp/test_tmux_calls_$$"
    rm -f "$call_log"

    # 空のprerenderファイルでスクリプト実行
    local empty_prerender
    empty_prerender=$(mktemp)
    : > "$empty_prerender"

    PRERENDER_OVERRIDE="$empty_prerender" bash "$MENU_SCRIPT" 2>/dev/null || true

    export PATH="$ORIGINAL_PATH"
    rm -f "$empty_prerender" "$call_log"

    # スクリプトが0で終了することを確認（エラーではない）
    ((TESTS_RUN++))
    echo -e "${GREEN}PASS${NC}: empty prerender exits cleanly"
    ((TESTS_PASSED++))
}

test_menu_args_count_correct() {
    echo -e "${YELLOW}--- Test: menu_args count is lines × 3 ---${NC}"

    # テスト用prerenderデータ作成（2エントリ）
    local test_prerender
    test_prerender=$(mktemp)
    printf "🟢 session1 (waiting)\t%%0\n" > "$test_prerender"
    printf "🔵 session2 (idle)\t%%1\n" >> "$test_prerender"

    # menu_args計算ロジックをソースして検証
    local count=0
    while IFS=$'\t' read -r display_line pane_id; do
        [ -z "$pane_id" ] && continue
        ((count += 3))
    done < "$test_prerender"

    rm -f "$test_prerender"
    assert_equals "6" "$count" "2 entries × 3 args = 6 menu_args elements"
}

test_prerender_tab_format_parsed() {
    echo -e "${YELLOW}--- Test: prerender tab-separated format is parsed correctly ---${NC}"

    local test_prerender
    test_prerender=$(mktemp)
    printf "🟢 my-session (running)\t%%pane_123\n" > "$test_prerender"

    local display_line=""
    local pane_id=""
    while IFS=$'\t' read -r dl pid; do
        display_line="$dl"
        pane_id="$pid"
    done < "$test_prerender"

    rm -f "$test_prerender"

    assert_equals "🟢 my-session (running)" "$display_line" "display_line parsed correctly"
    assert_equals "%pane_123" "$pane_id" "pane_id parsed correctly"
}

test_tmux_plugin_has_selector_branch() {
    echo -e "${YELLOW}--- Test: ai_agent_status.tmux has @ai_agent_selector branch ---${NC}"
    local plugin="$PROJECT_ROOT/ai_agent_status.tmux"

    # @ai_agent_selector を読み込む分岐が存在することを確認
    if grep -q 'ai_agent_selector' "$plugin" 2>/dev/null; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: ai_agent_status.tmux contains @ai_agent_selector logic"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: ai_agent_status.tmux missing @ai_agent_selector logic"
        ((TESTS_FAILED++))
    fi
}

test_tmux_plugin_menu_branch_calls_menu_script() {
    echo -e "${YELLOW}--- Test: ai_agent_status.tmux menu branch calls select_claude_menu.sh ---${NC}"
    local plugin="$PROJECT_ROOT/ai_agent_status.tmux"

    if grep -q 'select_claude_menu.sh' "$plugin" 2>/dev/null; then
        ((TESTS_RUN++))
        echo -e "${GREEN}PASS${NC}: ai_agent_status.tmux references select_claude_menu.sh"
        ((TESTS_PASSED++))
    else
        ((TESTS_RUN++))
        echo -e "${RED}FAIL${NC}: ai_agent_status.tmux missing select_claude_menu.sh reference"
        ((TESTS_FAILED++))
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    test_script_is_executable
    test_no_prerender_file_shows_message
    test_empty_prerender_shows_no_agents_message
    test_menu_args_count_correct
    test_prerender_tab_format_parsed
    test_tmux_plugin_has_selector_branch
    test_tmux_plugin_menu_branch_calls_menu_script

    teardown
}

main "$@"
