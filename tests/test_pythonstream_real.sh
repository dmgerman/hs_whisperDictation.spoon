#!/bin/bash
# Real integration test for pythonstream backend using hs command

echo "=== Pythonstream Backend Integration Test ==="
echo

# Test 1: Check configuration
echo "Test 1: Configuration"
hs -c 'local wd = spoon.hs_whisperDictation
print("  Backend: " .. wd.recordingManager.backend:getName())
print("  Python: " .. wd.recordingManager.backend.backend.config.pythonCmd)
print("  Script: " .. wd.recordingManager.backend.backend.config.scriptPath)
print("  Port: " .. wd.recordingManager.backend.backend.config.port)
'
echo

# Test 2: Validation
echo "Test 2: Backend Validation"
hs -c 'local wd = spoon.hs_whisperDictation
local valid, err = wd.recordingManager.backend:validate()
print("  Valid: " .. tostring(valid))
if err then print("  Error: " .. err) end
'
echo

# Test 3: Check if port is free
echo "Test 3: Port Status"
PORT=$(hs -c 'print(spoon.hs_whisperDictation.recordingManager.backend.backend.config.port)')
echo "  Port: $PORT"
if lsof -i :$PORT >/dev/null 2>&1; then
  echo "  Status: IN USE (need to kill process)"
  lsof -i :$PORT
  echo "  Killing..."
  lsof -ti :$PORT | xargs kill -9 2>/dev/null
  sleep 1
else
  echo "  Status: FREE"
fi
echo

# Test 4: Manual server start
echo "Test 4: Manual Server Start"
PYTHON=$(hs -c 'print(spoon.hs_whisperDictation.recordingManager.backend.backend.config.pythonCmd)')
SCRIPT=$(hs -c 'print(spoon.hs_whisperDictation.recordingManager.backend.backend.config.scriptPath)')
echo "  Command: $PYTHON $SCRIPT --tcp-port $PORT ..."
$PYTHON $SCRIPT --tcp-port $PORT --output-dir /tmp/whisper_dict --filename-prefix test --silence-threshold 2.0 --min-chunk-duration 3.0 --max-chunk-duration 600.0 2>&1 &
SERVER_PID=$!
sleep 3

if lsof -i :$PORT >/dev/null 2>&1; then
  echo "  ✓ Manual start SUCCESS"
  kill $SERVER_PID 2>/dev/null
else
  echo "  ❌ Manual start FAILED"
  wait $SERVER_PID
fi
sleep 1
echo

# Test 5: Recording via Hammerspoon
echo "Test 5: Recording via Hammerspoon"
hs -c 'local wd = spoon.hs_whisperDictation
print("  Starting recording...")
wd.recordingManager:startRecording("en"):next(function()
  print("  ✓ Promise resolved")
end):catch(function(err)
  print("  ❌ Promise rejected: " .. tostring(err))
end)
'

sleep 5

if lsof -i :$PORT >/dev/null 2>&1; then
  echo "  ✓ SERVER IS RUNNING"
  echo "  Process:"
  lsof -i :$PORT
else
  echo "  ❌ SERVER NOT RUNNING"
  echo "  Checking backend state..."
  hs -c 'local b = spoon.hs_whisperDictation.recordingManager.backend.backend
  if b._serverProcess then
    print("    Server process exists: " .. tostring(b._serverProcess))
    print("    Is running: " .. tostring(b._serverProcess:isRunning()))
  else
    print("    No server process")
  end
  '
fi

echo
echo "=== Test Complete ==="
