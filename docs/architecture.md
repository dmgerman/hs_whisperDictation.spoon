# Architecture

## Overview

WhisperDictation uses a clean Manager pattern with callback-based communication. The architecture prioritizes simplicity, testability, and single-user non-reentrant operation.

**Key Characteristics:**
- ~400 lines Manager vs. 1500-line "God Object" (original)
- 408+ tests (368 Lua + 40 Python)
- Callback-based (no EventBus, no custom Promises)
- Interface-based extensibility

## Core Components

### Manager (`core/manager.lua`)

**Responsibilities:**
- State machine: IDLE → RECORDING → TRANSCRIBING → ERROR → IDLE
- Minimal tracking: state, pending count, results array
- Coordinates recorder and transcriber via callbacks
- No knowledge of chunks (implementation detail of recorders)

**State Machine:**
```
IDLE ──startRecording()──> RECORDING
RECORDING ──stopRecording()──> TRANSCRIBING
TRANSCRIBING ──completion──> IDLE
any state ──error──> ERROR
ERROR ──reset()──> IDLE
```

**Key Methods:**
- `startRecording(lang)` - Start recording session
- `stopRecording()` - Stop and begin transcription
- `reset()` - Reset from ERROR state

**Callbacks:**
- `_onChunkReceived(audioFile, chunkNum, isFinal)` - Chunk from recorder
- `_onTranscriptionSuccess(chunkNum, text)` - Transcription complete
- `_onTranscriptionError(chunkNum, errorMsg)` - Transcription failed
- `_onRecordingComplete()` - Recording stopped (triggers completion check)

### Recorders (`recorders/`)

**Interface:** `IRecorder`
```lua
function IRecorder:validate() → (boolean, string?)
function IRecorder:getName() → string
function IRecorder:startRecording(config, onChunk, onError) → (boolean, string?)
function IRecorder:stopRecording(onComplete, onError) → (boolean, string?)
function IRecorder:isRecording() → boolean
function IRecorder:cleanup() → boolean
```

**Implementations:**

1. **SoxRecorder** (`recorders/sox_recorder.lua`)
   - Simple single-chunk recording
   - Uses sox command for audio capture
   - Emits one chunk on stop (synchronous)

2. **StreamingRecorder** (`recorders/streaming/streaming_recorder.lua`)
   - Continuous recording with Silero VAD
   - Python server (`whisper_stream.py`) via TCP
   - Emits multiple chunks during recording (asynchronous)
   - Persistent server pattern (cleanup on spoon unload)

**Chunk Callback:**
```lua
onChunk(audioFile, chunkNum, isFinal)
```

### Transcribers (`transcribers/`)

**Interface:** `ITranscriber`
```lua
function ITranscriber:validate() → (boolean, string?)
function ITranscriber:getName() → string
function ITranscriber:transcribe(audioFile, lang, onSuccess, onError) → (boolean, string?)
function ITranscriber:cleanup() → boolean
```

**Implementations:**

1. **WhisperKitTranscriber** (`transcribers/whisperkit_transcriber.lua`)
   - Uses whisperkit-cli (Swift/CoreML)
   - Fast on Apple Silicon
   - Local inference

2. **WhisperCLITranscriber** (`transcribers/whispercli_transcriber.lua`)
   - Uses whisper-cli (llama.cpp)
   - CPU inference with GGML models
   - Fallback option

3. **WhisperServerTranscriber** (`transcribers/whisperserver_transcriber.lua`)
   - HTTP API to whisper.cpp server
   - Remote inference
   - Fallback option

**Transcription Callback:**
```lua
onSuccess(text)
onError(errorMsg)
```

### Notifier (`lib/notifier.lua`)

**UI Boundary Pattern:**
- ONLY place for `hs.alert.show()` calls
- Finite message types: 4 categories × 4 severities = 16 types
- Categories: init, config, recording, transcription
- Severities: debug, info, warning, error

