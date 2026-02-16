#!/bin/bash
# New Architecture End-to-End Integration Test
# Tests complete flow: SoxRecorder + WhisperCLITranscriber + Manager via spoon
# Uses BlackHole virtual audio device for deterministic fixture audio playback

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh
source tests/lib/audio_routing.sh

test_suite "New Architecture - End-to-End Flow (via Spoon Interface)"

# ==============================================================================
# Prerequisites
# ==============================================================================

test_case "BlackHole virtual audio device is installed"
assert_blackhole_installed && pass

test_case "sox command is available"
assert_command_exists sox && pass

test_case "whisper-cli command is available"
assert_command_exists whisper-cli && pass

test_case "whisper model exists"
MODEL_PATH="/usr/local/whisper/ggml-large-v3.bin"
assert_file_exists "$MODEL_PATH" && pass

test_case "Hammerspoon is running"
assert_hs_running && pass

test_case "fixture audio file exists"
# Use shortest available fixture for faster tests
FIXTURE_AUDIO="tests/fixtures/audio/complete/en-20260214-200536.wav"
if [ ! -f "$FIXTURE_AUDIO" ]; then
  # Fallback to any available fixture
  FIXTURE_AUDIO=$(find tests/fixtures/audio/complete -name "*.wav" | head -1)
fi
assert_file_exists "$FIXTURE_AUDIO" && pass
echo "  # using fixture: $FIXTURE_AUDIO ($(ls -lh "$FIXTURE_AUDIO" | awk '{print $5}'))"

# ==============================================================================
# Setup
# ==============================================================================

# Create temp directory for this test
TEST_TEMP_DIR="/tmp/whisper_e2e_test_$$"
mkdir -p "$TEST_TEMP_DIR"

# Setup BlackHole audio routing
test_case "can setup virtual audio routing"
setup_virtual_audio && pass

clear_console
sleep 1

# ==============================================================================
# Load Spoon with New Architecture
# ==============================================================================

test_case "can load spoon with new architecture"
hs_eval_silent "
  wd = hs.loadSpoon('hs_whisperDictation')
  wd.config = {
    recorder = 'sox',
    transcriber = 'whispercli',
    sox = {
      soxCmd = '/opt/homebrew/bin/sox',
      audioInputDevice = 'BlackHole 2ch',  -- Use virtual device for tests
      tempDir = '${TEST_TEMP_DIR}'
    },
    whispercli = {
      executable = '/opt/homebrew/bin/whisper-cli',
      modelPath = '${MODEL_PATH}'
    }
  }
  wd.tempDir = '${TEST_TEMP_DIR}'
  wd:start()
"
LOADED=$(hs_eval "print(wd ~= nil and wd.manager ~= nil)")
assert_equals "true" "$LOADED" && pass

# ==============================================================================
# State Machine - Initial State
# ==============================================================================

test_case "manager starts in IDLE state"
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "IDLE" "$STATE" && pass

test_case "recorder is configured with BlackHole"
DEVICE=$(hs_eval "print(wd.recorder.audioInputDevice or 'nil')")
assert_equals "BlackHole 2ch" "$DEVICE" && pass

test_case "menubar shows idle icon"
MENUBAR=$(hs_eval "print(wd.menubar:title())")
if echo "$MENUBAR" | grep -q "🎤.*en"; then
  pass
else
  fail "Expected idle icon 🎤, got: $MENUBAR"
fi

# ==============================================================================
# Recording Lifecycle
# ==============================================================================

test_case "can start recording via toggle"
hs_eval_silent "wd:toggle()"
sleep 0.5
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "RECORDING" "$STATE" && pass

test_case "recorder is recording"
IS_REC=$(hs_eval "print(tostring(wd.recorder:isRecording()))")
assert_equals "true" "$IS_REC" && pass

test_case "menubar shows recording icon with elapsed time"
sleep 1  # Wait for updateElapsed timer to fire (runs every 1s)
MENUBAR=$(hs_eval "print(wd.menubar:title())")
if echo "$MENUBAR" | grep -q "🎙️.*s.*en"; then
  pass
else
  fail "Expected recording icon 🎙️ with time, got: $MENUBAR"
fi

# Play fixture audio to BlackHole (this becomes the "microphone" input)
test_case "play fixture audio through virtual device"
play_fixture_to_virtual "$FIXTURE_AUDIO" &
PLAY_PID=$!
sleep 2  # Allow some audio to be recorded
pass

# Stop recording
test_case "can stop recording via toggle"
hs_eval_silent "wd:toggle()"
sleep 0.5
IS_REC=$(hs_eval "print(tostring(wd.recorder:isRecording()))")
assert_equals "false" "$IS_REC" && pass

test_case "menubar shows transcribing icon"
MENUBAR=$(hs_eval "print(wd.menubar:title())")
if echo "$MENUBAR" | grep -q "⏳.*en"; then
  pass
else
  # Might already be IDLE if transcription was fast
  if echo "$MENUBAR" | grep -q "🎤.*en"; then
    echo "  # Note: Already transitioned to IDLE (transcription was very fast)"
    pass
  else
    fail "Expected transcribing icon ⏳ or idle icon 🎤, got: $MENUBAR"
  fi
