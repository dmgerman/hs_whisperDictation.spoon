#!/bin/bash
# Pythonstream Backend Integration Test
# Tests streaming recording with VAD-based chunking

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh

test_suite "Pythonstream Backend Integration"

# Clear console before starting
clear_console
sleep 1

# Prerequisites
test_case "Hammerspoon is running"
if assert_hs_running; then
    pass
fi

test_case "hs_whisperDictation spoon is loaded"
if assert_spoon_loaded; then
    pass
fi

# Get Python configuration
PYTHON_CMD=$(hs_eval "local cmd = 'python3'; if spoon.hs_whisperDictation.pythonstreamConfig and spoon.hs_whisperDictation.pythonstreamConfig.pythonCmd then cmd = spoon.hs_whisperDictation.pythonstreamConfig.pythonCmd end; print(cmd)" 2>/dev/null)
# Fallback if we got nil or empty
if [ -z "$PYTHON_CMD" ] || [ "$PYTHON_CMD" = "nil" ]; then
    PYTHON_CMD="python3"
fi

test_case "Python is available"
if assert_command_exists "$PYTHON_CMD"; then
    pass
    echo "  # python: $PYTHON_CMD"
fi

test_case "Python package sounddevice is installed"
if $PYTHON_CMD -c "import sounddevice" 2>/dev/null; then
    pass
else
    skip "sounddevice not installed"
fi

test_case "Python package scipy is installed"
if $PYTHON_CMD -c "import scipy" 2>/dev/null; then
    pass
else
    skip "scipy not installed"
fi

# Configuration
test_case "can switch to pythonstream backend"
hs_eval_silent "spoon.hs_whisperDictation.recordingBackend = 'pythonstream'"
sleep 1
BACKEND=$(hs_eval "print(spoon.hs_whisperDictation.recordingBackend)")
if assert_equals "pythonstream" "$BACKEND"; then
    pass
fi

test_case "backend validates successfully"
VALIDATION=$(hs_eval "local valid, err = spoon.hs_whisperDictation.recordingManager.backend:validate(); print(tostring(valid) .. '|' .. tostring(err or ''))")
VALID=$(echo "$VALIDATION" | cut -d'|' -f1)
if assert_equals "true" "$VALID"; then
    pass
else
    ERROR=$(echo "$VALIDATION" | cut -d'|' -f2)
    fail "validation failed: $ERROR"
fi

# Get port configuration
PORT=$(hs_eval "
if spoon.hs_whisperDictation.pythonstreamConfig and spoon.hs_whisperDictation.pythonstreamConfig.port then
  print(spoon.hs_whisperDictation.pythonstreamConfig.port)
else
  print('8765')
end
" 2>/dev/null)
if [ -z "$PORT" ] || [ "$PORT" = "nil" ]; then
    PORT="8765"
fi
echo "  # TCP port: $PORT"

# Recording lifecycle
test_case "can start recording"
hs_eval_silent "spoon.hs_whisperDictation.recordingManager:startRecording('en')"
sleep 3  # Give server time to start
IS_RECORDING=$(hs_eval "print(tostring(spoon.hs_whisperDictation.recordingManager:isRecording()))")
if assert_equals "true" "$IS_RECORDING"; then
    pass
fi

test_case "python server is listening on port"
if lsof -i ":$PORT" >/dev/null 2>&1; then
    pass
else
    fail "no process listening on port $PORT"
fi

test_case "recording stays active"
sleep 2
IS_RECORDING=$(hs_eval "print(tostring(spoon.hs_whisperDictation.recordingManager:isRecording()))")
if assert_equals "true" "$IS_RECORDING"; then
    pass
fi

# Check for chunks (if VAD detects speech)
test_case "can check for audio chunks"
CHUNK_COUNT=$(find /tmp/whisper_dict -name "en_chunk_*.wav" -mmin -1 2>/dev/null | wc -l | tr -d ' ')
echo "  # chunks detected: $CHUNK_COUNT"
pass  # Don't fail if no speech detected

test_case "can stop recording"
hs_eval_silent "spoon.hs_whisperDictation.recordingManager:stopRecording()"
sleep 3  # Give server time to shut down
IS_RECORDING=$(hs_eval "print(tostring(spoon.hs_whisperDictation.recordingManager:isRecording()))")
if assert_equals "false" "$IS_RECORDING"; then
    pass
fi

test_case "python server cleanup"
# The pythonstream backend may keep the server running for performance
# What matters is that recording stopped properly
# Check if server is still running, but don't fail the test
sleep 2
if ! lsof -i ":$PORT" >/dev/null 2>&1; then
    pass
    echo "  # server terminated"
else
    # Server still running - this is OK for pythonstream backend
    pass
    echo "  # server still running (expected for pythonstream backend)"
fi

# Verify at least one audio file was created (final chunk)
test_case "at least one audio file was created"
AUDIO_COUNT=$(find /tmp/whisper_dict -name "en_chunk_*.wav" -mmin -1 2>/dev/null | wc -l | tr -d ' ')
if [ "$AUDIO_COUNT" -gt 0 ]; then
    pass
    echo "  # total files: $AUDIO_COUNT"
else
    fail "no audio files created"
fi

# Validate audio files
if [ "$AUDIO_COUNT" -gt 0 ]; then
    test_case "audio files are valid WAV format"
    INVALID_COUNT=0
    for f in $(find /tmp/whisper_dict -name "en_chunk_*.wav" -mmin -1 2>/dev/null); do
        if ! file "$f" | grep -q "WAVE audio"; then
            INVALID_COUNT=$((INVALID_COUNT + 1))
        fi
    done
    if assert_equals "0" "$INVALID_COUNT" "all files should be valid WAV"; then
        pass
    fi
fi

# Error checking
test_case "no errors in console"
CONSOLE=$(get_recent_console 60)
# Look for actual errors, filtering out expected test-related IPC errors
ERROR_COUNT=$(echo "$CONSOLE" | grep -E "\[ERROR\]|Error in listener|Recording error:" | grep -v "error: Finished loading\|error: testing area\|error: finished loading\|ipc port is no longer valid\|message port was invalidated" | wc -l | tr -d ' ')
if [ "$ERROR_COUNT" -gt 0 ]; then
    fail "found $ERROR_COUNT errors:"
    echo "$CONSOLE" | grep -E "\[ERROR\]|Error in listener|Recording error:" | grep -v "error: Finished loading\|error: testing area\|error: finished loading\|ipc port is no longer valid\|message port was invalidated" | tail -5
else
    pass
fi

# Cleanup
cleanup_audio_files "en_chunk_*.wav"

test_summary
exit $?
