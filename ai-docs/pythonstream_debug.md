# Pythonstream Backend Debugging Summary

## Current Status
**Backend does NOT work** - Server process starts but immediately crashes/exits.

## What Works
✅ Backend validation passes
✅ Python dependencies installed (`--check-deps` returns ok)
✅ Manual server start works perfectly:
```bash
~/.config/dmg/python3.12/bin/python3 whisper_stream.py \
  --tcp-port 12342 \
  --output-dir /tmp/whisper_dict \
  --filename-prefix test \
  --silence-threshold 2.0 \
  --min-chunk-duration 3.0 \
  --max-chunk-duration 600.0
# Output: {"status": "listening", "port": 12342}
```

## What Fails
❌ Server started via hs.task crashes immediately
❌ hs.task process shows "Is running: false" right after start
❌ No server process listening on port 12342
❌ No clear error message explaining why it failed

## Configuration
- Python: `/Users/dmg/.config/dmg/python3.12/bin/python3`
- Script: `/Users/dmg/.hammerspoon/Spoons/hs_whisperDictation.spoon/whisper_stream.py`
- Port: `12342` (changed from 12341 which was stuck)
- Output dir: `/tmp/whisper_dict` (exists, verified)

## Backend Architecture
Current implementation uses an adapter pattern:
1. `backends/streaming_backend.lua` - Adapter
2. `recording-backend.lua` - Original working implementation
3. Adapter loads pythonstream from recording-backend.lua
4. Converts callbacks → EventBus events
5. Converts callback API → Promise API

## The Problem
The hs.task is created but immediately exits (crashed). No stderr/error captured.

From hs command:
```lua
Server process exists: hs.task: /Users/dmg/.config/dmg/python3.12/bin/python3 ...
Is running: false  -- ❌ Process not running!
```

## Hypotheses
1. **hs.task environment** - Maybe hs.task runs in different environment than bash?
2. **Working directory** - Maybe the task runs from wrong directory?
3. **Permissions** - Maybe hs.task doesn't have permissions?
4. **Stderr not captured** - Exit callback should print errors but we don't see them
5. **Port conflict** - Even though lsof shows port free, maybe it's not?

## Next Steps
1. **Add comprehensive error logging** to recording-backend.lua's _startServer
2. **Capture and display ALL stderr/stdout** from hs.task
3. **Test hs.task directly** with simple python script to verify it works
4. **Check working directory** that hs.task runs from
5. **Write integration tests** using `hs` command that verify functionality

## Files Modified
- `init.lua` - Added pythonExecutable config, changed port to 12342
- `backends/streaming_backend.lua` - Adapter that loads recording-backend.lua
- `tests/test_pythonstream_real.sh` - Integration test script

## Test Results
```
Test 4: Manual Server Start - ✓ SUCCESS
Test 5: Recording via Hammerspoon - ❌ FAILED (server not running)
```

Manual start works, hs.task start fails - environmental difference!
