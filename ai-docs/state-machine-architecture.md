# WhisperDictation Manager Architecture

**Document Version:** 2.1
**Date:** 2026-02-15
**Status:** Proposed Architecture (Not Implemented)

---

## Overview

This document describes the proposed architecture for WhisperDictation spoon, centered around a **Manager** with explicit state management as the single source of truth for all system state.

### Design Principles

1. **Single User, Non-Reentrant** - One recording session at a time, no concurrent operations
2. **Explicit State Management** - All state transitions are explicit and validated (IDLE/RECORDING/TRANSCRIBING/ERROR)
3. **Interface-Based Isolation** - Recorders and Transcribers implement clear contracts
4. **Direct Communication** - Callbacks instead of EventBus, simplicity over abstraction
5. **Domain Language** - Use "Recorder" and "Transcriber", not "Backend" and "Method"
6. **Lua Idioms** - Native callbacks, not custom Promise implementations
7. **Option-Style Returns** - Functions return (success, error), caller handles display
8. **UI Boundary** - Notifier is the ONLY place that shows alerts or logs messages
9. **Fail Fast** - Validate at startup (async), fallback to working configuration
10. **Minimal Tracking** - Manager tracks only what it needs: state, pending count, results array

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      WhisperDictation                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Manager (Core)                         │  │
│  │  - Single source of truth for state (IDLE/RECORDING/...)│  │
│  │  - Validates state transitions                           │  │
│  │  - Orchestrates recorder + transcriber                   │  │
│  │  - Tracks pending transcriptions (counter + results)     │  │
│  │  - Provides per-chunk feedback via Notifier             │  │
│  └───────────────────────────────────────────────────────────┘  │
│           │                            │                         │
│           ▼                            ▼                         │
│  ┌─────────────────┐          ┌─────────────────┐              │
│  │   IRecorder     │          │  ITranscriber   │              │
│  │  (Interface)    │          │   (Interface)   │              │
│  └─────────────────┘          └─────────────────┘              │
│           │                            │                         │
│           ├── SoxRecorder              ├── WhisperKitTranscriber│
│           └── StreamingRecorder        ├── GroqTranscriber      │
│               (has subdirectory)       ├── WhisperCLITranscriber│
│                                        └── WhisperServerTranscriber
└─────────────────────────────────────────────────────────────────┘
```

**Only two public components:** Recorder and Transcriber. Everything else is internal to Manager.

---

## Public API vs Internal Implementation

### User-Facing Public API

What users of the spoon interact with:

```lua
local wd = hs.loadSpoon("hs_whisperDictation")

-- Configuration (public)
wd.config = {
  recorder = "streaming",        -- or "sox"
  transcriber = "whisperkit",    -- or "groq", "whispercli", "whisperserver"
  languages = {"en", "ja"},
  tempDir = "/tmp/whisper_dict",
  -- ... recorder/transcriber specific configs
}

-- Public methods
wd:start()                       -- Initialize and validate
wd:stop()                        -- Shutdown
wd:toggle()                      -- Toggle recording on/off
wd:startRecording()              -- Explicit start
wd:stopRecording()               -- Explicit stop
wd:bindHotKeys(mapping)          -- Bind keyboard shortcuts
wd:switchRecorder("sox")         -- Switch recorder (requires restart)
wd:switchTranscriber("groq")     -- Switch transcriber (requires restart)
```

### Extension API (Public Interfaces)

What developers implement to extend functionality:

**IRecorder Interface:**
```lua
startRecording(config, onChunk, onError) → success, error
stopRecording(onComplete, onError) → success, error
validate() → success, error
```

**ITranscriber Interface:**
```lua
transcribe(audioFile, lang, onSuccess, onError) → success, error
validate() → success, error
```

### Internal Implementation (Private)

Not exposed to users, subject to change without notice:

```lua
-- Manager internals
Manager:transitionTo(newState, context)             -- ❌ Private
Manager:_onChunkReceived(audioFile, ...)            -- ❌ Private
Manager:_checkIfComplete()                          -- ❌ Private
Manager:_assembleResults()                          -- ❌ Private
Manager.state                                       -- ❌ Private state
Manager.pendingTranscriptions                       -- ❌ Private state
Manager.results                                     -- ❌ Private state

-- Recorder internals
StreamingRecorder:_startServer(...)                 -- ❌ Private
StreamingRecorder:_handleServerEvent(...)           -- ❌ Private

-- Notifier internals
Notifier:_getIconAndDuration(...)                   -- ❌ Private
```

---

## State Machine

### The Four States

The system exists in exactly one of four states at any time:

```
┌──────────────────────────────────────────────────────────────┐
│                     STATE MACHINE                             │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│   ┌──────┐  startRecording()   ┌───────────┐               │
│   │ IDLE │ ──────────────────> │ RECORDING │               │
│   └──────┘                      └───────────┘               │
│      ↑                               │                       │
│      │                               │ stopRecording()       │
│      │                               ↓                       │
│      │                          ┌──────────────┐            │
│      │                          │ TRANSCRIBING │            │
│      │                          └──────────────┘            │
│      │                               │                       │
│      └──────── all chunks done ──────┘                       │
│                                                               │
│   Any State ──── error ────> ┌───────┐                      │
│                               │ ERROR │                      │
│                               └───────┘                      │
│                                   │                           │
│                                   │ timeout/reset            │
│                                   ↓                           │
│                               ┌──────┐                       │
│                               │ IDLE │                       │
│                               └──────┘                       │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

### State Descriptions

#### IDLE
**What it means:** System is ready, waiting for user action.

**Valid actions:**
- Start recording (→ RECORDING)

**State data:**
- No active recording
- No chunks being tracked
- No transcription in progress

---

#### RECORDING
**What it means:** Microphone is active, audio is being captured.

**What happens in this state:**
- Recorder is capturing audio
- Chunks may be emitted as recording continues (streaming mode)
- Each chunk triggers immediate transcription (asynchronous)
- User can stop recording at any time

**Valid actions:**
- Stop recording (→ TRANSCRIBING)

