# Pythonstream Backend - FIXED

## Status: ✅ WORKING

The pythonstream backend is now fully functional.

## What Was Wrong

**The server was actually working the entire time!**

The issue was a **field name mismatch** in the adapter:
- Old backend uses snake_case: `chunk_num`, `audio_file`, `is_final`
- Adapter was using camelCase: `chunkNum`, `audioFile`, `isFinal`

This caused `audioFile` to be `nil` → transcription failed with "Audio file parameter is required"

## The Fix

Changed `backends/streaming_backend.lua` line 41-47:

```lua
# BEFORE (broken):
chunkNum = event.chunkNum,     # undefined!
audioFile = event.audioFile,   # undefined!
isFinal = event.isFinal,       # undefined!

# AFTER (working):
chunkNum = event.chunk_num,    # ✓
audioFile = event.audio_file,  # ✓
isFinal = event.is_final,      # ✓
```

## Files Modified

1. **init.lua**
   - Added `pythonExecutable` config with correct Python path
   - Changed port from 12341 → 12342
   - Added `pythonExecutable` to backend config

2. **backends/streaming_backend.lua**
   - Fixed field names: snake_case instead of camelCase
   - Added Python path resolution (converts "python3" → full path)

3. **recording-backend.lua**
   - Added error alert on server crash (shows stderr)

## Configuration

```lua
obj.pythonstreamConfig = {
  pythonExecutable = os.getenv("HOME") .. "/.config/dmg/python3.12/bin/python3",
  port = 12342,
  host = "127.0.0.1",
  serverStartupTimeout = 5.0,
  silenceThreshold = 2.0,
  minChunkDuration = 3.0,
  maxChunkDuration = 600.0,
}
```

## How It Works Now

1. User presses recording hotkey
2. Adapter calls `recording-backend.lua`'s pythonstream backend
3. Backend starts Python server via hs.task (if not running)
4. Server listens on port 12342
5. TCP socket connects to server
6. Recording starts, server emits chunk events via TCP
7. Adapter converts events: callbacks → EventBus
8. ChunkAssembler receives chunks and assembles text
9. Transcription happens per chunk
10. Final text pasted to active app

## Testing

Run integration test:
```bash
chmod +x tests/test_pythonstream_integration.sh
./tests/test_pythonstream_integration.sh
```

## Verification

Check console for successful transcriptions:
```bash
hs -c "print(hs.console.getConsole())" | grep -E "Adding to ChunkAssembler|audioFile"
```

Should see:
```
✓ audioFile: /tmp/whisper_dict/en_chunk_001.wav
✓ Adding to ChunkAssembler: chunk 1, 10 chars
```

Check audio files are created:
```bash
ls -lth /tmp/whisper_dict/en_chunk_*.wav | head -5
```

## Key Lessons

1. **Use hs.console.getConsole()** to read Hammerspoon console output
2. **Check field names** when bridging different APIs
3. **The old code was working** - adapter bugs caused new issues
4. **Silent failures happen** when error messages go to console instead of alerts
5. **Integration tests** needed to catch field name mismatches

## Architecture

- `backends/streaming_backend.lua` - Thin adapter
- `recording-backend.lua` - Contains actual pythonstream implementation
- Adapter bridges: callback API → EventBus + Promises
- Field names must match: old backend uses snake_case

## Next Steps

- ✅ Backend works
- ✅ Chunks are generated
- ✅ Transcription works
- ✅ Integration test created
- ⏭️  Add unit tests for adapter field mapping
- ⏭️  Add tests for backend switching (sox ↔ pythonstream)
