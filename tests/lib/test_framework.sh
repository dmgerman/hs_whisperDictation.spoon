#!/bin/bash
# Simple test framework for shell-based integration tests
# Provides TAP-like output with proper assertions

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

# Color codes
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Test suite functions
test_suite() {
    echo "# $1"
    echo ""
}

test_case() {
    CURRENT_TEST="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

pass() {
    echo -e "${GREEN}ok${NC} $TESTS_RUN - $CURRENT_TEST"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}not ok${NC} $TESTS_RUN - $CURRENT_TEST"
    [ -n "$1" ] && echo "  # $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

skip() {
    echo -e "${YELLOW}ok${NC} $TESTS_RUN - $CURRENT_TEST # SKIP $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

# Assertion functions
assert_command_exists() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    else
        fail "$1 not found in PATH"
        return 1
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-values should be equal}"

    if [ "$expected" = "$actual" ]; then
        return 0
    else
        fail "$desc (expected: '$expected', got: '$actual')"
        return 1
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local desc="${3:-values should not be equal}"

    if [ "$not_expected" != "$actual" ]; then
        return 0
    else
        fail "$desc (got: '$actual')"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local desc="${2:-condition should be true}"

    if [ "$condition" = "true" ]; then
        return 0
    else
        fail "$desc (got: '$condition')"
        return 1
    fi
}

assert_file_exists() {
    local filepath="$1"
    local desc="${2:-file should exist}"

    if [ -f "$filepath" ]; then
        return 0
    else
        fail "$desc (file not found: $filepath)"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-should contain substring}"

    if echo "$haystack" | grep -q "$needle"; then
        return 0
    else
        fail "$desc (looking for: '$needle')"
        return 1
    fi
}

# Hammerspoon helper functions
hs_eval() {
    timeout 3 hs -c "$1" 2>&1
}

hs_eval_silent() {
    timeout 3 hs -c "$1" >/dev/null 2>&1
}

# Clear Hammerspoon console
clear_console() {
    hs_eval_silent "hs.console.clearConsole()"
}

# Get console output from the last N seconds
get_recent_console() {
    local seconds="${1:-60}"
    local now=$(date +%s)
    local cutoff=$((now - seconds))

    hs_eval "print(hs.console.getConsole())" 2>/dev/null | while IFS= read -r line; do
        # Extract timestamp if present (format: YYYY-MM-DD HH:MM:SS)
        if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
            timestamp=$(echo "$line" | cut -d: -f1-3 | cut -d' ' -f1-2)
            line_time=$(date -j -f "%Y-%m-%d %H:%M:%S" "$timestamp" +%s 2>/dev/null || echo "0")
            if [ "$line_time" -ge "$cutoff" ]; then
                echo "$line"
            fi
        fi
    done
}

assert_hs_running() {
    if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
        return 0
    else
        fail "Hammerspoon is not running"
        return 1
    fi
}

assert_spoon_loaded() {
    local loaded=$(hs_eval "print(spoon.hs_whisperDictation ~= nil)" 2>/dev/null)
    if [ "$loaded" = "true" ]; then
        return 0
    else
        fail "hs_whisperDictation spoon is not loaded"
        return 1
    fi
}

# Test summary
test_summary() {
    echo ""
    echo "1..$TESTS_RUN"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}# All tests passed ($TESTS_PASSED/$TESTS_RUN)${NC}"
        return 0
    else
        echo -e "${RED}# Tests failed: $TESTS_FAILED/$TESTS_RUN${NC}"
        echo -e "${GREEN}# Tests passed: $TESTS_PASSED/$TESTS_RUN${NC}"
        return 1
    fi
}

# Setup/teardown helpers
cleanup_audio_files() {
    local pattern="$1"
    find /tmp/whisper_dict -name "$pattern" -mmin -1 -delete 2>/dev/null || true
}

wait_for_condition() {
    local condition="$1"
    local timeout="${2:-5}"
    local interval="${3:-0.5}"

    local elapsed=0
    while [ $(echo "$elapsed < $timeout" | bc) -eq 1 ]; do
        if eval "$condition"; then
            return 0
        fi
        sleep "$interval"
        elapsed=$(echo "$elapsed + $interval" | bc)
    done
    return 1
}