**State data:**
- Current language
- Chunks received so far (may be empty initially)
- Recording not yet complete

---

#### TRANSCRIBING
**What it means:** Recording stopped, waiting for all transcriptions to complete.

**What happens in this state:**
- Recording is complete (no more chunks will arrive)
- Some chunks may still be transcribing (async operations in flight)
- System waits for all pending transcriptions
- Chunks are assembled in order as they complete

**Transition out:**
- When all chunks transcribed (→ IDLE)
- On error (→ ERROR)

**State data:**
- All chunks received
- Recording marked complete
- Transcription status per chunk (pending/complete/error)

---

#### ERROR
**What it means:** Something went wrong, system is in recovery mode.

**What happens in this state:**
- Error displayed to user via Notifier
- Recording/transcription stopped
- Auto-reset timer started (5 seconds)
- User can manually reset

**Transition out:**
- After timeout (→ IDLE)
- On manual reset (→ IDLE)

**State data:**
- Error message
- Error source (recorder/transcriber/system)
- Recovery timer

---

### State Transition Rules

**Valid transitions:**
```
IDLE         → RECORDING, ERROR
RECORDING    → TRANSCRIBING, ERROR
TRANSCRIBING → IDLE, ERROR
ERROR        → IDLE
```

**Invalid transitions (will throw error):**
```
IDLE         → TRANSCRIBING  ❌ (must record first)
RECORDING    → IDLE          ❌ (must stop recording first)
TRANSCRIBING → RECORDING     ❌ (must finish or error first)
ERROR        → RECORDING     ❌ (must reset to IDLE first)
```

### Transition Validation

Every state change goes through `transitionTo()`:
1. **Validate** - Check if transition is legal (throw error if not)
2. **Log** - Record transition via Notifier
3. **Update** - Change state variable
4. **Handle** - Execute state entry handler

This ensures:
- ✅ State changes are always explicit
- ✅ Invalid transitions are caught immediately
- ✅ All transitions are logged for debugging
- ✅ State entry/exit logic is centralized

---

## Manager Internal State: Minimal Transcription Tracking

The Manager orchestrates transcriptions with **minimal tracking**. It doesn't need to know about "chunks" - that's a Recorder implementation detail. The Manager only cares about:
1. How many transcriptions are pending?
2. What are the results (indexed by number)?
3. Is recording complete?

**Why track transcriptions?** Immediate user feedback during long recordings:
```
StreamingRecorder (multiple chunks):
"Chunk 1: Hello, this is a test..."
"Chunk 2: I'm recording a long document..."
"Chunk 3: Almost done now..."

SoxRecorder (single file):
"Chunk 1: [entire recording transcribed at once]"
```

**Important distinction:**
- **StreamingRecorder**: Emits multiple chunks during recording (chunk 1, 2, 3...) → multiple transcriptions → assembled result
- **SoxRecorder**: Emits exactly 1 file when stopped (chunk 1 only) → single transcription → done

Manager handles both cases identically - it just counts pending transcriptions and collects results.

**Internal data structures (minimal):**
```lua
self.state = "IDLE"  -- IDLE | RECORDING | TRANSCRIBING | ERROR
self.pendingTranscriptions = 0   -- Simple counter
self.results = {}                 -- Array indexed by chunk number
self.recordingComplete = false    -- Has recorder finished?
```

**How it works:**
```lua
function Manager:_onChunkReceived(audioFile, chunkNum, isFinal)
  self.pendingTranscriptions = self.pendingTranscriptions + 1

  -- Start async transcription
  self.transcriber:transcribe(audioFile, self.language,
    function(text)  -- onSuccess
      self.results[chunkNum] = text
      self.pendingTranscriptions = self.pendingTranscriptions - 1

      -- Per-chunk feedback (essential requirement!)
      Notifier.show("transcription", "info",
        string.format("Chunk %d: %s", chunkNum, text:sub(1, 50) .. "..."))

      self:_checkIfComplete()
    end,
    function(error)  -- onError
      self.results[chunkNum] = "[Error in chunk " .. chunkNum .. "]"
      self.pendingTranscriptions = self.pendingTranscriptions - 1

      Notifier.show("transcription", "warning",
        string.format("Chunk %d failed: %s", chunkNum, error))

      self:_checkIfComplete()  -- Graceful degradation
    end
  )
end

function Manager:stopRecording()
  self.recordingComplete = true
  self:transitionTo("TRANSCRIBING")
  self:_checkIfComplete()  -- Might already be done
end

function Manager:_checkIfComplete()
  if self.recordingComplete and self.pendingTranscriptions == 0 then
    local finalText = self:_assembleResults()
    hs.pasteboard.setContents(finalText)
    Notifier.show("transcription", "info", "Complete! Copied to clipboard")
    self:transitionTo("IDLE")
  end
end

function Manager:_assembleResults()
  local parts = {}
  for i = 1, #self.results do
    if self.results[i] then
      table.insert(parts, self.results[i])
    end
  end
  return table.concat(parts, "\n\n")
end
```

**Example: Out-of-order completion (StreamingRecorder with 3 chunks):**
```
Recording emits: chunk 1, chunk 2, chunk 3
Transcriptions complete: chunk 2 (fast), chunk 1 (slow), chunk 3 (medium)

Manager state:
- results[1] = "Hello..."      (completed second)
- results[2] = "This is..."    (completed first)
- results[3] = "The end."      (completed third)
- Assembles in order: results[1] + "\n\n" + results[2] + "\n\n" + results[3]
```

**Example: Single file (SoxRecorder with 1 chunk):**
```
Recording emits: chunk 1 (when stopped)
Transcription completes: chunk 1

Manager state:
- results[1] = "Hello, this is the entire recording..."
- recordingComplete = true, pendingTranscriptions = 0
- Done! (No assembly needed, just copy results[1])
```

**Graceful degradation:**
```
If chunk 2 fails to transcribe:
- results[1] = "Hello..."
- results[2] = "[Error in chunk 2]"
- results[3] = "The end."
- User gets partial result instead of total failure
- Notifier shows warning for chunk 2, but continues
```