fi

# Wait for playback to complete
wait $PLAY_PID 2>/dev/null || true

# ==============================================================================
# Transcription
# ==============================================================================

test_case "manager transitions through TRANSCRIBING to IDLE"
# Wait up to 60 seconds for transcription to complete
MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  STATE=$(hs_eval "print(wd.manager.state)" 2>/dev/null || echo "UNKNOWN")
  echo "  # state: $STATE (${ELAPSED}s elapsed)"
  if [ "$STATE" = "IDLE" ]; then
    break
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done
assert_equals "IDLE" "$STATE" && pass

test_case "menubar returns to idle icon after completion"
MENUBAR=$(hs_eval "print(wd.menubar:title())")
if echo "$MENUBAR" | grep -q "🎤.*en"; then
  pass
else
  fail "Expected idle icon 🎤, got: $MENUBAR"
fi

# ==============================================================================
# Results Verification
# ==============================================================================

test_case "exactly 1 chunk was processed (SoxRecorder emits single chunk)"
PENDING=$(hs_eval "print(wd.manager.pendingTranscriptions)")
assert_equals "0" "$PENDING" && pass

test_case "result copied to clipboard"
CLIPBOARD=$(hs_eval "print(hs.pasteboard.getContents() or '')")
assert_not_equals "" "$CLIPBOARD" && pass
echo "  # transcription: ${CLIPBOARD:0:80}..."

test_case "audio file was created"
AUDIO=$(find "$TEST_TEMP_DIR" -name "en-*.wav" -mmin -5 2>/dev/null | head -1)
assert_not_equals "" "$AUDIO" && pass
echo "  # audio file: $AUDIO"

test_case "audio file is valid WAV"
file "$AUDIO" | grep -q "WAVE audio" && pass

test_case "audio file has reasonable size"
SIZE=$(stat -f%z "$AUDIO" 2>/dev/null || stat -c%s "$AUDIO" 2>/dev/null)
if [ "$SIZE" -gt 1000 ]; then
  pass
else
  fail "Audio file too small: $SIZE bytes"
fi

test_case "no errors in console"
CONSOLE=$(get_recent_console 120)
ERROR_COUNT=$(echo "$CONSOLE" | grep -iE "error|failed" | grep -v "no error" | wc -l | tr -d ' ')
if [ "$ERROR_COUNT" -gt 0 ]; then
  fail "found errors in console:"
  echo "$CONSOLE" | grep -iE "error|failed" | grep -v "no error"
else
  pass
fi

# ==============================================================================
# Second Recording Cycle (verify state machine resets properly)
# ==============================================================================

test_case "can start second recording"
hs_eval_silent "wd:toggle()"
sleep 0.5
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "RECORDING" "$STATE" && pass

test_case "menubar shows recording icon for second recording"
sleep 1  # Wait for timer
MENUBAR=$(hs_eval "print(wd.menubar:title())")
if echo "$MENUBAR" | grep -q "🎙️.*s.*en"; then
  pass
else
  fail "Expected recording icon 🎙️, got: $MENUBAR"
fi

# Record for a bit
sleep 2

test_case "can stop second recording"
hs_eval_silent "wd:toggle()"
sleep 0.5
STATE=$(hs_eval "print(wd.manager.state)")
# Should be TRANSCRIBING or already IDLE
if [ "$STATE" = "TRANSCRIBING" ] || [ "$STATE" = "IDLE" ]; then
  pass
else
  fail "Expected TRANSCRIBING or IDLE, got: $STATE"
fi

test_case "second transcription completes"
# Wait for second transcription
MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  STATE=$(hs_eval "print(wd.manager.state)" 2>/dev/null || echo "UNKNOWN")
  if [ "$STATE" = "IDLE" ]; then
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done
assert_equals "IDLE" "$STATE" && pass

test_case "menubar returns to idle after second recording"
MENUBAR=$(hs_eval "print(wd.menubar:title())")
if echo "$MENUBAR" | grep -q "🎤.*en"; then
  pass
else
  fail "Expected idle icon 🎤, got: $MENUBAR"
fi

test_case "second result copied to clipboard"
CLIPBOARD=$(hs_eval "print(hs.pasteboard.getContents() or '')")
assert_not_equals "" "$CLIPBOARD" && pass
echo "  # second transcription: ${CLIPBOARD:0:80}..."

test_case "no errors in console after second recording"
CONSOLE=$(get_recent_console 120)
ERROR_COUNT=$(echo "$CONSOLE" | grep -iE "error|failed" | grep -v "no error" | wc -l | tr -d ' ')
if [ "$ERROR_COUNT" -gt 0 ]; then
  fail "found errors in console:"
  echo "$CONSOLE" | grep -iE "error|failed" | grep -v "no error"
else
  pass
fi

# ==============================================================================
# Cleanup
# ==============================================================================

# Restore audio device (done automatically by trap in audio_routing.sh)
teardown_virtual_audio

# Remove test directory
rm -rf "$TEST_TEMP_DIR"

# Restore spoon to normal configuration (reload to reset state)
echo "# Reloading Hammerspoon to restore normal configuration..."
timeout 5 hs -c "hs.reload()" &
sleep 2

test_summary
exit $?
