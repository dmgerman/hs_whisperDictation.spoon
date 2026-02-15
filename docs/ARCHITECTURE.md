# Architecture Documentation

## Overview

WhisperDictation has been refactored from a 1500-line "God Object" into a clean, modular architecture following SOLID principles. The codebase is now fully tested (227 tests) and easy to extend.

## Design Principles

### 1. **Single Responsibility Principle**
Each class has exactly one reason to change:
- `RecordingManager` - Manages recording lifecycle
- `TranscriptionManager` - Manages transcription jobs
- `ChunkAssembler` - Assembles chunks in order
- `EventBus` - Pub/sub communication
- Backends - Audio capture
- Methods - Audio transcription

### 2. **Dependency Injection**
All dependencies are injected via constructor:

```lua
local manager = RecordingManager.new(backend, eventBus, config)
```

This enables:
- Easy testing with mocks
- Runtime configuration
- No global state

### 3. **Interface Segregation**
Clean contracts define expectations:

**IRecordingBackend:**
```lua
function IRecordingBackend:startRecording(config) → Promise
function IRecordingBackend:stopRecording() → Promise
function IRecordingBackend:isRecording() → boolean
function IRecordingBackend:validate() → (boolean, string?)
function IRecordingBackend:getDisplayText(lang) → string
```

**ITranscriptionMethod:**
```lua
function ITranscriptionMethod:transcribe(audioFile, lang) → Promise
function ITranscriptionMethod:validate() → (boolean, string?)
function ITranscriptionMethod:getName() → string
function ITranscriptionMethod:supportsLanguage(lang) → boolean
```

### 4. **Event-Driven Communication**
Components communicate via EventBus (pub/sub):

```lua
-- Publisher
eventBus:emit("recording:started", {lang = "en"})

-- Subscriber
eventBus:on("recording:started", function(data)
  print("Recording started:", data.lang)
end)
```

**Benefits:**
- Loose coupling
- Easy to add new listeners
- No circular dependencies

### 5. **Promise-Based Async**
All async operations use Promises:

```lua
backend:startRecording(config)
  :andThen(function()
    print("Recording started")
  end)
  :catch(function(err)
    print("Error:", err)
  end)
```

**Benefits:**
- No callback hell
- Composable (chaining, Promise.all)
- Clear error propagation

## Component Architecture

### Core Infrastructure

#### EventBus
Lightweight pub/sub system.

**Usage:**
```lua
local EventBus = require("lib.event_bus")
local bus = EventBus.new()

-- Subscribe
local unsubscribe = bus:on("event", function(data) end)

-- Publish
bus:emit("event", {key = "value"})

-- Unsubscribe
unsubscribe()
-- or
bus:off("event", listener)
```

#### Promise
A/+ Promise implementation for Lua.

**Usage:**
```lua
local Promise = require("lib.promise")

-- Create
local p = Promise.new(function(resolve, reject)
  if success then
    resolve(result)
  else
    reject(error)
  end
end)

-- Chain
p:andThen(function(result)
  return processResult(result)
end):catch(function(err)
  print("Error:", err)
end)

-- Utilities
Promise.resolve(value)
Promise.reject(reason)
Promise.all({p1, p2, p3})
```

### Business Logic

#### ChunkAssembler
Collects transcription chunks and concatenates them in order.

**Responsibilities:**
- Track chunks (out-of-order safe)
- Detect when all chunks received
- Concatenate in correct order
- Emit final result

**Events:**
- Listens: `transcription:complete`
- Emits: `transcription:all_complete`

```lua
local ChunkAssembler = require("core.chunk_assembler")
local assembler = ChunkAssembler.new(eventBus)

assembler:addChunk(1, "First chunk", "/tmp/chunk1.wav")
assembler:addChunk(2, "Second chunk", "/tmp/chunk2.wav")
assembler:recordingStopped()  -- Triggers finalization if all chunks received
```

#### RecordingManager
Manages recording lifecycle with state machine.

**States:** `idle` → `recording` → `stopping` → `idle`

**Responsibilities:**
- Control recording backend
- Track recording state
- Emit lifecycle events
- Handle errors gracefully

**Events:**
- Emits: `recording:started`, `recording:stopped`, `recording:error`

```lua
local RecordingManager = require("core.recording_manager")
local manager = RecordingManager.new(backend, eventBus, config)

manager:startRecording("en")
  :andThen(function()
    print("Recording started")
  end)
```

#### TranscriptionManager
Manages transcription job queue.

**Responsibilities:**
- Generate unique job IDs
- Track pending/completed/failed jobs
- Coordinate with transcription method
- Emit job events

**Events:**
- Emits: `transcription:started`, `transcription:complete`, `transcription:error`

```lua
local TranscriptionManager = require("core.transcription_manager")
local manager = TranscriptionManager.new(method, eventBus, config)

manager:transcribe("/tmp/audio.wav", "en")
  :andThen(function(text)
    print("Transcribed:", text)
  end)
```