**Why this is minimal:** Manager doesn't track chunk metadata, status flags, or complex objects. Just a counter and a results array. Simple and sufficient.

---

## Component Architecture

### Recorder (Audio Capture)

**Responsibility:** Capture audio from microphone, emit audio chunks.

**Interface (IRecorder):**
```lua
startRecording(config, onChunk, onError) → success, error
stopRecording(onComplete, onError) → success, error
validate() → success, error
```

**Implementations:**

#### SoxRecorder
- **Strategy:** Simple, single-file recording (NO chunking)
- **How it works:**
  1. Starts `sox` process capturing to timestamped WAV file
  2. Records until stopped
  3. On stop: emits single file with complete audio
  4. Calls `onChunk(audioFile, chunkNum=1, isFinal=true)` ONCE
  5. Recording complete

- **Key point:** This recorder does NOT chunk. One recording session = one file = one transcription.
- **Pros:** Simple, reliable, no dependencies, no Python required
- **Cons:** No real-time feedback during recording, no silence detection, user must wait until end for transcription

**File:** `recorders/sox_recorder.lua`

---

#### StreamingRecorder

- **Strategy:** Continuous recording WITH chunking (VAD-based)
- **Location:** `recorders/streaming/` subdirectory (contains all streaming-specific code)
- **How it works:**
  1. Starts Python server (`whisper_stream.py`) via TCP
  2. Server continuously captures audio
  3. Server uses Silero VAD to detect speech/silence boundaries
  4. Server emits chunks when silence detected or max duration reached
  5. Each chunk triggers `onChunk(audioFile, chunkNum, isFinal)` - **multiple times during recording**
  6. On stop: server emits final chunk and stops

- **Key point:** This recorder DOES chunk. One recording session = multiple files = multiple transcriptions = assembled result.
- **Pros:** Real-time per-chunk feedback (essential for long recordings), intelligent chunking, handles unlimited duration
- **Cons:** More complex, requires Python dependencies (sounddevice, torch, silero-vad)

**Files:**
```
recorders/streaming/
├── streaming_recorder.lua    # Main recorder implementation
├── whisper_stream.py         # Python server (TCP, VAD, chunking logic)
└── README.md                 # Setup instructions, dependencies
```

**Why subdirectory?** StreamingRecorder is complex with multiple files:
- Lua recorder implementation
- Python server with VAD
- TCP communication protocol
- Chunking logic specific to this recorder
- Keeping it in a subdirectory makes it clear this is all part of one recorder implementation

**Key Design Point:** Recorders are **stateless** with respect to recording lifecycle. They don't track "am I recording?" - the Manager does. They only track operational state (is server running?).

---

### Transcriber (Speech Recognition)

**Responsibility:** Convert audio file to text.

**Interface (ITranscriber):**
```lua
transcribe(audioFile, lang, onSuccess, onError)
validate() → success, error
```

**Implementations:**

#### WhisperKitTranscriber
- **Strategy:** Local, Apple Silicon optimized
- **File:** `transcribers/whisperkit_transcriber.lua`
- **How it works:**
  1. Validates audio file exists (returns false if not)
  2. Executes `whisperkit-cli` command asynchronously
  3. Passes audio file path and language
  4. Reads transcribed text from stdout
  5. Calls `onSuccess(text)` or `onError(error)`
  6. Returns `(true, nil)` if started successfully, `(false, error)` if failed to start

- **Pros:** Fast on M1/M2/M3, runs locally, no API costs
- **Cons:** Requires whisperkit-cli installation

---

#### WhisperCLITranscriber
- **Strategy:** Local whisper.cpp (fallback option)
- **File:** `transcribers/whispercli_transcriber.lua`
- **How it works:**
  1. Executes `whisper-cli` command (whisper.cpp)
  2. Reads transcribed text from stdout
  3. Calls `onSuccess(text)` or `onError(error)`

- **Pros:** Works on any platform, reliable, no API costs
- **Cons:** Slower than WhisperKit, requires model download

**This is the fallback transcriber** - if primary transcriber fails validation, system falls back to this.

---

#### GroqTranscriber
- **Strategy:** Cloud API, fast inference
- **File:** `transcribers/groq_transcriber.lua`
- **How it works:**
  1. Uploads audio file to Groq API
  2. Waits for transcription response
  3. Calls `onSuccess(text)` or `onError(error)`

- **Pros:** Very fast, no local compute
- **Cons:** Requires API key, internet, costs money

---

#### WhisperServerTranscriber
- **Strategy:** Self-hosted HTTP server
- **File:** `transcribers/whisperserver_transcriber.lua`
- **How it works:**
  1. POSTs audio file to local whisper server
  2. Server runs inference
  3. Returns transcribed text
  4. Calls `onSuccess(text)` or `onError(error)`

- **Pros:** Local control, no API costs
- **Cons:** Requires running server

---

**Key Design Point:** Transcribers are **stateless**. Each `transcribe()` call is independent. Manager tracks which chunks are pending.

---

## Notifier: UI Boundary Layer

**The ONLY place in the codebase that:**
- Calls `hs.alert.show()`
- Logs messages

**Responsibility:** Centralized message display and logging based on category and severity.

**Location:** `lib/notifier.lua`

### Message Classification

**4 Categories:**
1. **init** - Startup, validation, dependencies
2. **config** - Configuration changes, backend switching
3. **recording** - Recording lifecycle
4. **transcription** - Transcription lifecycle

**4 Severities:**
1. **debug** - Debug messages (logs only, no alert)
2. **info** - Status updates (icon + 3s alert)
3. **warning** - Non-critical issues (⚠️ + 5s alert)
4. **error** - Critical failures (❌ + 10s alert)

**Total:** 4×4 = 16 message types

### API

```lua
Notifier.show(category, severity, message)
```

**No logger parameter** - Notifier handles logging internally.

### Icon Mapping

