#!/bin/bash
# Live integration tests for whisperFilters
# Tests real shell command execution through Hammerspoon's hs.task
#
# Prerequisites: Hammerspoon running with hs_whisperDictation spoon loaded
set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh

test_suite "WhisperFilter Integration Tests"

# --- Prerequisites ---

test_case "Hammerspoon is running"
assert_hs_running && pass

test_case "spoon is loaded"
assert_spoon_loaded && pass

# --- Helper: run filter on text and return clipboard content ---
# Sets up filter, calls onTextReady, waits, reads clipboard
apply_filter_and_get_result() {
  local filter_cmd="$1"
  local input_text="$2"
  local filter_name="${3:-test filter}"

  hs_eval_silent "
    local wd = spoon.hs_whisperDictation
    wd.whisperFilters = {{ name = '$filter_name', cmd = [[$filter_cmd]] }}
    wd.activeFilter = 1
    wd.manager.onTextReady('$input_text', function() end)
  "
  sleep 2
  hs_eval "print(hs.pasteboard.getContents())"
}

# --- Passthrough tests ---

test_case "no filter active passes text through unchanged"
hs_eval_silent "
  local wd = spoon.hs_whisperDictation
  wd.whisperFilters = {}
  wd.activeFilter = nil
  hs.pasteboard.setContents('')
  wd.manager.onTextReady('passthrough test', function() end)
"
sleep 1
RESULT=$(hs_eval "print(hs.pasteboard.getContents())")
assert_equals "passthrough test" "$RESULT" && pass

# --- Simple echo filter (cat) ---

test_case "cat filter returns text unchanged"
RESULT=$(apply_filter_and_get_result "cat" "hello world")
assert_equals "hello world" "$RESULT" && pass

# --- Transform filter ---

test_case "uppercase filter transforms text"
RESULT=$(apply_filter_and_get_result "tr '[:lower:]' '[:upper:]'" "hello world")
assert_equals "HELLO WORLD" "$RESULT" && pass

# --- Multi-line text ---

test_case "filter preserves multi-line text"
hs_eval_silent "
  local wd = spoon.hs_whisperDictation
  wd.whisperFilters = {{ name = 'cat', cmd = 'cat' }}
  wd.activeFilter = 1
  hs.pasteboard.setContents('')
  wd.manager.onTextReady('line one\nline two\nline three', function() end)
"
sleep 2
RESULT=$(hs_eval "print(hs.pasteboard.getContents())")
LINE_COUNT=$(echo "$RESULT" | wc -l | tr -d ' ')
[ "$LINE_COUNT" -ge 3 ] && pass || fail "Expected 3+ lines, got $LINE_COUNT"

# --- Nonexistent script ---

test_case "nonexistent script falls back to original text"
hs_eval_silent "
  local wd = spoon.hs_whisperDictation
  wd.whisperFilters = {{ name = 'bad script', cmd = '/nonexistent/script.sh' }}
  wd.activeFilter = 1
  hs.pasteboard.setContents('')
  wd.manager.onTextReady('original text', function() end)
"
sleep 2
RESULT=$(hs_eval "print(hs.pasteboard.getContents())")
assert_equals "original text" "$RESULT" && pass

# --- Non-zero exit code ---

test_case "non-zero exit code falls back to original text"
RESULT=$(apply_filter_and_get_result "echo fail >&2; exit 1" "keep this")
assert_equals "keep this" "$RESULT" && pass

# --- Empty output ---

test_case "empty output falls back to original text"
RESULT=$(apply_filter_and_get_result "true" "keep this too")
assert_equals "keep this too" "$RESULT" && pass

# --- Cleanup: restore no-filter state ---

hs_eval_silent "
  local wd = spoon.hs_whisperDictation
  wd.activeFilter = nil
  wd.whisperFilters = {}
"

test_summary
exit $?
