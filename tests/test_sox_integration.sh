#!/bin/bash
# Sox Backend Integration Test
# Tests simple sox recording → transcription flow

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh

test_suite "Sox Backend Integration"

# Clear console before starting
clear_console
sleep 1

# Prerequisites
test_case "sox command is available"
if assert_command_exists sox; then
    pass
fi

test_case "Hammerspoon is running"
if assert_hs_running; then
    pass
fi

test_case "hs_whisperDictation spoon is loaded"
if assert_spoon_loaded; then
    pass
fi

# Configuration
test_case "can read current backend"
BACKEND=$(hs_eval "print(spoon.hs_whisperDictation.recordingBackend)")
if assert_not_equals "" "$BACKEND" "backend should not be empty"; then
    pass
    echo "  # current backend: $BACKEND"
fi

test_case "can switch to sox backend"
hs_eval_silent "spoon.hs_whisperDictation.recordingBackend = 'sox'"
sleep 1
BACKEND=$(hs_eval "print(spoon.hs_whisperDictation.recordingBackend)")
if assert_equals "sox" "$BACKEND"; then
    pass
fi

test_case "backend validates successfully"
VALID=$(hs_eval "local valid = spoon.hs_whisperDictation.recordingManager.backend:validate(); print(tostring(valid))")
if assert_equals "true" "$VALID"; then
    pass
fi

# Recording lifecycle
test_case "can start recording"
hs_eval_silent "spoon.hs_whisperDictation.recordingManager:startRecording('en')"
sleep 2
IS_RECORDING=$(hs_eval "print(tostring(spoon.hs_whisperDictation.recordingManager:isRecording()))")
if assert_equals "true" "$IS_RECORDING"; then
    pass
fi

test_case "recording stays active for duration"
sleep 2
IS_RECORDING=$(hs_eval "print(tostring(spoon.hs_whisperDictation.recordingManager:isRecording()))")
if assert_equals "true" "$IS_RECORDING"; then
    pass
fi

test_case "can stop recording"
hs_eval_silent "spoon.hs_whisperDictation.recordingManager:stopRecording()"
sleep 2
IS_RECORDING=$(hs_eval "print(tostring(spoon.hs_whisperDictation.recordingManager:isRecording()))")
if assert_equals "false" "$IS_RECORDING"; then
    pass
fi

# Audio file validation
test_case "audio file was created"
AUDIO_FILE=$(find /tmp/whisper_dict -name "en-*.wav" -mmin -1 2>/dev/null | head -1)
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

# Error checking
test_case "no errors in console"
CONSOLE=$(get_recent_console 60)
# Look for actual errors, not debug lines containing "error:"
ERROR_COUNT=$(echo "$CONSOLE" | grep -E "\[ERROR\]|Error in listener|Recording error:" | grep -v "error: Finished loading\|error: testing area\|error: finished loading" | wc -l | tr -d ' ')
if [ "$ERROR_COUNT" -gt 0 ]; then
    fail "found $ERROR_COUNT errors:"
    echo "$CONSOLE" | grep -E "\[ERROR\]|Error in listener|Recording error:" | grep -v "error: Finished loading\|error: testing area\|error: finished loading" | tail -5
else
    pass
fi

# Cleanup
cleanup_audio_files "en-*.wav"

test_summary
exit $?