| Category | Severity | Icon | Duration | Alert? |
|----------|----------|------|----------|--------|
| init | debug | - | - | No (log only) |
| init | info | ✓ | 3s | Yes |
| init | warning | ⚠️ | 5s | Yes |
| init | error | ❌ | 10s | Yes |
| config | debug | - | - | No (log only) |
| config | info | ⚙️ | 3s | Yes |
| config | warning | ⚠️ | 5s | Yes |
| config | error | ❌ | 10s | Yes |
| recording | debug | - | - | No (log only) |
| recording | info | 🎙️ | 3s | Yes |
| recording | warning | ⚠️ | 5s | Yes |
| recording | error | ❌ | 10s | Yes |
| transcription | debug | - | - | No (log only) |
| transcription | info | 📝 | 3s | Yes |
| transcription | warning | ⚠️ | 5s | Yes |
| transcription | error | ❌ | 10s | Yes |

### Usage Examples

```lua
local Notifier = require("lib.notifier")

-- Startup
Notifier.show("init", "info", "WhisperDictation ready: sox + whisperkit")
  → "✓ WhisperDictation ready: sox + whisperkit" (3s)

-- Fallback warning
Notifier.show("init", "warning", "StreamingRecorder unavailable, using Sox")
  → "⚠️ StreamingRecorder unavailable, using Sox" (5s)

-- Recording
Notifier.show("recording", "info", "Recording started (en)")
  → "🎙️ Recording started (en)" (3s)

Notifier.show("recording", "error", "Microphone not available")
  → "❌ Microphone not available" (10s)

-- Transcription
Notifier.show("transcription", "info", "Chunk 1: Hello this is a test...")
  → "📝 Chunk 1: Hello this is a test..." (3s)

Notifier.show("transcription", "warning", "Chunk 2 failed, continuing with others")
  → "⚠️ Chunk 2 failed, continuing with others" (5s)

-- Debug (no alert)
Notifier.show("transcription", "debug", "Chunk 1 transcription took 2.3s")
  → (logs only, no alert shown)

-- Config changes
Notifier.show("config", "info", "Switched to streaming recorder")
  → "⚙️ Switched to streaming recorder" (3s)
```

### Implementation

```lua
--- lib/notifier.lua
local Logger = require("lib.logger")
local logger = Logger.new()  -- Internal logger

local Notifier = {}

-- Valid categories and severities (finite set - prevents explosion)
local CATEGORIES = {
  init = true,
  config = true,
  recording = true,
  transcription = true
}

local SEVERITIES = {
  debug = true,
  info = true,
  warning = true,
  error = true
}

function Notifier.show(category, severity, message)
  -- Validate (fail fast on programming errors)
  if not CATEGORIES[category] then
    error("Invalid category: " .. tostring(category))
  end
  if not SEVERITIES[severity] then
    error("Invalid severity: " .. tostring(severity))
  end

  -- Always log
  logger:log(severity, string.format("[%s] %s", category, message))

  -- Show alert based on severity
  if severity == "debug" then
    return  -- Debug only logs, doesn't show alert
  end

  local icon, duration = Notifier._getIconAndDuration(category, severity)
  hs.alert.show(string.format("%s %s", icon, message), duration)
end

function Notifier._getIconAndDuration(category, severity)
  if severity == "error" then
    return "❌", 10
  elseif severity == "warning" then
    return "⚠️", 5
  else -- info
    -- Category-specific icons
    local icons = {
      init = "✓",
      config = "⚙️",
      recording = "🎙️",
      transcription = "📝"
    }
    return icons[category] or "ℹ️", 3
  end
end

return Notifier
```

---

## Error Handling Strategy

### Option-Style Returns

All functions use **option-style returns** instead of throwing errors:

```lua
function IRecorder:validate()
  -- Check dependencies
  if not fileExists(self.cmd) then
    return false, "Command not found: " .. self.cmd
  end

  return true, nil
end

function IRecorder:startRecording(config, onChunk, onError)
  -- Start recording
  if not self.task then
    return false, "Failed to create task"
  end

  return true, nil
end

function ITranscriber:transcribe(audioFile, lang, onSuccess, onError)
  -- Check file exists
  if not fileExists(audioFile) then
    return false, "Audio file not found: " .. audioFile
  end

  -- Start async transcription
  startAsyncTask(...)

  return true, nil
end
```

**Pattern:** `return success, error`
- **Success:** `return true, nil` (operation started successfully)
- **Failure:** `return false, error_message` (operation failed to start)
- **Note:** Return value indicates whether operation **started** successfully, callbacks deliver async results

### Error Display via Notifier

**Caller decides whether and how to display errors:**

```lua
-- Internal validation - show error and handle
local ok, err = recorder:validate()
if not ok then
  Notifier.show("init", "error", err)
  -- Try fallback or fail
end

-- User-initiated action - show error
local ok, err = recorder:startRecording(...)
if not ok then
  Notifier.show("recording", "error", err)
  return false
end

-- Internal chunk error - log, continue
local ok, err = transcriber:transcribe(...)
if not ok then
  Notifier.show("transcription", "warning", "Chunk " .. num .. " failed: " .. err)
  -- Continue with other chunks (graceful degradation)
end
```

### Graceful Degradation

**Principle:** Partial success is better than total failure.

**Examples:**

1. **Chunk transcription fails:**
   ```
   Chunk 2 fails to transcribe:
   - Show warning via Notifier
   - Mark chunk as error
   - Continue transcribing other chunks
   - Final text: chunk1 + "[Error in chunk 2]" + chunk3
   ```

2. **Recorder validation fails:**
   ```
   StreamingRecorder.validate() fails:
   - Show warning: "StreamingRecorder unavailable, using Sox"
   - Fall back to SoxRecorder
   - Continue startup
   ```

3. **Transcriber validation fails:**
   ```
   WhisperKitTranscriber.validate() fails:
   - Show warning: "WhisperKit unavailable, using whisper-cli"
   - Fall back to WhisperCLITranscriber
   - Continue startup
   ```

---

## Startup Validation and Fallback

### Async Validation at Load Time

When user loads the spoon (`wd:start()`), system performs **async validation**:

1. **Show initial message:**
   ```lua
   Notifier.show("init", "info", "⏳ WhisperDictation starting...")
   ```