### Recording Backends

#### SoxBackend
Simple recording using `sox` command.

```lua
local SoxBackend = require("backends.sox_backend")
local backend = SoxBackend.new(eventBus)

backend:startRecording({
  outputDir = "/tmp",
  filenamePrefix = "en",
  lang = "en",
  eventBus = eventBus,
  chunkDuration = 5,
})
```

#### StreamingBackend
Advanced streaming with Python server and Silero VAD.

**Features:**
- Real-time Voice Activity Detection (VAD) using Silero model
- Consecutive silence detection to filter false positives during speech
- Configurable chunk duration and silence thresholds
- Persistent server for multiple recording sessions
- TCP socket communication for real-time events

```lua
local StreamingBackend = require("backends.streaming_backend")
local backend = StreamingBackend.new(eventBus, {
  pythonExecutable = "python3",
  serverScript = "whisper_stream.py",
  tcpPort = 12342,
  silenceThreshold = 3.0,    -- Seconds of silence to trigger chunk (default: 2.0, recommended: 3.0-4.0)
  minChunkDuration = 5.0,    -- Minimum seconds before chunk can be created (default: 3.0, recommended: 5.0)
  maxChunkDuration = 600.0,  -- Maximum chunk duration (10 minutes)
})
```

**VAD Chunking Logic:**
1. Audio callback runs every 0.5 seconds
2. VAD analyzes last 32ms of audio using Silero model
3. Requires 2 consecutive silence detections (1.0s) to confirm real silence
4. After silence threshold is met AND chunk >= minChunkDuration → create chunk
5. Total silence needed: ~4.0s (1.0s VAD confirmation + 3.0s silence threshold)
6. Brief pauses during speech (< 4s) are ignored, preventing false chunking

**Architecture:**
```
Lua (StreamingBackend)
  ↕ TCP Socket (JSON events)
Python (whisper_stream.py)
  ├─ sounddevice (audio capture every 0.5s)
  ├─ Silero VAD (speech detection on 32ms windows)
  ├─ Consecutive silence detection (filters false positives)
  └─ Chunk generation (when silence + duration thresholds met)
```

### Transcription Methods

#### WhisperMethod (whisper.cpp)
```lua
local WhisperMethod = require("methods.whisper_method")
local method = WhisperMethod.new({
  modelPath = "/usr/local/whisper/ggml-large-v3.bin",
  executable = "whisper-cpp"
})
```

#### WhisperKitMethod (Apple Silicon)
```lua
local WhisperKitMethod = require("methods.whisperkit_method")
local method = WhisperKitMethod.new({
  executable = "whisperkit-cli",
  model = "large-v3"
})
```

#### WhisperServerMethod (HTTP Server)
```lua
local WhisperServerMethod = require("methods.whisper_server_method")
local method = WhisperServerMethod.new({
  host = "127.0.0.1",
  port = 8080,
  curlCmd = "curl"
})
```

#### GroqMethod (Cloud API)
```lua
local GroqMethod = require("methods.groq_method")
local method = GroqMethod.new({
  apiKey = "gsk_...",
  model = "whisper-large-v3",
  timeout = 30
})
```

### Main Orchestrator

#### WhisperDictation (v2)
Coordinates all components.

```lua
local WhisperDictation = require("whisper_dictation_v2")

local wd = WhisperDictation.new({
  backend = backend,        -- IRecordingBackend
  method = method,          -- ITranscriptionMethod
  eventBus = eventBus,      -- EventBus (optional)
  tempDir = "/tmp/whisper", -- string
  defaultLang = "en",       -- string
})

-- Simple toggle
wd:toggleRecording()
wd:toggleRecording("ja")

-- With callback
wd:toggleRecordingWithCallback("en", function(text)
  print(text)
end)

-- Status
local status = wd:getStatus()
```

#### WhisperDictation (v1 Compat)
Backward-compatible wrapper.

```lua
local WhisperDictationV1 = require("whisper_dictation_v1_compat")

local wd = WhisperDictationV1.new({...})

-- Old API works
wd:toggleTranscribe(nil)  -- Clipboard
wd:toggleTranscribe(function(text) end)  -- Callback
```

## Event Flow

### Recording Start
```
User: Press hotkey
  ↓
WhisperDictation:toggleRecording()
  ↓
RecordingManager:startRecording()
  ↓
Backend:startRecording()
  ↓
[emit] recording:started
  ↓
Update UI
```

### Chunk Ready (Streaming)
```
Python Server: Chunk ready
  ↓
[TCP] chunk_ready event
  ↓
StreamingBackend:_handleServerEvent()
  ↓
[emit] audio:chunk_ready
  ↓
WhisperDictation (listening)
  ↓
TranscriptionManager:transcribe()
  ↓
[emit] transcription:started
  ↓
Method:transcribe()
  ↓
[emit] transcription:complete
  ↓
ChunkAssembler:addChunk()
```