**Example:**
```lua
Notifier.show("recording", "info", "Recording started")
Notifier.show("transcription", "error", "Transcription failed: " .. err)
```

## Design Principles

### 1. Single User, Non-Reentrant
- No concurrent operations
- Single Manager instance
- Explicit state checks prevent reentrancy

### 2. Manager with Explicit States
- Single source of truth: `Manager.state`
- Invalid transitions rejected
- State context tracked for debugging

### 3. Minimal Tracking
Manager tracks only:
- `state` - Current state
- `pendingTranscriptions` - Counter (not complex objects)
- `results` - Array of transcribed text
- `recordingComplete` - Boolean flag

**NOT tracked:**
- Chunk objects (recorder implementation detail)
- Transcription jobs (just counters)

### 4. Interface-Based Isolation
- `IRecorder` - Recording implementations
- `ITranscriber` - Transcription implementations
- Easy to add new implementations
- No over-engineering (simple Lua tables, not classes)

### 5. Direct Communication (Callbacks)
**No EventBus, No Promises:**
- Lua-native callbacks: `function(result)` or `function(error)`
- Option-style returns: `(boolean, string?)` for synchronous failures
- Simpler, more debuggable

**Async Pattern:**
```lua
recorder:startRecording(config,
  function(audioFile, chunkNum, isFinal)  -- onChunk
    -- Handle chunk
  end,
  function(errorMsg)  -- onError
    -- Handle error
  end
)
```

### 6. UI Boundary Pattern
- `Notifier` is the ONLY UI component
- Manager/Recorders/Transcribers are UI-agnostic
- All alerts go through `Notifier.show(category, severity, message)`
- 16 finite message types (controlled, consistent)

### 7. Lua Idioms
- Native patterns over custom abstractions
- No metatable magic
- Simple, readable code

### 8. Per-Chunk Feedback
- Immediate user feedback during long recordings
- Essential for usability
- StreamingRecorder emits chunks DURING recording
- Manager shows each chunk as it's transcribed

### 9. Async Validation
- Validate dependencies at startup
- Fallback chains: StreamingRecorder → Sox, WhisperKit → whisper-cli
- User sees working transcription immediately

## Data Flow

### Recording Cycle (StreamingRecorder)

```
1. User: toggle hotkey
   ↓
2. init.lua: calls manager:startRecording("en")
   ↓
3. Manager: IDLE → RECORDING, calls recorder:startRecording()
   ↓
4. StreamingRecorder: starts Python server, begins recording
   ↓
5. Python VAD detects silence → emits chunk via TCP
   ↓
6. StreamingRecorder: receives TCP event, calls onChunk callback
   ↓
7. Manager: _onChunkReceived(), increments pendingTranscriptions, starts transcription
   ↓
8. Transcriber: async transcription, calls onSuccess callback
   ↓
9. Manager: _onTranscriptionSuccess(), stores result, decrements pending
   ↓
10. User: toggle hotkey again
    ↓
11. init.lua: calls manager:stopRecording()
    ↓
12. Manager: RECORDING → TRANSCRIBING, marks recordingComplete=true
    ↓
13. StreamingRecorder: sends stop command, waits for final chunk
    ↓
14. Python: emits final chunk (is_final=true), sends recording_stopped
    ↓
15. StreamingRecorder: receives final chunk, calls onComplete callback
    ↓
16. Manager: _onRecordingComplete(), calls _checkIfComplete()
    ↓
17. Manager: if recordingComplete && pending==0, calls _finalize()
    ↓
18. Manager: assembles results, copies to clipboard, TRANSCRIBING → IDLE
```

### Completion Coordination

**Problem:** StreamingRecorder emits chunks DURING recording, but final chunk arrives AFTER stopRecording() returns.

**Solution:** Dual-trigger completion check
- Set `recordingComplete = true` in `stopRecording()`
- Decrement `pendingTranscriptions` in transcription callbacks
- Call `_checkIfComplete()` in BOTH places
- Finalize only when BOTH conditions met:
  - `recordingComplete == true` (recording stopped)
  - `pendingTranscriptions == 0` (all transcriptions done)

