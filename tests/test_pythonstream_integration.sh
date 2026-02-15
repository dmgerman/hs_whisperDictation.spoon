#!/bin/bash
# Integration test for pythonstream backend
# Tests actual recording → chunking → transcription flow

set -e

echo "=== Pythonstream Backend Integration Test ==="
echo

# Step 1: Check server is running
echo "Step 1: Check if server is running"
PORT=$(hs -c 'print(spoon.hs_whisperDictation.pythonstreamConfig.port)')
if lsof -i :$PORT >/dev/null 2>&1; then
  echo "  ✓ Server already running on port $PORT"
else
  echo "  Server not running, will start on first recording"
fi
echo

# Step 2: Start recording
echo "Step 2: Start recording"
hs -c 'spoon.hs_whisperDictation.recordingManager:startRecording("en"):next(function()
  print("✓ Recording started")
end):catch(function(err)
  print("❌ Failed to start: " .. tostring(err))
  error(err)
end)
'
echo "  Waiting for server to start..."
sleep 5

# Check server started
if lsof -i :$PORT >/dev/null 2>&1; then
  echo "  ✓ Server is running on port $PORT"
else
  echo "  ❌ Server failed to start"
  exit 1
fi
echo

# Step 3: Wait for chunks
echo "Step 3: Recording (speak into microphone for 5 seconds)"
echo "  Waiting for audio chunks..."
sleep 5

# Step 4: Check console for chunks
echo
echo "Step 4: Verify chunks are being processed"
CONSOLE=$(hs -c "print(hs.console.getConsole())")
CHUNK_COUNT=$(echo "$CONSOLE" | grep -c "Chunk.*ready" || echo "0")
TRANSCRIPTION_COUNT=$(echo "$CONSOLE" | grep -c "Adding to ChunkAssembler" || echo "0")

echo "  Chunks received: $CHUNK_COUNT"
echo "  Transcriptions: $TRANSCRIPTION_COUNT"

if [ "$CHUNK_COUNT" -gt 0 ]; then
  echo "  ✓ Chunks are being generated"
else
  echo "  ⚠️  No chunks yet (may need more time)"
fi

if [ "$TRANSCRIPTION_COUNT" -gt 0 ]; then
  echo "  ✓ Transcriptions are working"
else
  echo "  ❌ No transcriptions (check whisper server)"
fi
echo

# Step 5: Stop recording
echo "Step 5: Stop recording"
hs -c 'spoon.hs_whisperDictation.recordingManager:stopRecording():next(function()
  print("✓ Recording stopped")
end):catch(function(err)
  print("❌ Failed to stop: " .. tostring(err))
end)
'
sleep 2
echo

# Step 6: Check for errors
echo "Step 6: Check for errors"
ERROR_COUNT=$(echo "$CONSOLE" | grep -c "ERROR.*Audio file parameter" || echo "0")
if [ "$ERROR_COUNT" -gt 0 ]; then
  echo "  ❌ Found $ERROR_COUNT transcription errors"
  echo "$CONSOLE" | grep "ERROR.*Audio file" | tail -3
  exit 1
else
  echo "  ✓ No audio file errors"
fi

# Step 7: Verify audio files exist
echo
echo "Step 7: Verify audio files"
RECENT_FILES=$(find /tmp/whisper_dict -name "en_chunk_*.wav" -mmin -1 2>/dev/null | wc -l | tr -d ' ')
echo "  Recent audio files (last minute): $RECENT_FILES"
if [ "$RECENT_FILES" -gt 0 ]; then
  echo "  ✓ Audio files are being created"
  ls -lth /tmp/whisper_dict/en_chunk_*.wav 2>/dev/null | head -3
else
  echo "  ⚠️  No recent audio files"
fi

echo
echo "=== Test Summary ==="
if [ "$CHUNK_COUNT" -gt 0 ] && [ "$TRANSCRIPTION_COUNT" -gt 0 ] && [ "$ERROR_COUNT" -eq 0 ]; then
  echo "✅ ALL TESTS PASSED"
  echo "   - Server started: ✓"
  echo "   - Chunks generated: $CHUNK_COUNT"
  echo "   - Transcriptions: $TRANSCRIPTION_COUNT"
  echo "   - No errors: ✓"
  exit 0
else
  echo "⚠️  SOME TESTS FAILED"
  [ "$CHUNK_COUNT" -eq 0 ] && echo "   - No chunks generated"
  [ "$TRANSCRIPTION_COUNT" -eq 0 ] && echo "   - No transcriptions"
  [ "$ERROR_COUNT" -gt 0 ] && echo "   - $ERROR_COUNT errors found"
  exit 1
fi