2. **Validate recorder (async):**
   ```lua
   -- Try preferred recorder
   local ok, err = preferredRecorder:validate()
   if not ok then
     Notifier.show("init", "warning", "StreamingRecorder unavailable: " .. err)

     -- Try fallback (Sox)
     ok, err = soxRecorder:validate()
     if not ok then
       Notifier.show("init", "error", "No working recorders found")
       return false  -- Fail startup
     end

     -- Use Sox fallback
     recorder = soxRecorder
     Notifier.show("init", "info", "Using Sox recorder (fallback)")
   end
   ```

3. **Validate transcriber (async):**
   ```lua
   -- Try preferred transcriber
   local ok, err = preferredTranscriber:validate()
   if not ok then
     Notifier.show("init", "warning", "WhisperKit unavailable: " .. err)

     -- Try fallback (whisper-cli)
     ok, err = whisperCLITranscriber:validate()
     if not ok then
       Notifier.show("init", "error", "No working transcribers found")
       return false  -- Fail startup
     end

     -- Use whisper-cli fallback
     transcriber = whisperCLITranscriber
     Notifier.show("init", "info", "Using whisper-cli (fallback)")
   end
   ```

4. **For StreamingRecorder, start server (async):**
   ```lua
   if recorder == streamingRecorder then
     -- Start Python server in background
     local ok, err = recorder:_startServerAsync()
     if not ok then
       Notifier.show("init", "warning", "Server startup failed: " .. err)
       -- Fall back to Sox
       recorder = soxRecorder
       Notifier.show("init", "info", "Using Sox recorder (fallback)")
     end
   end
   ```

5. **Show final status:**
   ```lua
   Notifier.show("init", "info",
     string.format("WhisperDictation ready: %s + %s",
       recorder:getName(), transcriber:getName()))
   ```

### Fallback Chains

**Recorder fallback:**
```
User preference: StreamingRecorder
  ↓ (validation fails)
Fallback: SoxRecorder
  ↓ (validation fails)
Error: "No working recorders found" → Don't start spoon
```

**Transcriber fallback:**
```
User preference: WhisperKitTranscriber
  ↓ (validation fails)
Fallback: WhisperCLITranscriber
  ↓ (validation fails)
Error: "No working transcribers found" → Don't start spoon
```

### Validation Checks

**Recorder validation:**
- Check command exists (`sox` or Python executable)
- Check dependencies installed (for StreamingRecorder: sounddevice, torch)
- For StreamingRecorder: Start server and verify it responds

**Transcriber validation:**
- Check command exists (`whisperkit-cli`, `whisper-cli`, `curl`)
- Check model files exist (for local transcribers)
- Check API key set (for cloud transcribers)

### Runtime Failures (No Fallback)

**Once startup succeeds, runtime failures do NOT trigger automatic fallback.**

Example:
```
Startup: StreamingRecorder validated successfully
Runtime: User starts recording, server crashes
Action: Show error, transition to ERROR state, don't auto-switch to Sox
Reason: User chose streaming for a reason (per-chunk feedback),
        auto-switching would be unexpected behavior
```

User can manually switch recorders via config.

---

## Backend Switching API

### How to Switch Recorders/Transcribers

**Pattern: Config change + restart**

```lua
-- User wants to switch to Sox recorder
wd.config.recorder = "sox"
wd:stop()
wd:start()  -- Revalidates, loads new recorder

-- Or combined:
wd:switchRecorder("sox")  -- Helper method that does stop + change config + start
```

### Helper Methods

```lua
function obj:switchRecorder(recorderName)
  Notifier.show("config", "info", "Switching to " .. recorderName .. " recorder...")

  self.config.recorder = recorderName
  self:stop()
  return self:start()  -- Returns success/error
end

function obj:switchTranscriber(transcriberName)
  Notifier.show("config", "info", "Switching to " .. transcriberName .. " transcriber...")

  self.config.transcriber = transcriberName
  self:stop()
  return self:start()  -- Returns success/error
end
```

### Usage

```lua
-- User switches recorder
local ok, err = wd:switchRecorder("streaming")
if not ok then
  -- Error already shown via Notifier during start()
  -- Fallback already attempted
  -- If we get here, nothing works
end

-- User switches transcriber
wd:switchTranscriber("groq")  -- Switch to cloud API
```

**No hot-swapping** - switching requires stop/start cycle. This ensures clean state and validation.

---

## Configuration

### Recorder Selection: Chunking vs Non-Chunking

**Two fundamentally different recording strategies:**

| Aspect | SoxRecorder | StreamingRecorder |
|--------|-------------|-------------------|
| **Chunking** | NO - single file | YES - multiple chunks |
| **Feedback** | At end only | Real-time per chunk |
| **Duration** | Limited (must fit in memory) | Unlimited (streams) |
| **Dependencies** | sox only | Python + sounddevice + torch |
| **Use case** | Quick recordings (<2 min) | Long recordings, interviews, dictation |
| **Files emitted** | 1 file when stopped | N files during recording |
| **Transcriptions** | 1 transcription at end | N transcriptions during recording |

### Structure

Configuration is **flat and organized by component**:

```lua
obj.config = {
  -- Component selection
  recorder = "streaming",     -- "sox" (single file, no chunking) or "streaming" (multiple chunks, real-time feedback)
  transcriber = "whisperkit", -- "whisperkit", "groq", "whispercli", "whisperserver"

  -- Recording settings
  tempDir = "/tmp/whisper_dict",
  languages = {"en", "ja", "es"},

  -- Recorder-specific configs
  sox = {
    cmd = "/opt/homebrew/bin/sox"
  },

  streaming = {
    pythonExecutable = "~/.config/dmg/python3.12/bin/python3",
    port = 12342,
    silenceThreshold = 2.0,
    minChunkDuration = 3.0,
    maxChunkDuration = 600.0
  },

  -- Transcriber-specific configs
  whisperkit = {
    cmd = "/opt/homebrew/bin/whisperkit-cli",
    model = "large-v3"
  },

  whispercli = {
    cmd = "/opt/homebrew/bin/whisper-cli",
    modelPath = "/usr/local/whisper/ggml-large-v3.bin"
  },

  groq = {
    apiKey = os.getenv("GROQ_API_KEY"),
    model = "whisper-large-v3"
  },

  whisperserver = {
    host = "127.0.0.1",
    port = "8080",
    curlCmd = "/usr/bin/curl"
  }
}
```

