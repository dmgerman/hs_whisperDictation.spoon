# Pythonstream Backend - Current Status

## Status: ✅ FULLY WORKING (as of 2026-02-15)

The pythonstream backend has been completely refactored and optimized for reliable chunk detection.

## Architecture

**Complete rewrite completed on 2026-02-15:**
- ✅ Direct implementation using `hs.task` and `hs.socket` (no adapter)
- ✅ Native EventBus event emission
- ✅ Native Promise returns
- ✅ All 16 unit tests passing
- ✅ VAD consecutive silence detection implemented

## Current Configuration

### Recommended Settings (in dmg-functions.lua)
```lua
wd.recordingBackends.pythonstream.config.silenceThreshold = 3.0    -- 3 seconds of silence
wd.recordingBackends.pythonstream.config.minChunkDuration = 5.0    -- 5 seconds minimum chunk
wd.recordingBackends.pythonstream.config.maxChunkDuration = 600.0  -- 10 minutes max
```

### Default Settings (in init.lua)
```lua
obj.pythonstreamConfig = {
  pythonExecutable = os.getenv("HOME") .. "/.config/dmg/python3.12/bin/python3",
  port = 12342,
  host = "127.0.0.1",
  serverStartupTimeout = 5.0,
  silenceThreshold = 2.0,      -- Override in dmg-functions.lua if needed
  minChunkDuration = 3.0,      -- Override in dmg-functions.lua if needed
  maxChunkDuration = 600.0,
}
```

### Python VAD Constants (in whisper_stream.py)
```python
VAD_SPEECH_THRESHOLD = 0.25  # Speech detection sensitivity
VAD_CONSECUTIVE_SILENCE_REQUIRED = 2  # 2 detections (1.0s) to confirm silence
```

## How Chunking Works

### Chunk Creation Logic
1. **Audio callback** runs every 0.5 seconds
2. **VAD check** analyzes last 32ms of audio using Silero VAD
3. If **speech detected** → reset silence counter
4. If **silence detected** → increment consecutive silence counter
5. After **2 consecutive silence detections** (1.0s) → start silence timer
6. After **silenceThreshold** more silence (3.0s default) → check if chunk ready
7. If **chunk duration >= minChunkDuration** (5.0s) → save chunk

### Total Requirements for Chunking
- ✅ Minimum 5.0 seconds of recording
- ✅ ~4.0 seconds of continuous silence:
  - 1.0s for VAD confirmation (2 consecutive detections)
  - 3.0s for silence threshold
- ✅ Speech detected before silence (not just ambient noise)

### What This Prevents
- ❌ Chunks created during brief pauses (< 4 seconds)
- ❌ Chunks created during consonants or breaths
- ❌ Empty or near-empty chunks
- ❌ Rapid chunking every 2-3 seconds

## Recent Fixes (2026-02-15)

### 1. Streaming Backend Refactor
**Problem**: Used adapter pattern loading old recording-backend.lua (technical debt)

**Fix**: Complete rewrite (591 lines) with direct hs.task/hs.socket implementation
- All 16 unit tests passing
- Proper event emission
- Proper Promise handling
- Test mode support

### 2. Config Override Issue
**Problem**: dmg-functions.lua had `minChunkDuration = 2.0` (too low)

**Fix**: Changed to `minChunkDuration = 5.0` and added `silenceThreshold = 3.0`

### 3. VAD Consecutive Silence Detection
**Problem**: Single 32ms VAD check caused false silence during speech pauses

**Fix**: Require 2 consecutive silence detections (1.0s) before considering it real silence
- Added `VAD_CONSECUTIVE_SILENCE_REQUIRED = 2`
- Added `consecutive_silence_count` tracking
- Reset counter on speech detection

## Files Modified

1. **backends/streaming_backend.lua** - Complete rewrite (591 lines)
2. **whisper_stream.py** - Added consecutive silence detection
3. **lib/event_bus.lua** - Added missing streaming events
4. **dmg-functions.lua** - Updated configuration values

## Testing

### Unit Tests
```bash
busted tests/spec/unit/backends/streaming_backend_spec.lua -v
# Result: 16/16 passing ✅
```

### Integration Testing
Record with natural speech pauses under 4 seconds - no chunks should be created.
Only when pausing for 4+ seconds should a chunk boundary occur.

### Verify Server Parameters
```bash
ps aux | grep whisper_stream.py | grep -v grep
```

Expected output should show:
```
--silence-threshold 3.0 --min-chunk-duration 5.0 --max-chunk-duration 600.0
```

## Troubleshooting

### Chunks Still Created Too Frequently

**Check server parameters:**
```bash
ps aux | grep whisper_stream.py
```

**Verify configuration:**
```lua
hs -c "print(spoon.hs_whisperDictation.pythonstreamConfig.minChunkDuration)"
hs -c "print(spoon.hs_whisperDictation.pythonstreamConfig.silenceThreshold)"
```

**Restart server:**
```bash
lsof -ti:12342 | xargs kill -9
# Server will restart on next recording with new parameters
```

### Empty Chunks

**Check Python VAD constants** in `whisper_stream.py`:
- `VAD_CONSECUTIVE_SILENCE_REQUIRED` should be 2
- `VAD_SPEECH_THRESHOLD` should be 0.25

**Restart Hammerspoon** after changing Python file:
```bash
killall Hammerspoon && open -a Hammerspoon
```

## Architecture

```
User → RecordingAdapter → StreamingBackend → hs.task (Python server)
                                           → hs.socket (TCP)
                                           → EventBus (events)
                                           → Promise (async)

Python Server:
  ├─ sounddevice (audio capture)
  ├─ Silero VAD (speech detection)
  ├─ Consecutive silence detection
  └─ Chunk generation
```

## Event Flow

```
Python server → TCP socket → StreamingBackend:_handleServerEvent()
                           → EventBus:emit("audio:chunk_ready")
                           → ChunkAssembler
                           → Transcription
                           → Paste
```

## Next Steps

- ✅ All critical issues resolved
- ✅ VAD consecutive silence working
- ✅ Configuration optimized
- ⏭️ Monitor for any edge cases in production use
- ⏭️ Consider making silence thresholds user-configurable via hotkey

## Related Documentation

- `STREAMING_BACKEND_REFACTOR.md` - Details of the refactoring
- `docs/ARCHITECTURE.md` - Overall architecture (needs update)
- `tests/spec/unit/backends/streaming_backend_spec.lua` - Unit tests
