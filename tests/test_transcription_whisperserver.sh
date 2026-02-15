#!/bin/bash
# Transcription Test: Whisper Server Method
# Uses sox backend for simple recording, tests whisperserver transcription

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh

test_suite "Transcription: Whisper Server"

clear_console
sleep 1

# Prerequisites
test_case "curl is available"
if assert_command_exists curl; then
    pass
fi

test_case "whisper server is running"
if curl -s --max-time 2 http://localhost:9090/status >/dev/null 2>&1; then
    pass
else
    skip "whisper server not running on localhost:9090"
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

test_case "can switch to whisperserver method"
hs_eval_silent "spoon.hs_whisperDictation.transcriptionMethod = 'whisperserver'"
sleep 1
METHOD=$(hs_eval "print(spoon.hs_whisperDictation.transcriptionMethod)" | head -1)
if assert_equals "whisperserver" "$METHOD"; then
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

# Test transcription via server
if [ -n "$AUDIO_FILE" ]; then
    test_case "can transcribe with whisper server"
    RESPONSE=$(curl -s --max-time 10 -F "file=@$AUDIO_FILE" http://localhost:9090/transcribe 2>&1)
    if echo "$RESPONSE" | grep -q "text"; then
        pass
        TEXT=$(echo "$RESPONSE" | grep -o '"text":"[^"]*"' | cut -d'"' -f4 | head -c 50)
        echo "  # transcription: $TEXT..."
    else
        fail "no transcription in response"
    fi
fi

# Cleanup
cleanup_audio_files "en-*.wav"

test_summary
exit $?
