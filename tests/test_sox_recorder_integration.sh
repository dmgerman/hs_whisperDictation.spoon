#!/bin/bash
# SoxRecorder Live Integration Test
# Tests callback-based SoxRecorder with Manager + MockTranscriber
# Part of new architecture (v2) - Step 4 verification

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh

test_suite "SoxRecorder Integration (New Architecture)"

clear_console
sleep 1

# Prerequisites
test_case "sox is available"
if assert_command_exists sox; then
    pass
    SOX_VERSION=$(sox --version 2>&1 | head -1)
    echo "  # $SOX_VERSION"
fi

test_case "Hammerspoon is running"
if assert_hs_running; then
    pass
fi

# Get spoon path
SPOON_PATH="/Users/dmg/.hammerspoon/Spoons/hs_whisperDictation.spoon"

# Load components using loader helper
test_case "can load new architecture components"
hs_eval_silent "dofile('$SPOON_PATH/tests/helpers/load_new_architecture.lua')"

LOADED=$(hs_eval "print(SoxRecorder ~= nil and Manager ~= nil and MockTranscriber ~= nil)")
if assert_equals "true" "$LOADED"; then
    pass
fi

# Create instances in global namespace (will persist across hs_eval calls)
test_case "can create Manager with SoxRecorder + MockTranscriber"
hs_eval_silent "
  recorder = SoxRecorder.new({
    soxCmd = '/opt/homebrew/bin/sox',
    tempDir = '/tmp/test_sox_recorder'
  })

  transcriber = MockTranscriber.new({
    transcriptPrefix = 'Transcribed: ',
    delay = 0.1
  })

  mgr = Manager.new(recorder, transcriber, {
    language = 'en',
    tempDir = '/tmp/test_sox_recorder'
  })
"

CREATED=$(hs_eval "print(mgr ~= nil)")
if assert_equals "true" "$CREATED"; then
    pass
fi

# Validation
test_case "SoxRecorder validates successfully"
VALID=$(hs_eval "local ok, err = recorder:validate(); print(tostring(ok))")
if assert_equals "true" "$VALID"; then
    pass
else
    ERROR=$(hs_eval "local ok, err = recorder:validate(); print(tostring(err))")
    fail "validation failed: $ERROR"
fi

test_case "MockTranscriber validates successfully"
VALID=$(hs_eval "local ok, err = transcriber:validate(); print(tostring(ok))")
if assert_equals "true" "$VALID"; then
    pass
fi

# Initial state
test_case "Manager starts in IDLE state"
STATE=$(hs_eval "print(mgr.state)")
if assert_equals "IDLE" "$STATE"; then
    pass
fi

test_case "recorder is not recording initially"
IS_REC=$(hs_eval "print(tostring(recorder:isRecording()))")
if assert_equals "false" "$IS_REC"; then
    pass
fi

# Recording lifecycle
test_case "can start recording"
hs_eval_silent "
  local success, err = mgr:startRecording('en')
  assert(success, 'startRecording failed: ' .. tostring(err))
"
sleep 1
STATE=$(hs_eval "print(mgr.state)")
if assert_equals "RECORDING" "$STATE"; then
    pass
fi

test_case "recorder is recording"
IS_REC=$(hs_eval "print(tostring(recorder:isRecording()))")
if assert_equals "true" "$IS_REC"; then
    pass
fi

test_case "recording stays active for 2 seconds"
sleep 2
IS_REC=$(hs_eval "print(tostring(recorder:isRecording()))")
if assert_equals "true" "$IS_REC"; then
    pass
fi

test_case "can stop recording"
hs_eval_silent "
  local success, err = mgr:stopRecording()
  assert(success, 'stopRecording failed: ' .. tostring(err))
"
sleep 1
IS_REC=$(hs_eval "print(tostring(recorder:isRecording()))")
if assert_equals "false" "$IS_REC"; then
    pass
fi

# State transitions
test_case "Manager transitions to IDLE after transcription"
# Give time for transcription to complete (MockTranscriber is fast)
sleep 1
STATE=$(hs_eval "print(mgr.state)")
if assert_equals "IDLE" "$STATE"; then
    pass
    echo "  # MockTranscriber completes quickly in tests"