### How Configuration Works

**At startup (`obj:start()`):**
1. Read `obj.config.recorder` → "streaming"
2. Load recorder implementation: `recorders/streaming/streaming_recorder.lua`
3. Create instance: `StreamingRecorder.new(obj.config.streaming)`
4. Validate: `recorder:validate()` → checks Python exists, dependencies installed
5. For StreamingRecorder: Start server async
6. Repeat for transcriber
7. Create manager: `Manager.new(recorder, transcriber, config)`

**No factory pattern** - Simple conditional:
```lua
local recorder
if config.recorder == "sox" then
  local SoxRecorder = dofile(spoonPath .. "recorders/sox_recorder.lua")
  recorder = SoxRecorder.new(config.sox)
elseif config.recorder == "streaming" then
  local StreamingRecorder = dofile(spoonPath .. "recorders/streaming/streaming_recorder.lua")
  recorder = StreamingRecorder.new(config.streaming)
else
  return false, "Unknown recorder: " .. config.recorder
end
```

---

## File Structure

```
hs_whisperDictation.spoon/
├── init.lua                      # Entry point (~300 lines)
│                                 # - Configuration
│                                 # - Component initialization
│                                 # - Validation & fallback logic
│                                 # - Public API (start, stop, toggle, etc.)
│
├── core/
│   └── manager.lua               # Core manager (~400 lines)
│                                 # - State transitions (IDLE/RECORDING/TRANSCRIBING/ERROR)
│                                 # - Transcription orchestration (minimal tracking)
│                                 # - Recorder + Transcriber coordination
│
├── recorders/
│   ├── i_recorder.lua            # Interface (~30 lines)
│   ├── sox_recorder.lua          # Simple recorder (~150 lines)
│   └── streaming/                # StreamingRecorder subdirectory
│       ├── streaming_recorder.lua    # Main implementation (~400 lines)
│       ├── whisper_stream.py         # Python server (~800 lines)
│       └── README.md                 # Setup, dependencies
│
├── transcribers/
│   ├── i_transcriber.lua         # Interface (~20 lines)
│   ├── whisperkit_transcriber.lua    # Apple Silicon (~100 lines)
│   ├── whispercli_transcriber.lua    # Fallback (~100 lines)
│   ├── groq_transcriber.lua          # Cloud API (~120 lines)
│   └── whisperserver_transcriber.lua # Self-hosted (~120 lines)
│
└── lib/
    ├── notifier.lua              # UI boundary (~100 lines)
    └── logger.lua                # Logging (~100 lines)
```

**Total estimated:** ~1200 lines Lua + 800 lines Python = ~2000 lines

**vs Current:** ~2500 lines Lua + 800 lines Python = ~3300 lines

**Reduction:** ~1300 lines removed (39% smaller)
- EventBus, Promises, Manager layers, Factories
- Complex chunk tracking replaced with counter + array

---

## Testing Strategy

### Tests Must Be Rewritten

The proposed architecture is **not backward compatible** with current tests. All tests must be rewritten to match the new architecture.

### Test Coverage

#### 1. Manager Tests (~100 tests)
```lua
describe("Manager", function()
  describe("State transitions", function()
    it("should transition from IDLE to RECORDING on startRecording")
    it("should transition from RECORDING to TRANSCRIBING on stopRecording")
    it("should transition from TRANSCRIBING to IDLE when all transcriptions complete")
    it("should transition to ERROR on recorder error")
    it("should reject invalid transitions (IDLE → TRANSCRIBING)")
  end)

  describe("Transcription orchestration", function()
    it("should track pending transcriptions count")
    it("should handle multiple transcriptions from StreamingRecorder")
    it("should handle out-of-order transcription completion")
    it("should assemble results in correct order by index")
    it("should handle transcription errors gracefully (partial results)")
    it("should only complete when recordingComplete=true AND pendingTranscriptions=0")
  end)
end)
```

#### 2. Recorder Tests (~60 tests)
```lua
describe("SoxRecorder", function()
  it("should validate sox command exists")
  it("should start recording and emit single chunk")
  it("should return error if sox not found")
end)

describe("StreamingRecorder", function()
  it("should validate Python and dependencies")
  it("should start server and connect via TCP")
  it("should emit multiple chunks based on VAD")
  it("should handle server crashes gracefully")
end)
```

#### 3. Transcriber Tests (~60 tests)
```lua
describe("WhisperKitTranscriber", function()
  it("should validate whisperkit-cli exists")
  it("should transcribe audio file and return text")
  it("should handle transcription errors")
end)
```

#### 4. Notifier Tests (~30 tests)
```lua
describe("Notifier", function()
  it("should validate category names")
  it("should validate severity levels")
  it("should show alert for info messages")
  it("should only log for debug messages")
  it("should throw error for invalid category")
end)
```

#### 5. Integration Tests (~50 tests)
```lua
describe("Full recording session", function()
  describe("SoxRecorder (non-chunking)", function()
    it("should record single file, transcribe once, copy to clipboard")
    it("should emit exactly 1 chunk with isFinal=true")
    it("should transition IDLE → RECORDING → TRANSCRIBING → IDLE")
  end)

  describe("StreamingRecorder (chunking)", function()
    it("should record multiple chunks, transcribe each, assemble final text")
    it("should emit chunks 1, 2, 3... during recording")
    it("should show per-chunk feedback to user")
    it("should handle out-of-order transcription completion")
  end)

  describe("Fallback chains", function()
    it("should fall back to Sox when StreamingRecorder fails validation")
    it("should fall back to whisper-cli when WhisperKit fails validation")
  end)
end)
```

