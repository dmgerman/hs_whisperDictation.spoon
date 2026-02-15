#!/bin/bash
# Transcription Test: Whisper CLI Method
# Uses sox backend for simple recording, tests whisper CLI transcription

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh

test_suite "Transcription: Whisper CLI"

clear_console
sleep 1

# Prerequisites
test_case "whisper CLI is available"
if assert_command_exists whisper; then
    pass
else
    skip "whisper CLI not installed"
    test_summary
    exit 0
fi

test_case "Hammerspoon is running"
if assert_hs_running; then
    pass
fi

test_case "spoon is loaded"
if assert_spoon_loaded; then
    pass
fi

# Configuration
test_case "can switch to sox backend"
hs_eval_silent "spoon.hs_whisperDictation.recordingBackend = 'sox'"
sleep 1
BACKEND=$(hs_eval "print(spoon.hs_whisperDictation.recordingBackend)" | head -1)
if assert_equals "sox" "$BACKEND"; then
    pass
fi

test_case "can switch to whispercli method"
hs_eval_silent "spoon.hs_whisperDictation.transcriptionMethod = 'whispercli'"
sleep 1
METHOD=$(hs_eval "print(spoon.hs_whisperDictation.transcriptionMethod)" | head -1)
if assert_equals "whispercli" "$METHOD"; then
    pass
fi

# Record audio
test_case "can record with sox"
hs_eval_silent "spoon.hs_whisperDictation.recordingManager:startRecording('en')"
sleep 3
hs_eval_silent "spoon.hs_whisperDictation.recordingManager:stopRecording()"
sleep 2

AUDIO_FILE=$(find /tmp/whisper_dict -name "en-*.wav" -mmin -1 2>/dev/null | head -1)
if assert_not_equals "" "$AUDIO_FILE"; then
    pass
    echo "  # file: $(basename "$AUDIO_FILE")"
fi

# Test transcription
if [ -n "$AUDIO_FILE" ]; then
    test_case "can transcribe with whisper CLI"
    RESULT=$(whisper "$AUDIO_FILE" --language en --model tiny --output_format txt 2>&1 | grep -v "^$" | tail -5)
    if [ -n "$RESULT" ]; then
        pass
        echo "  # transcription output received"
    else
        fail "no transcription output"
    fi
fi

# Cleanup
cleanup_audio_files "en-*.wav"

test_summary
exit $?