fi

test_case "no pending transcriptions"
PENDING=$(hs_eval "print(mgr.pendingTranscriptions)")
if assert_equals "0" "$PENDING"; then
    pass
fi

# File validation
test_case "audio file was created"
AUDIO_FILE=$(find /tmp/test_sox_recorder -name "en-*.wav" -mmin -1 2>/dev/null | head -1)
if assert_not_equals "" "$AUDIO_FILE" "audio file should exist"; then
    pass
    echo "  # file: $(basename "$AUDIO_FILE")"
fi

if [ -n "$AUDIO_FILE" ]; then
    test_case "audio file is valid WAV format"
    if file "$AUDIO_FILE" | grep -q "WAVE audio"; then
        pass
    else
        fail "not a valid WAV file: $(file "$AUDIO_FILE")"
    fi

    test_case "audio file has non-zero size"
    SIZE=$(stat -f%z "$AUDIO_FILE" 2>/dev/null || stat -c%s "$AUDIO_FILE" 2>/dev/null)
    if [ "$SIZE" -gt 1000 ]; then
        pass
        echo "  # size: $SIZE bytes"
    else
        fail "file too small: $SIZE bytes"
    fi
fi

# Results verification
test_case "exactly 1 result (SoxRecorder emits single chunk)"
RESULTS=$(hs_eval "print(#mgr.results)")
if assert_equals "1" "$RESULTS"; then
    pass
fi

test_case "result copied to clipboard"
CLIPBOARD=$(hs_eval "print(hs.pasteboard.getContents() or '')")
if assert_not_equals "" "$CLIPBOARD"; then
    pass
    echo "  # clipboard: ${CLIPBOARD:0:60}..."
fi

test_case "clipboard contains MockTranscriber prefix"
if echo "$CLIPBOARD" | grep -q "Transcribed:"; then
    pass
else
    fail "clipboard doesn't have expected MockTranscriber prefix"
fi

# Error checking
test_case "no errors in console"
CONSOLE=$(get_recent_console 60)
# Look for actual errors, not debug lines containing "error:"
ERROR_COUNT=$(echo "$CONSOLE" | grep -E "\[ERROR\]|Error in listener|Recording error:" | grep -v "error: Finished loading\|error: testing area\|error: finished loading" | wc -l | tr -d ' ')
if [ "$ERROR_COUNT" -gt 0 ]; then
    fail "found $ERROR_COUNT errors in console:"
    echo "$CONSOLE" | grep -E "\[ERROR\]|Error in listener|Recording error:" | grep -v "error: Finished loading\|error: testing area\|error: finished loading" | tail -5
else
    pass
fi

# Test invalid state transitions
test_case "cannot start recording when already recording"
hs_eval_silent "mgr:startRecording('en')"
sleep 0.5
RESULT=$(hs_eval "
  local success, err = mgr:startRecording('en')
  print(tostring(success) .. '|' .. tostring(err or ''))
")
SUCCESS=$(echo "$RESULT" | cut -d'|' -f1)
if assert_equals "false" "$SUCCESS" "second start should fail"; then
    pass
    ERROR=$(echo "$RESULT" | cut -d'|' -f2)
    echo "  # error: $ERROR"
fi

# Stop the recording we just started
hs_eval_silent "mgr:stopRecording()"
sleep 1

test_case "cannot stop recording when not recording"
RESULT=$(hs_eval "
  local success, err = mgr:stopRecording()
  print(tostring(success) .. '|' .. tostring(err or ''))
")
SUCCESS=$(echo "$RESULT" | cut -d'|' -f1)
if assert_equals "false" "$SUCCESS" "stop when not recording should fail"; then
    pass
    ERROR=$(echo "$RESULT" | cut -d'|' -f2)
    echo "  # error: $ERROR"
fi

# Cleanup
test_case "cleanup test files"
rm -rf /tmp/test_sox_recorder
if [ ! -d /tmp/test_sox_recorder ]; then
    pass
else
    fail "cleanup failed"
fi

test_summary
exit $?