#### 6. Python Tests (keep existing ~40 tests)
```lua
# whisper_stream.py tests
- VAD detection
- Chunk emission
- TCP communication
- Server lifecycle
```

**Total:** ~340 tests (300 Lua + 40 Python)

### Test Infrastructure

**Mock components:**
```lua
-- tests/mocks/mock_recorder.lua
local MockRecorder = {}

function MockRecorder:startRecording(config, onChunk, onError)
  -- Simulate chunk emission
  hs.timer.doAfter(0.1, function()
    onChunk("/tmp/test.wav", 1, true)
  end)
  return true, nil
end
```

**Test helpers:**
```lua
-- tests/helpers/manager_helper.lua
function createManager(opts)
  local recorder = opts.recorder or MockRecorder.new()
  local transcriber = opts.transcriber or MockTranscriber.new()
  local config = opts.config or {language = "en", tempDir = "/tmp"}
  return Manager.new(recorder, transcriber, config)
end
```

---

## Python Integration: whisper_stream.py

### Role in Architecture

The Python script (`whisper_stream.py`) is an **implementation detail of StreamingRecorder**. It's not a separate architectural component.

**Location:** `recorders/streaming/whisper_stream.py`

### How It Works

**Architecture:**
```
StreamingRecorder (Lua)
    ↕ TCP (JSON events)
whisper_stream.py (Python)
    ↕ Audio callbacks
sounddevice (microphone)
```

**Communication Protocol:**

**Lua → Python (Commands):**
```json
{"command": "start_recording"}
{"command": "stop_recording"}
{"command": "shutdown"}
```

**Python → Lua (Events):**
```json
{"type": "server_ready"}
{"type": "recording_started"}
{"type": "chunk_ready", "chunk_num": 1, "audio_file": "/tmp/...", "is_final": false}
{"type": "recording_stopped"}
{"type": "error", "error": "..."}
```

**Lifecycle:**

1. **Startup:**
   - Lua starts Python subprocess: `hs.task.new(pythonPath, args)`
   - Python starts TCP server on configured port
   - Python sends `server_ready` event
   - Lua connects TCP client

2. **Recording:**
   - Lua sends `start_recording` command
   - Python starts capturing from microphone
   - Python runs Silero VAD on audio stream
   - When silence detected: Python saves chunk, sends `chunk_ready` event
   - Lua receives event, calls `onChunk()` callback
   - StreamingRecorder emits to Manager

3. **Shutdown:**
   - Lua sends `stop_recording` command
   - Python saves final chunk, sends `recording_stopped`
   - Lua sends `shutdown` command
   - Python exits cleanly

### Key Design Decisions

**Why TCP instead of stdout?**
- Bidirectional communication (Lua can send commands)
- Asynchronous events (chunks can arrive anytime)
- Clean separation (audio processing isolated in Python)

**Why subprocess instead of HTTP server?**
- Auto-lifecycle management (Lua starts/stops it)
- No manual server setup required
- Isolated per-user (no global server)

**Why Python instead of pure Lua?**
- Silero VAD requires PyTorch (no Lua equivalent)
- sounddevice library (robust audio capture)
- Rich audio processing ecosystem

**Why this is in recorders/streaming/ subdirectory:**
- TCP communication is specific to StreamingRecorder
- VAD chunking is specific to StreamingRecorder
- Python server is specific to StreamingRecorder
- Keeping it together makes dependencies clear

---

## Comparison: Current vs Proposed

### Architectural Differences

| Aspect | Current Architecture | Proposed Architecture |
|--------|---------------------|----------------------|
| **Core Model** | Event-driven (EventBus) | Manager with explicit states |
| **State Tracking** | 3 sources of truth | 1 source of truth (Manager.state) |
| **Async Model** | Custom Promises (183 lines) | Lua callbacks |
| **Communication** | EventBus events | Direct callbacks |
| **Components** | Backend, Method, Manager, Factory | Recorder, Transcriber, Manager |
| **Transcription Tracking** | Complex chunk objects with status | Simple counter + results array |
| **Lines of Code** | ~3300 total | ~2000 total |
| **Indirection Layers** | 5+ (EventBus→Manager→Backend→EventBus→Handler) | 2 (Manager→Recorder/Transcriber) |
| **State Transitions** | Implicit, scattered | Explicit, validated, centralized |
| **Debuggability** | Hard (trace events) | Easy (direct calls, state log) |
| **Error Handling** | Throws + EventBus | Option-style returns + Notifier |
| **UI Boundary** | Scattered hs.alert calls | Centralized in Notifier |
| **Startup Validation** | Synchronous | Asynchronous with fallback |

### What We Keep (Strengths)

✅ **Interface contracts** - IRecorder, ITranscriber define clear APIs
✅ **Separate implementations** - Multiple recorders/transcribers
✅ **Dependency injection** - Pass dependencies in, don't hard-code
✅ **Out-of-order result handling** - Assembles results in correct order (minimal tracking in Manager)
✅ **Per-chunk feedback** - Immediate user feedback during long recordings
✅ **Python backend** - Silero VAD integration via whisper_stream.py (now in recorders/streaming/)
✅ **Test suite** - 408 tests total (will be rewritten for new architecture)

### What We Remove (Over-Engineering)

❌ **EventBus** - Indirection without benefit, use direct callbacks
❌ **Promise library** - 183 lines custom code, use Lua callbacks
❌ **Manager layer** - RecordingManager, TranscriptionManager (thin pass-throughs)
❌ **Factory pattern** - BackendFactory, MethodFactory (simple conditionals instead)
❌ **Multiple state sources** - RecordingManager.state, Backend._isRecording
❌ **Scattered error display** - hs.alert calls throughout codebase
❌ **Complex chunk objects** - Replace with simple counter + results array
❌ **ChunkAssembler as component** - Unnecessary abstraction

### What We Add (Missing)

