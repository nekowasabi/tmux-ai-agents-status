#!/usr/bin/env bash
# tests/test_prerender.sh - write_fzf_prerender() unit tests (TDD)
# Tests for cache_shared.sh write_fzf_prerender() function

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test utilities
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        printf "${GREEN}PASS${NC}: %s\n" "$message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        printf "${RED}FAIL${NC}: %s\n" "$message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_matches() {
    local pattern="$1"
    local actual="$2"
    local message="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$actual" | grep -qE "$pattern"; then
        printf "${GREEN}PASS${NC}: %s\n" "$message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        printf "${RED}FAIL${NC}: %s\n" "$message"
        echo "  Pattern: $pattern"
        echo "  Actual:  '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -f "$file" ]; then
        printf "${GREEN}PASS${NC}: %s\n" "$message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        printf "${RED}FAIL${NC}: %s\n" "$message"
        echo "  File not found: $file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test fixtures
TMP_PRERENDER="/tmp/ai_agent_fzf_prerender_test_$$"
TMP_STATUS_CACHE="/tmp/ai_agent_pane_status_cache_test_$$"

setup() {
    # Remove test output files
    rm -f "$TMP_PRERENDER" "$TMP_STATUS_CACHE"

    # Create mock status cache: pane_id|detailed_status
    cat > "$TMP_STATUS_CACHE" << 'EOF'
%1:1.1|idle
%2:1.2|running:2m30s
%3:1.3|waiting:30s:plan_mode
EOF

    # Source platform.sh first (required by cache_shared.sh)
    source "$PROJECT_ROOT/scripts/lib/platform.sh" 2>/dev/null || true
    # Source the module under test
    source "$PROJECT_ROOT/scripts/lib/cache_shared.sh"
}

teardown() {
    rm -f "$TMP_PRERENDER" "$TMP_STATUS_CACHE"
}

# ==============================================================================
# Test: function exists
# ==============================================================================
test_function_exists() {
    setup
    assert_equals "0" "$(declare -f write_fzf_prerender > /dev/null 2>&1; echo $?)" \
        "write_fzf_prerender function should exist"
    teardown
}

# ==============================================================================
# Test: creates output file
# ==============================================================================
test_creates_output_file() {
    setup

    local process_info="12345|%1:1.1|main|1|/dev/pts/0|iTerm2|/home/user/myproject"
    write_fzf_prerender "$process_info" "$TMP_STATUS_CACHE" "$TMP_PRERENDER"

    assert_file_exists "$TMP_PRERENDER" \
        "write_fzf_prerender should create output file"
    teardown
}

# ==============================================================================
# Test: output format is display_string TAB pane_id
# ==============================================================================
test_output_format_tab_separated() {
    setup

    local process_info="12345|%1:1.1|main|1|/dev/pts/0|iTerm2|/home/user/myproject"
    write_fzf_prerender "$process_info" "$TMP_STATUS_CACHE" "$TMP_PRERENDER"

    local line
    line=$(head -1 "$TMP_PRERENDER")
    # Each line must contain a TAB separator
    assert_matches $'\t' "$line" \
        "output line should contain TAB separator between display string and pane_id"
    teardown
}

# ==============================================================================
# Test: pane_id appears after TAB
# ==============================================================================
test_pane_id_in_output() {
    setup

    local process_info="12345|%1:1.1|main|1|/dev/pts/0|iTerm2|/home/user/myproject"
    write_fzf_prerender "$process_info" "$TMP_STATUS_CACHE" "$TMP_PRERENDER"

    local pane_id_col
    pane_id_col=$(awk -F'\t' '{print $NF}' "$TMP_PRERENDER" | head -1)
    assert_equals "%1:1.1" "$pane_id_col" \
        "last TAB column should be the pane_id"
    teardown
}

# ==============================================================================
# Test: project name appears in display string
# ==============================================================================
test_project_name_in_display() {
    setup

    local process_info="12345|%1:1.1|main|1|/dev/pts/0|iTerm2|/home/user/myproject"
    write_fzf_prerender "$process_info" "$TMP_STATUS_CACHE" "$TMP_PRERENDER"

    local display_col
    display_col=$(awk -F'\t' '{print $1}' "$TMP_PRERENDER" | head -1)
    assert_matches "myproject" "$display_col" \
        "display string should contain project name from cwd"
    teardown
}

# ==============================================================================
# Test: empty process_info produces empty output (no error)
# ==============================================================================
test_empty_input_no_error() {
    setup

    write_fzf_prerender "" "$TMP_STATUS_CACHE" "$TMP_PRERENDER"
    local exit_code=$?
    assert_equals "0" "$exit_code" \
        "empty process_info should not cause error"
    teardown
}

# ==============================================================================
# Test: atomic write (tmp file used, then moved)
# ==============================================================================
test_atomic_write() {
    setup

    local process_info="12345|%1:1.1|main|1|/dev/pts/0|iTerm2|/home/user/myproject"
    write_fzf_prerender "$process_info" "$TMP_STATUS_CACHE" "$TMP_PRERENDER"

    # Tmp file should NOT remain after successful write
    local tmp_file="${TMP_PRERENDER}.tmp"
    assert_equals "0" "$([ ! -f "$tmp_file" ] && echo 0 || echo 1)" \
        "atomic tmp file should be cleaned up after write"
    teardown
}

# ==============================================================================
# Test: multiple processes produce multiple lines
# ==============================================================================
test_multiple_processes() {
    setup

    local process_info
    process_info="12345|%1:1.1|main|1|/dev/pts/0|iTerm2|/home/user/proj1
67890|%2:1.2|main|2|/dev/pts/1|iTerm2|/home/user/proj2"

    write_fzf_prerender "$process_info" "$TMP_STATUS_CACHE" "$TMP_PRERENDER"

    local line_count
    line_count=$(wc -l < "$TMP_PRERENDER" | tr -d ' ')
    assert_equals "2" "$line_count" \
        "two processes should produce two output lines"
    teardown
}

# ==============================================================================
# Test: missing status cache doesn't crash
# ==============================================================================
test_missing_status_cache_no_crash() {
    setup

    local process_info="12345|%1:1.1|main|1|/dev/pts/0|iTerm2|/home/user/myproject"
    write_fzf_prerender "$process_info" "/tmp/nonexistent_cache_$$" "$TMP_PRERENDER"
    local exit_code=$?

    assert_equals "0" "$exit_code" \
        "missing status cache should not crash"
    teardown
}

# ==============================================================================
# Test: ai_agent_status.sh calls write_fzf_prerender() after write_shared_cache
# ==============================================================================
test_ai_agent_status_calls_prerender() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local status_script="$PROJECT_ROOT/scripts/ai_agent_status.sh"

    if grep -q "write_fzf_prerender" "$status_script"; then
        printf "${GREEN}PASS${NC}: ai_agent_status.sh should call write_fzf_prerender()\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        printf "${RED}FAIL${NC}: ai_agent_status.sh should call write_fzf_prerender()\n"
        echo "  write_fzf_prerender not found in $status_script"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ==============================================================================
# Test: call is inside batch_info guard block
# ==============================================================================
test_prerender_call_inside_batch_guard() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local status_script="$PROJECT_ROOT/scripts/ai_agent_status.sh"

    # Check that write_fzf_prerender is called within the batch_info block
    # (i.e., appears after write_shared_cache in the same if block)
    if awk '/write_shared_cache/,/^[[:space:]]*fi/' "$status_script" | grep -q "write_fzf_prerender"; then
        printf "${GREEN}PASS${NC}: write_fzf_prerender called within batch_info guard\n"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        printf "${RED}FAIL${NC}: write_fzf_prerender should be called within batch_info guard\n"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ==============================================================================
# Run all tests
# ==============================================================================
echo "=== test_prerender.sh: write_fzf_prerender() TDD tests ==="
echo ""

test_function_exists
test_creates_output_file
test_output_format_tab_separated
test_pane_id_in_output
test_project_name_in_display
test_empty_input_no_error
test_atomic_write
test_multiple_processes
test_missing_status_cache_no_crash
test_ai_agent_status_calls_prerender
test_prerender_call_inside_batch_guard

echo ""
echo "=== Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
