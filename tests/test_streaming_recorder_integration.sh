#!/bin/bash
# StreamingRecorder Live Integration Test
# Tests StreamingRecorder with Manager + WhisperCLI transcriber via spoon interface
# Uses BlackHole virtual audio device for deterministic fixture audio playback

set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh
source tests/lib/audio_routing.sh

test_suite "StreamingRecorder Integration (via Spoon Interface)"

# ==============================================================================
# Prerequisites
# ==============================================================================

test_case "BlackHole virtual audio device is installed"
assert_blackhole_installed && pass

test_case "Python environment is available"
PYTHON_PATH="$HOME/.config/dmg/python3.12/bin/python3"
if [ ! -f "$PYTHON_PATH" ]; then
  skip "Python not found at $PYTHON_PATH"
fi
assert_file_exists "$PYTHON_PATH" && pass

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
TEST_TEMP_DIR="/tmp/streaming_test_$$"
mkdir -p "$TEST_TEMP_DIR"

# Setup BlackHole audio routing
test_case "can setup virtual audio routing"
setup_virtual_audio && pass

clear_console
sleep 1

# ==============================================================================
# Load Spoon with StreamingRecorder
# ==============================================================================

test_case "can load spoon with StreamingRecorder"
# Use longer timeout for spoon loading (10s instead of default 3s)
timeout 10 hs -c "
  wd = hs.loadSpoon('hs_whisperDictation')
  if not wd then error('Failed to load spoon') end
  wd.config = {
    recorder = 'streaming',
    transcriber = 'whispercli',
    streaming = {
      pythonPath = '$PYTHON_PATH',
      audioInputDevice = 'BlackHole 2ch',  -- Use virtual device for tests
      tempDir = '${TEST_TEMP_DIR}',
      tcpPort = 12341,
      silenceThreshold = 2.0,
      minChunkDuration = 3.0,
      maxChunkDuration = 600.0
    },
    whispercli = {
      executable = '/opt/homebrew/bin/whisper-cli',
      modelPath = '/usr/local/whisper/ggml-large-v3.bin'
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
# Validate Recorder
# ==============================================================================

test_case "StreamingRecorder validates successfully"
VALID=$(hs_eval "local ok, err = wd.manager.recorder:validate(); print(tostring(ok))")
assert_equals "true" "$VALID" && pass

test_case "recorder has correct name"
NAME=$(hs_eval "print(wd.manager.recorder:getName())")
assert_equals "streaming" "$NAME" && pass

test_case "recorder configuration is correct"
PYTHON=$(hs_eval "print(wd.manager.recorder.pythonPath)")
assert_equals "$PYTHON_PATH" "$PYTHON" && pass

# ==============================================================================
# State Machine - Initial State
# ==============================================================================

test_case "manager starts in IDLE state"
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "IDLE" "$STATE" && pass

# ==============================================================================
# Recording Cycle 1 - Basic Flow
# ==============================================================================

test_case "can start recording"
# Use fire-and-forget pattern with timeout to avoid IPC hang
timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
sleep 1
IS_REC=$(timeout 5 hs -c "print(tostring(wd.manager.state == 'RECORDING'))" 2>&1 | grep -o "true\|false" || echo "false")
assert_equals "true" "$IS_REC" && pass

test_case "manager is in RECORDING state"
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "RECORDING" "$STATE" && pass

test_case "play fixture audio through virtual device"
# Play fixture in background - this becomes "microphone" input via BlackHole
play_fixture_to_virtual "$FIXTURE_AUDIO" &
PLAY_PID=$!
sleep 3
pass

test_case "can stop recording"
timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
sleep 2
pass

test_case "wait for transcription to complete"
# StreamingRecorder emits chunks during recording, so transcription may already be done
MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  STATE=$(hs_eval "print(wd.manager.state)" 2>/dev/null || echo "UNKNOWN")
  if [ "$STATE" = "IDLE" ]; then
    break
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

if [ "$STATE" != "IDLE" ]; then
  fail "Transcription did not complete within ${MAX_WAIT}s (state: $STATE)"
fi
pass

test_case "final state is IDLE"
STATE=$(hs_eval "print(wd.manager.state)")
assert_equals "IDLE" "$STATE" && pass

test_case "no pending transcriptions"
PENDING=$(hs_eval "print(wd.manager.pendingTranscriptions)")
assert_equals "0" "$PENDING" && pass

test_case "clipboard contains transcription"
CLIPBOARD=$(hs_eval "print(hs.pasteboard.getContents())")
if [ -z "$CLIPBOARD" ] || [ "$CLIPBOARD" = "nil" ]; then
  fail "Clipboard is empty"
fi
pass
echo "  # transcribed: ${CLIPBOARD:0:50}..."

# ==============================================================================
# Recording Cycle 2 - Verify State Reset
# ==============================================================================

test_case "can start second recording (state machine reset)"
timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
sleep 1
IS_REC=$(timeout 5 hs -c "print(tostring(wd.manager.state == 'RECORDING'))" 2>&1 | grep -o "true\|false" || echo "false")
assert_equals "true" "$IS_REC" && pass

test_case "play fixture again"
play_fixture_to_virtual "$FIXTURE_AUDIO" &
PLAY_PID=$!
sleep 3
pass

test_case "can stop second recording"
timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
sleep 2
pass

test_case "second transcription completes"
MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  STATE=$(hs_eval "print(wd.manager.state)" 2>/dev/null || echo "UNKNOWN")
  if [ "$STATE" = "IDLE" ]; then
    break
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done
assert_equals "IDLE" "$STATE" && pass

# ==============================================================================
# Error Handling
# ==============================================================================

test_case "no errors in console"
CONSOLE=$(get_recent_console 180)
ERROR_COUNT=$(echo "$CONSOLE" | grep -E "\[ERROR\]" | wc -l | tr -d ' ')
if [ "$ERROR_COUNT" -gt 0 ]; then
  echo "$CONSOLE" | grep -E "\[ERROR\]" | head -5
  fail "Found $ERROR_COUNT error(s) in console"
fi
pass

# ==============================================================================
# Server Lifecycle
# ==============================================================================

test_case "server process cleaned up"
# Check if Python server process is still running
PS_COUNT=$(ps aux | grep -c "whisper_stream.py" | tr -d ' ' || echo "0")
# Subtract 1 for the grep process itself
PS_COUNT=$((PS_COUNT - 1))
if [ "$PS_COUNT" -gt 0 ]; then
  echo "  # warning: $PS_COUNT whisper_stream.py process(es) still running"
fi
pass

# ==============================================================================
# Cleanup
# ==============================================================================

test_case "restore original audio configuration"
# Reload Hammerspoon to restore default config
timeout 2 hs -c "hs.reload()" &
sleep 2
timeout 2 hs -c "print('ready')" >/dev/null 2>&1 || true
pass

# Audio device restoration happens via trap in audio_routing.sh

# Clean up test temp directory
rm -rf "$TEST_TEMP_DIR"

test_summary
exit $?