✅ **Manager with explicit states** - Single source of truth, explicit transitions (IDLE/RECORDING/TRANSCRIBING/ERROR)
✅ **State validation** - Catch invalid transitions immediately
✅ **State transition log** - Every state change is logged
✅ **Minimal tracking** - Simple counter + results array instead of complex chunk objects
✅ **Notifier (UI boundary)** - Centralized message display and logging
✅ **Option-style returns** - Clear success/error handling (including transcribe())
✅ **Async validation** - Non-blocking startup with fallback chains
✅ **Public API definition** - Clear separation of public vs internal
✅ **Subdirectory for StreamingRecorder** - Clear organization of complex component

---

## Key Architectural Decisions

### Decision 1: State Machine Core
**Rationale:** Single-user, non-reentrant system has clear states and transitions. State machine makes these explicit and prevents invalid state combinations.

**Alternative considered:** Keep event-driven architecture
**Why rejected:** Events hide state transitions, make debugging hard, add indirection

---

### Decision 2: Direct Callbacks Over EventBus
**Rationale:** Single user means single listener per event. Direct callbacks are simpler, more Lua-idiomatic, easier to trace.

**Alternative considered:** Keep EventBus
**Why rejected:** EventBus solves "multiple listeners" problem we don't have

---

### Decision 3: Lua Callbacks Over Promises
**Rationale:** Lua has first-class functions and closures. Callbacks are native, Promises are custom abstraction (183 lines).

**Alternative considered:** Keep Promise library
**Why rejected:** Adds complexity, not idiomatic Lua, callback nesting is manageable for our use case

---

### Decision 4: Stateless Recorders/Transcribers
**Rationale:** Recording lifecycle state belongs in Manager. Recorders/Transcribers should just implement their interface, not track "am I recording?"

**Alternative considered:** Recorders track their own state
**Why rejected:** Creates multiple sources of truth, synchronization bugs

---

### Decision 5: Rename to Recorder/Transcriber
**Rationale:** "Backend" and "Method" are technical jargon. "Recorder" and "Transcriber" are domain language, clearer to understand.

**Alternative considered:** Keep current naming
**Why rejected:** Less clear what they do, more cognitive overhead

---

### Decision 6: Notifier as UI Boundary
**Rationale:** Centralizing all UI display and logging in one place makes it easier to maintain consistent messaging and prevents alert spam.

**Alternative considered:** Allow components to show alerts directly
**Why rejected:** Leads to inconsistent messaging, hard to control display logic

---

### Decision 7: Option-Style Returns
**Rationale:** Functions returning (success, error) makes error handling explicit and testable. Caller decides whether to display error.

**Alternative considered:** Throw errors
**Why rejected:** Error handling becomes implicit, harder to control flow

---

### Decision 8: Async Validation with Fallback
**Rationale:** Don't block Hammerspoon startup. Validate async, fall back to working config automatically.

**Alternative considered:** Synchronous validation, fail immediately
**Why rejected:** Blocks Hammerspoon, bad user experience

---

### Decision 9: Minimal Tracking (Counter + Results Array)
**Rationale:** Manager doesn't need to know about "chunks" - that's a Recorder detail. It just needs to track: how many pending transcriptions? what are the results? Manager uses simple counter + results array instead of complex chunk objects.

**Alternative considered:** Track chunks as objects with {audioFile, text, status, metadata}
**Why rejected:** Unnecessary complexity. Counter + array is simpler and sufficient.

---

### Decision 10: StreamingRecorder Subdirectory
**Rationale:** StreamingRecorder is complex (Lua + Python + TCP + VAD). Keeping all related code in one subdirectory makes dependencies clear.

**Alternative considered:** Flat structure with all files in recorders/
**Why rejected:** Mixes StreamingRecorder-specific code with generic recorder code

---

## Implementation Notes

### Migration Path

This architecture is **not backward compatible** with current code. **Clean rewrite recommended.**

**Why rewrite instead of incremental refactor:**
- Core architecture is fundamentally different (EventBus → State Machine)
- Async model is different (Promises → Callbacks)
- Component structure is different (Managers removed)
- Tests must be rewritten anyway
- Incremental refactoring would be more work than clean rewrite

**Approach:**
1. Build new version in parallel (keep old code)
2. Port functionality piece by piece
3. Test each piece as it's ported
4. Switch when new version reaches feature parity
5. Delete old code

### Development Order

**Recommended build order:**

1. **Infrastructure first:**
   - Logger
   - Notifier
   - Manager (without recorder/transcriber, just state transitions)

2. **Simple recorder:**
   - IRecorder interface
   - SoxRecorder (no dependencies, easy to test)

3. **Simple transcriber:**
   - ITranscriber interface
   - WhisperCLITranscriber (fallback, reliable)

4. **Wire together:**
   - init.lua (basic version)
   - Test full flow: Sox → WhisperCLI → clipboard

5. **Add complexity:**
   - StreamingRecorder (subdirectory, Python server, TCP)
   - WhisperKitTranscriber
   - Async validation
   - Fallback chains

6. **Polish:**
   - Additional transcribers (Groq, WhisperServer)
   - Configuration helpers
   - Backend switching API
   - Documentation

---

## Conclusion

This architecture centers on a **Manager with explicit state management as single source of truth**, using **direct callbacks** for communication, **Notifier as UI boundary**, **minimal tracking** (counter + results array), and **interface-based isolation** for extensibility.

It removes unnecessary abstraction (EventBus, Promises, complex chunk objects, Managers, Factories) while adding missing features (async validation, fallback chains, centralized error display, public API definition, minimal tracking).

The result is a **simpler, more maintainable, more reliable system** that is easier to debug, easier to extend, and more appropriate for the single-user, non-reentrant use case.

**Key Improvements:**
- ✅ ~1300 lines removed (39% reduction)
- ✅ Single source of truth for state (no synchronization bugs)
- ✅ Explicit state transitions (easy to debug)
- ✅ Minimal tracking (counter + array, not complex chunk objects)
- ✅ Centralized UI boundary (consistent messaging)
- ✅ Option-style error handling everywhere (explicit, testable, including transcribe())
- ✅ Async validation with automatic fallback (better UX)
- ✅ Clear public API (ready for distribution)
- ✅ Organized file structure (clear dependencies)

---

**Document End**