## Error Handling

### Patterns

1. **Synchronous failures:** Return `(false, errorMsg)`
2. **Async failures:** Call `onError(errorMsg)` callback
3. **State transitions:** Manager → ERROR state
4. **Recovery:** `manager:reset()` or auto-reset on next `startRecording()`

### Error Context

Errors include context for proper handling:
- "start" - Error during startRecording()
- "stop" - Error during stopRecording()
- "recording" - Error while recording in progress

### Graceful Degradation

- Partial results if some chunks fail
- Error placeholders: `[chunk N: error - msg]`
- Transcription continues for successful chunks

## Testing

### Test Levels

1. **Unit Tests** (`tests/spec/unit/`)
   - Mock Hammerspoon APIs
   - Synchronous mock behavior
   - Fast, deterministic
   - 368+ tests

2. **Integration Tests** (`tests/spec/integration/`)
   - Real audio files from fixtures
   - Mock Hammerspoon APIs
   - Tests full flows with real components
   - Two layers: mock + real audio

3. **Live Tests** (`tests/test_*.sh`)
   - Actual Hammerspoon process
   - Real async timing
   - Shell-based TAP framework
   - BlackHole virtual audio for deterministic testing

### Testing Patterns

**Mock Behavior:**
- `hs.timer.doAfter()` executes immediately
- Task completion callbacks fire during `task:start()`
- All async chains complete synchronously

**Strategy:**
- Test callback invocation (not state after return)
- Use explicit state flags (`_isRecording`)
- Expect final state in integration tests
- Register mock files before validation

**Fixtures:**
- 44+ real audio recordings with transcripts
- Smart comparison with tolerance for model variations
- Automatic discovery via `Fixtures.getCompleteRecordings()`

## Configuration

### Example (init.lua)

```lua
local wd = hs.loadSpoon("hs_whisperDictation")

wd.config = {
  recorder = "streaming",  -- or "sox"
  transcriber = "whisperkit",  -- or "whispercli", "whisperserver"

  streaming = {
    pythonPath = "~/.config/dmg/python3.12/bin/python3",
    audioInputDevice = nil,  -- nil = system default
    silenceThreshold = 2.0,
    minChunkDuration = 3.0,
    maxChunkDuration = 600.0
  },

  sox = {
    soxCmd = "/opt/homebrew/bin/sox",
    audioInputDevice = nil
  },

  whispercli = {
    executable = "/opt/homebrew/bin/whisper-cli",
    modelPath = "/usr/local/whisper/ggml-large-v3.bin"
  }
}

wd:start()
```

## Extension Points

### Adding a New Recorder

1. Implement `IRecorder` interface
2. Place in `recorders/your_recorder.lua`
3. Add factory logic in `init.lua`

### Adding a New Transcriber

1. Implement `ITranscriber` interface
2. Place in `transcribers/your_transcriber.lua`
3. Add factory logic in `init.lua`

## Lessons Learned

### Critical Bugs Fixed

1. **Manager completion race condition** - Removed premature `_checkIfComplete()` call in `stopRecording()`. Chunks arrive AFTER stop command, not before.

2. **StreamingRecorder completion timing** - Store `onComplete` callback, call it when final chunk (`is_final=true`) OR `recording_stopped` event arrives, with timeout fallback.

3. **State clearing on IDLE transition** - Manager clears `results` array when entering IDLE state (by design). Tests must check clipboard for final output, not `manager.results`.

### Best Practices

- Always update tests before changing code (TDD)
- Test that NO errors occurred, not just final state is correct
- Use explicit state flags, not object existence for state checks
- Two-layer integration testing: mocks + real audio (both essential)
- Live tests need multiple recording cycles to catch state reset bugs

---

**For detailed testing guide, see:** `testing.md`
**For architectural decisions, see:** `ai-docs/state-machine-architecture.md`
