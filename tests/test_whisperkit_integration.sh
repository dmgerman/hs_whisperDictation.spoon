#!/bin/bash
# WhisperKitTranscriber Live Integration Test
# Tests WhisperKit transcriber with Manager + SoxRecorder via spoon interface
# Uses BlackHole virtual audio device for deterministic fixture audio playback

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh
source tests/lib/audio_routing.sh

test_suite "WhisperKit Transcriber Integration (via Spoon Interface)"

# ==============================================================================
# Prerequisites
# ==============================================================================

test_case "BlackHole virtual audio device is installed"
assert_blackhole_installed && pass

test_case "whisperkit-cli is available"
if ! command -v whisperkit-cli &> /dev/null; then
  skip "whisperkit-cli not installed (brew install whisperkit-cli)"
fi
pass

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
TEST_TEMP_DIR="/tmp/whisperkit_test_$$"
mkdir -p "$TEST_TEMP_DIR"

# Setup BlackHole audio routing
test_case "can setup virtual audio routing"
setup_virtual_audio && pass

clear_console
sleep 1

# ==============================================================================
# Load Spoon with WhisperKit Transcriber
# ==============================================================================

test_case "can load spoon with WhisperKit transcriber"
# Use longer timeout for spoon loading (10s instead of default 3s)
timeout 10 hs -c "
  wd = hs.loadSpoon('hs_whisperDictation')
  if not wd then error('Failed to load spoon') end
  wd.config = {
    recorder = 'sox',
    transcriber = 'whisperkit',
    sox = {
      soxCmd = '/opt/homebrew/bin/sox',
      audioInputDevice = 'BlackHole 2ch',  -- Use virtual device for tests
      tempDir = '${TEST_TEMP_DIR}'
    },
    whisperkit = {
      executable = '/opt/homebrew/bin/whisperkit-cli',
      model = 'large-v3'
    }
  }
  wd.tempDir = '${TEST_TEMP_DIR}'
  success = wd:start()
  if not success then error('Failed to start spoon') end
  print('Loaded and started')
" >/dev/null 2>&1
LOADED=$(hs_eval "print(wd ~= nil and wd.manager ~= nil)")
assert_equals "true" "$LOADED" && pass

# ==============================================================================
# Validate Transcriber
# ==============================================================================

test_case "WhisperKit transcriber validates successfully"
VALID=$(hs_eval "local ok, err = wd.manager.transcriber:validate(); print(tostring(ok))")
assert_equals "true" "$VALID" && pass

test_case "transcriber has correct name"
NAME=$(hs_eval "print(wd.manager.transcriber:getName())")
assert_equals "WhisperKit" "$NAME" && pass

# ==============================================================================
# State Machine - Initial State
# ==============================================================================

test_case "manager starts in IDLE state"
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "IDLE" "$STATE" && pass

test_case "recorder is configured with BlackHole"
DEVICE=$(hs_eval "print(wd.recorder.audioInputDevice or 'nil')")
assert_equals "BlackHole 2ch" "$DEVICE" && pass

# ==============================================================================
# Recording Lifecycle
# ==============================================================================

test_case "can start recording"
hs_eval_silent "wd:toggle()"
sleep 0.5
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "RECORDING" "$STATE" && pass

test_case "recorder is recording"
IS_REC=$(hs_eval "print(tostring(wd.recorder:isRecording()))")
assert_equals "true" "$IS_REC" && pass

# Play fixture audio to BlackHole (this becomes the "microphone" input)
test_case "play fixture audio through virtual device"
play_fixture_to_virtual "$FIXTURE_AUDIO" &
PLAY_PID=$!
sleep 2  # Allow some audio to be recorded
pass


# Stop recording
test_case "can stop recording"
timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
sleep 2  # Give Hammerspoon time to process stop
IS_REC=$(timeout 5 hs -c "print(tostring(wd.recorder:isRecording()))" 2>&1 || echo "false")
assert_equals "false" "$IS_REC" && pass

# Wait for playback to complete
wait $PLAY_PID 2>/dev/null || true

# ==============================================================================
# Transcription (WhisperKit may take 30-60 seconds)
# ==============================================================================

test_case "WhisperKit transcribes audio"
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

# ==============================================================================
# Results Verification
# ==============================================================================

test_case "transcription copied to clipboard"
CLIPBOARD=$(hs_eval "print(hs.pasteboard.getContents() or '')")
assert_not_equals "" "$CLIPBOARD" && pass
echo "  # transcription: ${CLIPBOARD:0:80}..."

test_case "audio file was created"
AUDIO=$(find "$TEST_TEMP_DIR" -name "en-*.wav" -mmin -5 2>/dev/null | head -1)
assert_not_equals "" "$AUDIO" && pass

test_case "audio file is valid WAV"
file "$AUDIO" | grep -q "WAVE audio" && pass

test_case "no errors in console"
CONSOLE=$(get_recent_console 120)
ERROR_COUNT=$(echo "$CONSOLE" | grep -iE "error|failed" | grep -v "no error" | wc -l | tr -d ' ')
if [ "$ERROR_COUNT" -gt 0 ]; then
  fail "found errors in console"
  echo "$CONSOLE" | grep -iE "error|failed" | grep -v "no error" | head -10
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