### Recording Stop
```
User: Press hotkey
  ↓
WhisperDictation:toggleRecording()
  ↓
RecordingManager:stopRecording()
  ↓
Backend:stopRecording()
  ↓
[emit] recording:stopped
  ↓
ChunkAssembler:recordingStopped()
  ↓
(if all chunks received)
[emit] transcription:all_complete
  ↓
WhisperDictation:_handleFinalText()
  ↓
Paste or copy to clipboard
```

## Testing Architecture

### Test Pyramid
- **70% Unit Tests** - Individual components in isolation
- **20% Integration Tests** - Component interactions
- **10% E2E Tests** - Full workflows

### Mock Strategy
All tests use mocks for external dependencies:

```lua
-- Mock backend
local mockBackend = {
  startRecording = function() return Promise.resolve() end,
  stopRecording = function() return Promise.resolve() end,
  isRecording = function() return false end,
  -- ...
}

-- Mock method
local mockMethod = {
  transcribe = function(audio, lang)
    return Promise.resolve("Transcribed text")
  end,
  -- ...
}
```

### Running Tests
```bash
cd tests
busted spec/unit/           # All tests
busted spec/unit/core/      # Core components
busted spec/unit/backends/  # Backends
busted spec/unit/methods/   # Methods
```

## Adding New Components

### New Recording Backend

1. **Implement IRecordingBackend:**
```lua
local MyBackend = {}
MyBackend.__index = MyBackend

function MyBackend.new(eventBus, config)
  local self = setmetatable({}, MyBackend)
  self.eventBus = eventBus
  self.config = config
  return self
end

function MyBackend:startRecording(config)
  local Promise = require("lib.promise")
  return Promise.new(function(resolve, reject)
    -- Your implementation
    resolve()
  end)
end

function MyBackend:stopRecording()
  -- ...
end

function MyBackend:isRecording()
  return self.isRecordingFlag
end

function MyBackend:validate()
  return true, nil
end

function MyBackend:getDisplayText(lang)
  return "🎙️ " .. lang
end

function MyBackend:getName()
  return "my-backend"
end

return MyBackend
```

2. **Write Tests:**
```lua
describe("MyBackend", function()
  local backend, eventBus

  before_each(function()
    eventBus = EventBus.new()
    backend = MyBackend.new(eventBus, {})
  end)

  it("starts recording", function()
    -- Test implementation
  end)
end)
```

3. **Use It:**
```lua
local MyBackend = require("backends.my_backend")
local wd = WhisperDictation.new({
  backend = MyBackend.new(eventBus, {...}),
  -- ...
})
```

### New Transcription Method

Similar process - implement `ITranscriptionMethod` interface.

## Best Practices

### 1. Always Use Promises
```lua
-- Good
function doAsync()
  return Promise.new(function(resolve, reject)
    -- async work
    resolve(result)
  end)
end

-- Bad (callback hell)
function doAsync(callback)
  someAsync(function(result)
    callback(result)
  end)
end
```

### 2. Emit Events for State Changes
```lua
-- Good
function RecordingManager:startRecording()
  self.state = "recording"
  self.eventBus:emit("recording:started", {...})
end

-- Bad (tight coupling)
function RecordingManager:startRecording()
  self.state = "recording"
  self.ui:updateIndicator()  -- Don't call UI directly
end
```

### 3. Inject Dependencies
```lua
-- Good
function Component.new(dependency1, dependency2)
  self.dep1 = dependency1
  self.dep2 = dependency2
end

-- Bad (global access)
function Component.new()
  self.dep1 = globalDep1  -- Hard to test
end
```

### 4. Test Everything
Every component should have comprehensive tests covering:
- Happy path
- Error cases
- Edge cases
- State transitions

## Performance Considerations

### EventBus
- O(n) emit (calls all listeners)
- Keep listeners lightweight
- Unsubscribe when done

### Promise Chaining
- Promises execute synchronously in our implementation
- No async/await overhead
- Chain efficiently

### Memory Management
- Lua has GC, but avoid leaks:
  - Unsubscribe from events
  - Clear large arrays when done
  - Don't hold references to old jobs indefinitely

## Migration Path

### Phase 1: Compatibility Layer (Current)
- Keep old `init.lua` as entry point
- Wrap new architecture with v1 compat
- Old API continues working

### Phase 2: Encourage v2 Adoption
- Document v2 API benefits
- Provide migration examples
- Keep v1 compat for backward compatibility

### Phase 3: Deprecation (Future)
- Mark v1 as deprecated
- Update docs to show v2 first
- Keep v1 compat indefinitely for existing users

## Future Enhancements

Possible additions:
- WebSocket backend for remote recording
- More transcription methods (AssemblyAI, Rev.ai)
- Audio preprocessing (noise reduction)
- Vocabulary/context injection
- Real-time streaming transcription
- Multi-speaker diarization

All can be added without breaking existing code thanks to clean architecture!
