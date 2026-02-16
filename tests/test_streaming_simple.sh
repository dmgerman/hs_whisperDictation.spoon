#!/bin/bash
# Simple StreamingRecorder Test - Just verify core functionality
# No complex timing, no multiple cycles, just: start → record → stop → verify

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh
source tests/lib/audio_routing.sh

test_suite "StreamingRecorder - Simple Functionality Test"

# Setup
test_case "Prerequisites check"
assert_blackhole_installed || skip "BlackHole not installed"
assert_hs_running || skip "Hammerspoon not running"
pass

PYTHON_PATH="$HOME/.config/dmg/python3.12/bin/python3"
test_case "Python environment available"
[ -f "$PYTHON_PATH" ] || skip "Python not at $PYTHON_PATH"
pass

FIXTURE_AUDIO="tests/fixtures/audio/complete/en-20260214-200536.wav"
test_case "Fixture audio exists"
assert_file_exists "$FIXTURE_AUDIO"
pass

# Setup audio
test_case "Setup virtual audio"
setup_virtual_audio
pass

TEST_TEMP_DIR="/tmp/streaming_simple_$$"
mkdir -p "$TEST_TEMP_DIR"
clear_console
sleep 1

# Load spoon
test_case "Load spoon with StreamingRecorder"
timeout 10 hs -c "
  wd = hs.loadSpoon('hs_whisperDictation')
  wd.config = {
    recorder = 'streaming',
    transcriber = 'whispercli',
    streaming = {
      pythonPath = '$PYTHON_PATH',
      audioInputDevice = 'BlackHole 2ch',
      tempDir = '${TEST_TEMP_DIR}',
      tcpPort = 12342
    },
    whispercli = {
      executable = '/opt/homebrew/bin/whisper-cli',
      modelPath = '/usr/local/whisper/ggml-large-v3.bin'
    }
  }
  wd.tempDir = '${TEST_TEMP_DIR}'
  wd:start()
  print('ok')
" >/dev/null 2>&1
LOADED=$(hs_eval "print(wd ~= nil)")
assert_equals "true" "$LOADED" && pass

# Verify recorder
test_case "Recorder is StreamingRecorder"
NAME=$(hs_eval "print(wd.recorder:getName())")
assert_equals "streaming" "$NAME" && pass

# Start recording
test_case "Start recording"
timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
sleep 2
STATE=$(hs_eval "print(wd.manager.state)" 2>/dev/null || echo "UNKNOWN")
assert_equals "RECORDING" "$STATE" && pass

# Play audio
test_case "Play fixture audio"
play_fixture_to_virtual "$FIXTURE_AUDIO" &
sleep 4
pass

# Stop recording
test_case "Stop recording"
timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
sleep 2
pass

# Wait for completion (generous timeout)
test_case "Wait for transcription"
MAX_WAIT=90
ELAPSED=0
FINAL_STATE="UNKNOWN"
while [ $ELAPSED -lt $MAX_WAIT ]; do
  STATE=$(hs_eval "print(wd.manager.state)" 2>/dev/null || echo "UNKNOWN")
  PENDING=$(hs_eval "print(wd.manager.pendingTranscriptions)" 2>/dev/null || echo "-1")

  if [ "$STATE" = "IDLE" ] && [ "$PENDING" = "0" ]; then
    FINAL_STATE="IDLE"
    break
  fi

  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

if [ "$FINAL_STATE" != "IDLE" ]; then
  echo "  # Timed out after ${ELAPSED}s (state: $STATE, pending: $PENDING)"
  fail "Transcription did not complete"
fi
pass

# Verify completion
test_case "Final state is IDLE"
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "IDLE" "$STATE" && pass

test_case "No pending transcriptions"
PENDING=$(hs_eval "print(wd.manager.pendingTranscriptions)")
assert_equals "0" "$PENDING" && pass

# Check results
test_case "Transcription produced result"
# Check if clipboard or results have content
CLIPBOARD=$(hs_eval "print(hs.pasteboard.getContents())" 2>/dev/null || echo "")
if [ -n "$CLIPBOARD" ] && [ "$CLIPBOARD" != "nil" ]; then
  pass
  echo "  # Transcribed: ${CLIPBOARD:0:60}..."
else
  # Clipboard might be empty but transcription might have happened
  # Check console for transcription success
  CONSOLE=$(get_recent_console 120)
  if echo "$CONSOLE" | grep -q "transcribed successfully"; then
    pass
    echo "  # (Transcription succeeded, check console)"
  else
    fail "No transcription result"
  fi
fi

# Check for errors
test_case "No critical errors in console"
CONSOLE=$(get_recent_console 120)
CRITICAL_ERRORS=$(echo "$CONSOLE" | grep -E "\[ERROR\].*crash|CRITICAL" | wc -l | tr -d ' ')
if [ "$CRITICAL_ERRORS" -gt 0 ]; then
  echo "$CONSOLE" | grep -E "\[ERROR\].*crash|CRITICAL" | head -3
fi
[ "$CRITICAL_ERRORS" -eq 0 ] && pass

# Cleanup
test_case "Cleanup"
# Kill server process
pkill -f "whisper_stream.py.*12342" 2>/dev/null || true
# Reload to restore config
timeout 2 hs -c "hs.reload()" &
sleep 2
rm -rf "$TEST_TEMP_DIR"
pass

test_summary
exit $?
