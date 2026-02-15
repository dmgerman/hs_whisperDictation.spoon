# Chore: State Machine Architecture Refactoring

## Progress Tracking

Track completion status for each step. Update this section as work progresses.

| Step | Description                                    | Status      | Completed Date |
|------|------------------------------------------------|-------------|----------------|
| 1    | Foundation - Notifier and Directory Structure  | ✅ Complete | 2026-02-15     |
| 2    | Interface Definitions and Mock Implementations | ✅ Complete | 2026-02-15     |
| 3    | Core Manager with State Machine                | ⬜ Pending  | -              |
| 4    | SoxRecorder - Simple Recording Implementation  | ⬜ Pending  | -              |
| 5    | WhisperCLITranscriber - Simple Transcription   | ⬜ Pending  | -              |
| 6    | Integration Test - Core Subset End-to-End      | ⬜ Pending  | -              |
| 7    | Additional Recorders and Transcribers          | ⬜ Pending  | -              |
| 8    | Dual API Support in init.lua                   | ⬜ Pending  | -              |
| 9    | Validation, Fallback Chains, Documentation     | ⬜ Pending  | -              |
| 10   | Deprecation Warnings, Full Test Suite, Cleanup | ⬜ Pending  | -              |

**Status Legend:**
- ⬜ Pending - Not started
- 🔄 In Progress - Currently working on this step
- ✅ Complete - Step finished and verified

**Instructions for updating:**
When completing a step, change status from ⬜ to ✅ and add the completion date.

---

## Chore Description

Refactor WhisperDictation from event-driven architecture (EventBus + custom Promises) to Manager-based state machine architecture with explicit states, direct callbacks, and minimal tracking. This addresses critical architectural issues:

- **Multiple sources of truth** - State tracked in 4+ places leading to synchronization bugs
- **Hidden state transitions** - Implicit state changes in event handlers make debugging difficult
- **Over-engineering** - EventBus and custom Promise library (183 lines) add complexity without benefit for single-user system
- **Critical bugs** - StreamingBackend._isRecording never set to true, breaking stop functionality
- **Scattered UI alerts** - hs.alert.show() calls throughout codebase

The new architecture provides:

- **Single source of truth** - Manager.state (IDLE, RECORDING, TRANSCRIBING, ERROR)
- **Explicit state transitions** - All transitions validated and logged
- **Direct callbacks** - Lua native patterns replace EventBus and Promises
- **Minimal tracking** - Simple counter + results array instead of complex chunk objects
- **UI boundary** - Notifier as only place with hs.alert.show() calls
- **39% code reduction** - From ~3300 to ~2000 lines

This will be done **gradually in-place** with each step leaving the system fully functional. Both old and new APIs will coexist during transition.

## Relevant Files

### Source Files to Adapt From

- **`backends/sox_backend.lua`** - Current Promise-based SoxBackend, will be adapted to callback-based SoxRecorder
- **`backends/streaming_backend.lua`** - Current Promise-based StreamingBackend, will be adapted to callback-based StreamingRecorder
- **`methods/whisper_method.lua`** - Current WhisperMethod (WhisperCLI), will be adapted to callback-based WhisperCLITranscriber
- **`methods/whisperkit_method.lua`** - Current WhisperKitMethod, will be adapted to callback-based transcriber
- **`methods/groq_method.lua`** - Current GroqMethod, will be adapted to callback-based transcriber
- **`methods/whisper_server_method.lua`** - Current WhisperServerMethod, will be adapted to callback-based transcriber
- **`core/recording_manager.lua`** - Current RecordingManager with state machine, provides patterns to learn from
- **`core/transcription_manager.lua`** - Current TranscriptionManager with job tracking
- **`core/chunk_assembler.lua`** - Current ChunkAssembler with complex chunk objects, will be simplified
- **`lib/event_bus.lua`** - Current EventBus (to be removed from new architecture)
- **`lib/promise.lua`** - Current custom Promise library (to be removed from new architecture)
- **`init.lua`** - Main entry point, will be modified to support dual API

### Testing Infrastructure to Reuse

- **`tests/helpers/mock_hs.lua`** - Hammerspoon API mocks (reuse as-is)
- **`tests/helpers/fixtures.lua`** - Test data and fixtures (reuse as-is)
- **`tests/helpers/async_helper.lua`** - Promise testing utilities (will need callback equivalents)
- **Existing test patterns** - All specs follow consistent describe/it/before_each structure

### Python Components to Keep

- **`recorders/streaming/whisper_stream.py`** - KEEP AS-IS - Solid implementation with 40 tests, no changes needed
- **`tests/python/`** - KEEP AS-IS - All 40 Python tests remain unchanged

### New Files

All new files will be created alongside existing code (not replacing immediately):

#### Step 1: Foundation
- **`lib/notifier.lua`** - Centralized UI boundary (only place with hs.alert.show())
- **`recorders/`** - New directory for IRecorder and implementations
- **`transcribers/`** - New directory for ITranscriber and implementations
- **`core_v2/`** - New directory for new Manager (avoid collision with core/)

#### Step 2: Interfaces and Mocks
- **`recorders/i_recorder.lua`** - IRecorder interface definition (callback-based)
- **`transcribers/i_transcriber.lua`** - ITranscriber interface definition (callback-based)
- **`tests/mocks/mock_recorder.lua`** - Mock recorder for testing Manager
- **`tests/mocks/mock_transcriber.lua`** - Mock transcriber for testing Manager

#### Step 3-7: Implementations
- **`core_v2/manager.lua`** - New Manager with state machine
- **`recorders/sox_recorder.lua`** - Callback-based SoxRecorder
- **`recorders/streaming/streaming_recorder.lua`** - Callback-based StreamingRecorder
- **`transcribers/whispercli_transcriber.lua`** - Callback-based WhisperCLI transcriber
- **`transcribers/whisperkit_transcriber.lua`** - Callback-based WhisperKit transcriber
- **`transcribers/groq_transcriber.lua`** - Callback-based Groq transcriber
- **`transcribers/whisperserver_transcriber.lua`** - Callback-based WhisperServer transcriber

#### Step 9: Documentation
- **`docs/migration_guide.md`** - How to migrate from old to new architecture

## Step by Step Tasks

Execute every step in order, top to bottom. Each step leaves the system fully functional.

### Step 1: Foundation - Notifier and Directory Structure

**What to build:**

Create `lib/notifier.lua` (~100 lines) - Centralized UI boundary:
- API: `Notifier.show(category, severity, message)`
- 4 categories: `init`, `config`, `recording`, `transcription`
- 4 severities: `debug` (log only), `info` (3s alert), `warning` (5s alert), `error` (10s alert)
- Icon mapping: ✓ (init), ⚙️ (config), 🎙️ (recording), 📝 (transcription), ⚠️ (warning), ❌ (error)
- Validates category/severity on every call (fail fast on programming errors)

Create directories:
```bash
mkdir -p recorders transcribers core_v2 tests/mocks
```

**Tests to write:**
- `tests/spec/unit/lib/notifier_spec.lua` (~30 tests)
  - Category validation (valid: init/config/recording/transcription, invalid: throws)
  - Severity validation (valid: debug/info/warning/error, invalid: throws)
  - Alert display (info/warning/error show alert, debug doesn't)
  - Icon mapping per category
  - Duration mapping per severity

**Verification:**
```bash
busted tests/spec/unit/lib/notifier_spec.lua
```

Manual test:
```lua
local Notifier = dofile(hs.spoons.scriptPath() .. "lib/notifier.lua")
Notifier.show("recording", "info", "Test") -- Should show 🎙️ Test for 3s
```

---

### Step 2: Interface Definitions and Mock Implementations

**What to build:**

Create `recorders/i_recorder.lua` (~30 lines) - IRecorder interface:
```lua
-- Callback-based interface (no Promises)
function IRecorder:startRecording(config, onChunk, onError) → (success, error)
function IRecorder:stopRecording(onComplete, onError) → (success, error)
function IRecorder:validate() → (success, error)
function IRecorder:isRecording() → boolean
function IRecorder:getName() → string
```

Create `transcribers/i_transcriber.lua` (~20 lines) - ITranscriber interface:
```lua
function ITranscriber:transcribe(audioFile, lang, onSuccess, onError) → (success, error)
function ITranscriber:validate() → (success, error)
function ITranscriber:getName() → string
function ITranscriber:supportsLanguage(lang) → boolean
```

Create `tests/mocks/mock_recorder.lua` (~100 lines):
- Configurable: chunkCount (default 1), shouldFail (default false), delay (default 0.1s)
- Simulates async chunk emission via hs.timer.doAfter
- Implements IRecorder interface with option-style returns

Create `tests/mocks/mock_transcriber.lua` (~80 lines):
- Configurable: transcriptPrefix (default "Transcribed: "), shouldFail, delay
- Simulates async transcription
- Implements ITranscriber interface with option-style returns

**Tests to write:**
- `tests/spec/unit/recorders/i_recorder_spec.lua` (~10 tests)
- `tests/spec/unit/transcribers/i_transcriber_spec.lua` (~10 tests)
- `tests/spec/unit/mocks/mock_recorder_spec.lua` (~20 tests)
- `tests/spec/unit/mocks/mock_transcriber_spec.lua` (~15 tests)

**Verification:**
```bash
busted tests/spec/unit/recorders/ tests/spec/unit/transcribers/ tests/spec/unit/mocks/
```

---

### Step 3: Core Manager with State Machine

**What to build:**

Create `core_v2/manager.lua` (~400 lines) - State machine manager:

**State machine:**
- 4 states: `IDLE`, `RECORDING`, `TRANSCRIBING`, `ERROR`
- Valid transitions: IDLE→RECORDING/ERROR, RECORDING→TRANSCRIBING/ERROR, TRANSCRIBING→IDLE/ERROR, ERROR→IDLE
- Invalid transitions throw errors (caught and logged)

**Minimal tracking:**
```lua
self.state = "IDLE"
self.pendingTranscriptions = 0   -- Simple counter
self.results = {}                 -- Array indexed by chunkNum
self.recordingComplete = false
self.currentLanguage = nil
```

**Key methods:**
```lua
function Manager:transitionTo(newState, context)
  -- Validate transition is legal
  -- Log via Notifier (debug level)
  -- Update state
  -- Call state entry handler
end

function Manager:startRecording(lang)
  -- Validate state (must be IDLE)
  -- Transition to RECORDING
  -- Call recorder:startRecording(config, onChunk, onError)
  -- Return (success, error)
end

function Manager:stopRecording()
  -- Validate state (must be RECORDING)
  -- Mark recordingComplete = true
  -- Call recorder:stopRecording(onComplete, onError)
  -- Transition to TRANSCRIBING
  -- Check if already complete
  -- Return (success, error)
end

function Manager:_onChunkReceived(audioFile, chunkNum, isFinal)
  -- Increment pendingTranscriptions
  -- Start async transcription via transcriber:transcribe()
  -- On success: store result, decrement counter, show chunk feedback via Notifier
  -- On error: store error placeholder, decrement counter, show warning
  -- Call _checkIfComplete()
end

function Manager:_checkIfComplete()
  -- If recordingComplete AND pendingTranscriptions == 0
  -- Assemble results via _assembleResults()
  -- Copy to clipboard (hs.pasteboard.setContents)
  -- Show completion message via Notifier
  -- Transition to IDLE
end

function Manager:_assembleResults()
  -- Concatenate results[1], results[2], ... in order
  -- Join with "\n\n" separator
  -- Handle gaps gracefully (skip nil entries)
  -- Return final text
end
```

**Tests to write:**

`tests/spec/unit/core_v2/manager_spec.lua` (~100 tests):
- Initialization (starts in IDLE, empty results, pending=0)
- State transitions (valid/invalid combinations)
- startRecording() (validation, recorder call, return values)
- stopRecording() (validation, recorder call, state changes)
- Transcription orchestration single chunk (SoxRecorder pattern)
- Transcription orchestration multiple chunks (StreamingRecorder pattern)
- Out-of-order completion (chunk 2 before chunk 1)
- Error handling (recorder errors, transcription errors)
- Graceful degradation (partial results with some failed chunks)
- Result assembly (concatenation, gap handling)

**Verification:**
```bash
busted tests/spec/unit/core_v2/manager_spec.lua
```

Manual test with mocks:
```lua
local Manager = require("core_v2.manager")
local MockRecorder = require("tests.mocks.mock_recorder")
local MockTranscriber = require("tests.mocks.mock_transcriber")

mgr = Manager.new(
  MockRecorder.new({chunkCount = 3}),
  MockTranscriber.new(),
  {language = "en", tempDir = "/tmp"}
)
mgr:startRecording("en")
-- Wait briefly
mgr:stopRecording()
-- Should see 3 chunks transcribed, assembled, copied to clipboard
```

---

### Step 4: SoxRecorder - Simple Recording Implementation

**What to build:**

Create `recorders/sox_recorder.lua` (~150 lines) - Adapt from `backends/sox_backend.lua`:

**Key changes from SoxBackend:**
- Remove: EventBus dependency, Promise library, all `self.eventBus:emit()` calls
- Add: Direct callbacks (onChunk, onError, onComplete) passed as parameters
- Change: Return from `Promise` to `(success, error)` option-style

**Implementation:**
```lua
function SoxRecorder.new(config)
  -- NO eventBus parameter (key difference)
  self.soxCmd = config.soxCmd or "/opt/homebrew/bin/sox"
  self.task = nil  -- hs.task object when recording
end

function SoxRecorder:startRecording(config, onChunk, onError)
  if self.task then
    return false, "Already recording"
  end

  -- Generate timestamped filename
  local timestamp = os.date("%Y%m%d-%H%M%S")
  local audioFile = string.format("%s/%s-%s.wav",
    config.outputDir, config.lang, timestamp)

  self._currentAudioFile = audioFile
  self._onChunk = onChunk
  self._onError = onError

  -- Create sox task
  self.task = hs.task.new(self.soxCmd, function(exitCode, stdout, stderr)
    self.task = nil
  end, {"-q", "-d", audioFile})

  if not self.task then
    return false, "Failed to create sox task"
  end

  local ok, err = pcall(function() self.task:start() end)
  if not ok then
    self.task = nil
    return false, "Failed to start sox: " .. tostring(err)
  end

  return true, nil
end

function SoxRecorder:stopRecording(onComplete, onError)
  if not self.task then
    return false, "Not recording"
  end

  local audioFile = self._currentAudioFile
  local onChunk = self._onChunk

  self.task:terminate()
  self.task = nil

  -- Wait for file to be written
  hs.timer.doAfter(0.1, function()
    local attrs = hs.fs.attributes(audioFile)
    if not attrs then
      if onError then onError("Recording file was not created") end
      return
    end

    -- Emit single chunk (chunkNum=1, isFinal=true)
    if onChunk then onChunk(audioFile, 1, true) end
    if onComplete then onComplete() end
  end)

  return true, nil
end

function SoxRecorder:validate()
  -- Check if sox command exists
  local file = io.open(self.soxCmd, "r")
  if file then
    file:close()
    return true, nil
  end
  return false, "Sox command not found: " .. self.soxCmd
end
```

**Tests to write:**

`tests/spec/unit/recorders/sox_recorder_spec.lua` (~60 tests):
- Initialization
- validate() - Check sox exists, return option-style
- startRecording() - Task creation, state tracking, error cases
- stopRecording() - Task termination, chunk emission, file validation
- isRecording() - State queries
- Error handling (already recording, not recording, file not created)
- Integration with Manager (via mocks)

**Verification:**
```bash
busted tests/spec/unit/recorders/sox_recorder_spec.lua
```

Test with Manager + MockTranscriber:
```lua
local Manager = require("core_v2.manager")
local SoxRecorder = require("recorders.sox_recorder")
local MockTranscriber = require("tests.mocks.mock_transcriber")

mgr = Manager.new(
  SoxRecorder.new({soxCmd = "/opt/homebrew/bin/sox", tempDir = "/tmp"}),
  MockTranscriber.new(),
  {language = "en", tempDir = "/tmp"}
)
mgr:startRecording("en")
-- Record for a few seconds
mgr:stopRecording()
-- Should see 1 chunk transcribed, copied to clipboard
```

---

### Step 5: WhisperCLITranscriber - Simple Transcription Implementation

**What to build:**

Create `transcribers/whispercli_transcriber.lua` (~100 lines) - Adapt from `methods/whisper_method.lua`:

**Key changes from WhisperMethod:**
- Remove: Promise library, all `Promise.new()` wrappers
- Add: Direct callbacks (onSuccess, onError) passed as parameters
- Change: Return from `Promise` to `(success, error)` option-style

**Implementation:**
```lua
function WhisperCLITranscriber.new(config)
  self.config = config
  self.executable = config.executable or "whisper-cpp"
  self.modelPath = config.modelPath
end

function WhisperCLITranscriber:transcribe(audioFile, lang, onSuccess, onError)
  -- Validate file exists
  local file = io.open(audioFile, "r")
  if not file then
    return false, "Audio file not found: " .. audioFile
  end
  file:close()

  -- Build whisper command
  local cmd = string.format(
    "%s -m %s -l %s -f %s --output-txt 2>&1",
    self.executable, self.modelPath, lang, audioFile
  )

  -- Execute asynchronously (io.popen blocks, so use timer for async pattern)
  hs.timer.doAfter(0.01, function()
    local handle = io.popen(cmd)
    if not handle then
      if onError then onError("Failed to execute whisper command") end
      return
    end

    local output = handle:read("*a")
    local success, exitType, exitCode = handle:close()

    if not success then
      if onError then
        onError("Whisper failed: " .. (output or "unknown error"))
      end
      return
    end

    -- Read transcription from output file
    local txtFile = audioFile .. ".txt"
    local transcriptHandle = io.open(txtFile, "r")
    if not transcriptHandle then
      if onError then onError("Failed to read transcription output") end
      return
    end

    local text = transcriptHandle:read("*a")
    transcriptHandle:close()
    os.remove(txtFile)  -- Cleanup

    text = text:match("^%s*(.-)%s*$")  -- Trim whitespace

    if onSuccess then onSuccess(text) end
  end)

  return true, nil  -- Return indicates started successfully
end

function WhisperCLITranscriber:validate()
  -- Check executable exists
  local file = io.open(self.executable, "r")
  if not file then
    return false, "Whisper executable not found: " .. self.executable
  end
  file:close()

  -- Check model exists
  file = io.open(self.modelPath, "r")
  if not file then
    return false, "Model file not found: " .. self.modelPath
  end
  file:close()

  return true, nil
end
```

**Tests to write:**

`tests/spec/unit/transcribers/whispercli_transcriber_spec.lua` (~60 tests):
- Initialization
- validate() - Check executable and model exist
- transcribe() - File validation, command execution, output reading
- Callback invocation (onSuccess with text, onError on failures)
- Error handling (file not found, command failed, output not readable)
- Integration with Manager (via mocks)

**Verification:**
```bash
busted tests/spec/unit/transcribers/whispercli_transcriber_spec.lua
```

Test with Manager + SoxRecorder (end-to-end):
```lua
local Manager = require("core_v2.manager")
local SoxRecorder = require("recorders.sox_recorder")
local WhisperCLITranscriber = require("transcribers.whispercli_transcriber")

mgr = Manager.new(
  SoxRecorder.new({soxCmd = "/opt/homebrew/bin/sox", tempDir = "/tmp"}),
  WhisperCLITranscriber.new({
    executable = "/opt/homebrew/bin/whisper-cpp",
    modelPath = "/usr/local/whisper/ggml-large-v3.bin"
  }),
  {language = "en", tempDir = "/tmp"}
)
mgr:startRecording("en")
-- Record something
mgr:stopRecording()
-- Should see real transcription, copied to clipboard
```

---

### Step 6: Integration Test - Core Subset End-to-End

**What to build:**

Create `tests/spec/integration/new_architecture_basic_spec.lua` (~50 tests):

Test complete flow with Manager + SoxRecorder + WhisperCLITranscriber:
- Full recording session (IDLE → RECORDING → TRANSCRIBING → IDLE)
- Single chunk emission from SoxRecorder
- Transcription callback invocation
- Result storage and assembly
- Clipboard copy
- Notifier feedback messages at each stage
- State machine validation (reject invalid transitions)
- Error handling (sox not found, whisper failed, file not created)
- Error recovery (transition to ERROR state, auto-reset)

**Tests to write:**

```lua
describe("New Architecture - Basic Flow", function()
  describe("SoxRecorder + WhisperCLITranscriber", function()
    it("should complete full recording session")
    it("should emit exactly 1 chunk (chunkNum=1, isFinal=true)")
    it("should transcribe chunk successfully")
    it("should store result in results[1]")
    it("should copy result to clipboard")
    it("should show per-chunk feedback via Notifier")
    it("should show completion message")
    it("should transition back to IDLE")
  end)

  describe("State machine validation", function()
    it("should reject startRecording when already RECORDING")
    it("should reject stopRecording when IDLE")
    it("should reject invalid transitions")
  end)

  describe("Error recovery", function()
    it("should handle sox not found")
    it("should handle whisper-cli not found")
    it("should handle audio file not created")
    it("should handle transcription failure")
    it("should show error messages via Notifier")
    it("should transition to ERROR state")
  end)
end)
```

**Verification:**
```bash
busted tests/spec/integration/new_architecture_basic_spec.lua
```

Manual test in Hammerspoon console:
```lua
-- Load all components
local Manager = require("core_v2.manager")
local SoxRecorder = require("recorders.sox_recorder")
local WhisperCLITranscriber = require("transcribers.whispercli_transcriber")

-- Create manager
mgr = Manager.new(
  SoxRecorder.new({
    soxCmd = "/opt/homebrew/bin/sox",
    tempDir = "/tmp/whisper_dict"
  }),
  WhisperCLITranscriber.new({
    executable = "/opt/homebrew/bin/whisper-cpp",
    modelPath = "/usr/local/whisper/ggml-large-v3.bin"
  }),
  {language = "en", tempDir = "/tmp/whisper_dict"}
)

-- Test recording
mgr:startRecording("en")  -- Should see "Recording started" alert
-- Speak for a few seconds
mgr:stopRecording()       -- Should see "Transcribing...", "Chunk 1: ...", "Complete!"
-- Check clipboard: hs.pasteboard.getContents() should have transcription
```

---

### Step 7: Additional Recorders and Transcribers

**What to build:**

Create `recorders/streaming/streaming_recorder.lua` (~400 lines):
- Adapt from `backends/streaming_backend.lua`
- Remove: EventBus, Promises
- Add: Direct callbacks, option-style returns
- Keep: Python server integration, TCP communication, VAD chunking
- **Key difference from Sox:** Emits multiple chunks during recording (not just at stop)

Create `transcribers/whisperkit_transcriber.lua` (~100 lines):
- Adapt from `methods/whisperkit_method.lua`
- Same Promise → callback transformation as WhisperCLI

Create `transcribers/groq_transcriber.lua` (~120 lines):
- Adapt from `methods/groq_method.lua`
- Same transformation pattern

Create `transcribers/whisperserver_transcriber.lua` (~120 lines):
- Adapt from `methods/whisper_server_method.lua`
- Same transformation pattern

**Python component:**
- `recorders/streaming/whisper_stream.py` - **KEEP AS-IS** (already solid, 40 tests)

**Tests to write:**
- `tests/spec/unit/recorders/streaming_recorder_spec.lua` (~80 tests)
- `tests/spec/unit/transcribers/whisperkit_transcriber_spec.lua` (~50 tests)
- `tests/spec/unit/transcribers/groq_transcriber_spec.lua` (~50 tests)
- `tests/spec/unit/transcribers/whisperserver_transcriber_spec.lua` (~50 tests)
- `tests/spec/integration/new_architecture_streaming_spec.lua` (~40 tests)

Integration tests should verify:
- Multiple chunks from StreamingRecorder
- Per-chunk feedback for each chunk
- Out-of-order transcription completion
- Result assembly in correct order [1, 2, 3]
- Completion only when all chunks done AND recording stopped

**Verification:**
```bash
busted tests/spec/unit/recorders/streaming_recorder_spec.lua
busted tests/spec/unit/transcribers/
busted tests/spec/integration/new_architecture_streaming_spec.lua
```

---

### Step 8: Dual API Support in init.lua

**What to build:**

Modify `init.lua` to support both old and new architectures:

**Add configuration flag:**
```lua
obj.useNewArchitecture = false  -- Default to old (will be deprecated)
```

**Add dual initialization paths:**
```lua
function obj:start()
  if self.useNewArchitecture then
    return self:_startNewArchitecture()
  else
    return self:_startOldArchitecture()
  end
end

function obj:_startNewArchitecture()
  -- Load Manager, Notifier
  local Manager = dofile(self.spoonPath .. "core_v2/manager.lua")
  local Notifier = dofile(self.spoonPath .. "lib/notifier.lua")

  -- Create recorder based on config
  local recorder
  if self.config.recorder == "streaming" then
    local StreamingRecorder = dofile(self.spoonPath .. "recorders/streaming/streaming_recorder.lua")
    recorder = StreamingRecorder.new(self.config.streaming or {})
  else  -- Default to sox
    local SoxRecorder = dofile(self.spoonPath .. "recorders/sox_recorder.lua")
    recorder = SoxRecorder.new(self.config.sox or {})
  end

  -- Create transcriber based on config
  local transcriber
  if self.config.transcriber == "whisperkit" then
    local WhisperKitTranscriber = dofile(self.spoonPath .. "transcribers/whisperkit_transcriber.lua")
    transcriber = WhisperKitTranscriber.new(self.config.whisperkit or {})
  else  -- Default to whispercli
    local WhisperCLITranscriber = dofile(self.spoonPath .. "transcribers/whispercli_transcriber.lua")
    transcriber = WhisperCLITranscriber.new(self.config.whispercli or {})
  end

  -- Create manager
  self.manager = Manager.new(recorder, transcriber, {
    language = self.currentLang or "en",
    tempDir = self.tempDir
  })

  -- Validate (will be extended with fallback chains in Step 9)
  local ok, err = recorder:validate()
  if not ok then
    Notifier.show("init", "error", err)
    return false
  end

  ok, err = transcriber:validate()
  if not ok then
    Notifier.show("init", "error", err)
    return false
  end

  Notifier.show("init", "info", "WhisperDictation ready (new architecture)")
  return true
end

function obj:_startOldArchitecture()
  -- Existing initialization code (unchanged)
  -- Load EventBus, Promises, RecordingManager, TranscriptionManager, etc.
end

function obj:toggle()
  if self.useNewArchitecture then
    return self:_toggleNew()
  else
    return self:_toggleOld()
  end
end

function obj:_toggleNew()
  if self.manager.state == "IDLE" then
    return self.manager:startRecording(self.currentLang)
  elseif self.manager.state == "RECORDING" then
    return self.manager:stopRecording()
  else
    return false, "Invalid state: " .. self.manager.state
  end
end

function obj:_toggleOld()
  -- Existing toggle logic (unchanged)
end
```

**Tests to write:**

`tests/spec/integration/dual_api_spec.lua` (~30 tests):
- Old API works by default (useNewArchitecture=false)
- New API works when enabled (useNewArchitecture=true)
- Both APIs provide same public methods (start, stop, toggle)
- Both APIs accept same configuration
- Both APIs produce same end result (clipboard)
- Configuration differences (recorder vs recordingBackend naming)

**Verification:**
```bash
busted tests/spec/integration/dual_api_spec.lua
```

Test both APIs:
```lua
-- Old API (default)
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = false  -- Explicit (or omit)
wd:start()
wd:toggle()  -- Uses old architecture

-- New API (opt-in)
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = true
wd.config = {
  recorder = "sox",
  transcriber = "whispercli",
  sox = {soxCmd = "/opt/homebrew/bin/sox"},
  whispercli = {
    executable = "/opt/homebrew/bin/whisper-cpp",
    modelPath = "/usr/local/whisper/ggml-large-v3.bin"
  }
}
wd:start()
wd:toggle()  -- Uses new architecture
```

---

### Step 9: Validation, Fallback Chains, and Documentation

**What to build:**

**Add to `core_v2/manager.lua` - Async validation (~50 lines):**
```lua
function Manager:_validateAndInitialize(fallbackRecorder, fallbackTranscriber)
  -- Validate recorder (async)
  local ok, err = self.recorder:validate()
  if not ok then
    Notifier.show("init", "warning",
      "Primary recorder unavailable: " .. err)

    if fallbackRecorder then
      ok, err = fallbackRecorder:validate()
      if not ok then
        Notifier.show("init", "error", "No working recorders found")
        return false, "No working recorders"
      end
      self.recorder = fallbackRecorder
      Notifier.show("init", "info",
        "Using fallback recorder: " .. self.recorder:getName())
    else
      return false, err
    end
  end

  -- Validate transcriber (async)
  ok, err = self.transcriber:validate()
  if not ok then
    Notifier.show("init", "warning",
      "Primary transcriber unavailable: " .. err)

    if fallbackTranscriber then
      ok, err = fallbackTranscriber:validate()
      if not ok then
        Notifier.show("init", "error", "No working transcribers found")
        return false, "No working transcribers"
      end
      self.transcriber = fallbackTranscriber
      Notifier.show("init", "info",
        "Using fallback transcriber: " .. self.transcriber:getName())
    else
      return false, err
    end
  end

  Notifier.show("init", "info",
    string.format("WhisperDictation ready: %s + %s",
      self.recorder:getName(), self.transcriber:getName()))

  return true, nil
end
```

**Update `init.lua` `_startNewArchitecture()` to use fallback chains:**
- StreamingRecorder → SoxRecorder (if Python unavailable)
- WhisperKit → WhisperCLI (if not Apple Silicon)

**Create `docs/migration_guide.md` (~200 lines):**
```markdown
# Migration Guide: Old to New Architecture

## Quick Start

Enable new architecture:
```lua
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = true
wd:start()
```

## Configuration Changes

Old:
```lua
wd.recordingBackend = "pythonstream"
wd.transcriptionMethod = "whisperkit"
```

New:
```lua
wd.config = {
  recorder = "streaming",  -- "sox" or "streaming"
  transcriber = "whisperkit"  -- "whispercli", "whisperkit", "groq", "whisperserver"
}
```

## Benefits

- Explicit state tracking (easier debugging)
- Async validation with automatic fallback
- Better error messages (Notifier UI boundary)
- 39% smaller codebase

## Fallback Behavior

Automatic fallbacks:
- StreamingRecorder → SoxRecorder
- WhisperKit → WhisperCLI

Shows warnings via Notifier when falling back.
```

**Tests to write:**

`tests/spec/integration/validation_fallback_spec.lua` (~40 tests):
- Recorder fallback (Streaming → Sox)
- Transcriber fallback (WhisperKit → WhisperCLI)
- Async validation behavior
- Warning messages via Notifier
- Failure when no recorders/transcribers available

**Verification:**
```bash
busted tests/spec/integration/validation_fallback_spec.lua
```

Test fallback manually:
```lua
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = true
wd.config = {
  recorder = "streaming",  -- Assume Python not available
  transcriber = "whisperkit"  -- Assume not Apple Silicon
}
wd:start()
-- Should see warnings and fallback to Sox + WhisperCLI
```

---

### Step 10: Deprecation Warnings, Full Test Suite, Cleanup

**What to build:**

**Add deprecation warning to old API in `init.lua`:**
```lua
function obj:_startOldArchitecture()
  -- Show deprecation warning
  if hs.alert then
    hs.alert.show(
      "⚠️ Old architecture deprecated. Set useNewArchitecture=true. See docs/migration_guide.md",
      10
    )
  end

  -- Continue with existing old code
  -- ... (unchanged)
end
```

**Update documentation:**
- Update `readme.md` - Add section on new architecture (mention it's recommended)
- Update `CLAUDE.md` - Document new architecture principles
- Ensure all examples in readme show new architecture

**Optional - Move old code to `deprecated/` directory:**
```bash
mkdir deprecated
mv backends deprecated/
mv methods deprecated/
mv core/recording_manager.lua deprecated/core/
mv core/transcription_manager.lua deprecated/core/
mv core/chunk_assembler.lua deprecated/core/
mv lib/event_bus.lua deprecated/lib/
mv lib/promise.lua deprecated/lib/
```
Then update require paths in `init.lua` `_startOldArchitecture()`.

**Final test verification:**

Ensure complete test coverage:
- All new tests written (~340 Lua tests)
- Python tests unchanged (40 tests)
- Total: ~380 tests

**Tests to write:**

`tests/spec/integration/deprecation_spec.lua` (~10 tests):
- Old API shows deprecation warning
- New API doesn't show deprecation warning
- Both APIs still function correctly

**Verification:**
```bash
# Run full test suite
make test        # Should pass ~380 tests (340 Lua + 40 Python)
make test-live   # Should pass all live integration tests
```

Test both APIs one final time:
```lua
-- Old API (shows deprecation warning)
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = false
wd:start()  -- Shows 10-second warning
wd:toggle()

-- New API (no warning)
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = true
wd:start()  -- No warning
wd:toggle()
```

Check documentation is complete:
- `readme.md` recommends new architecture
- `docs/migration_guide.md` is comprehensive
- `CLAUDE.md` documents new principles

**Decision on old code removal:**
- Recommended: Keep both APIs for 1-2 release cycles
- Mark old API as deprecated
- Remove in next major version (v3.0)

---

## Validation Commands

Execute every command to validate the chore is complete with zero regressions.

**Full test suite:**
```bash
cd /Users/dmg/.hammerspoon/Spoons/hs_whisperDictation.spoon
make test
```
Expected: ~380 tests pass (340 Lua + 40 Python)

**Live integration tests:**
```bash
make test-live
```
Expected: All 5 backend tests pass (sox, pythonstream, whisperkit, whispercli, whisperserver)

**Unit tests by component:**
```bash
busted tests/spec/unit/lib/notifier_spec.lua
busted tests/spec/unit/recorders/
busted tests/spec/unit/transcribers/
busted tests/spec/unit/core_v2/
busted tests/spec/unit/mocks/
```

**Integration tests:**
```bash
busted tests/spec/integration/new_architecture_basic_spec.lua
busted tests/spec/integration/new_architecture_streaming_spec.lua
busted tests/spec/integration/dual_api_spec.lua
busted tests/spec/integration/validation_fallback_spec.lua
busted tests/spec/integration/deprecation_spec.lua
```

**Manual verification with old API:**
```lua
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = false
wd:start()
wd:toggle()
-- Should work exactly as before (with deprecation warning)
```

**Manual verification with new API:**
```lua
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = true
wd.config = {recorder = "sox", transcriber = "whispercli"}
wd:start()
wd:toggle()
-- Should work with new state machine architecture
```

**Verify fallback chains:**
```lua
wd = hs.loadSpoon("hs_whisperDictation")
wd.useNewArchitecture = true
wd.config = {
  recorder = "streaming",  -- If unavailable, should fall back to sox
  transcriber = "whisperkit"  -- If unavailable, should fall back to whispercli
}
wd:start()
-- Check Notifier messages show fallback warnings
```

---

## Document changes

**Files to update:**

1. **`readme.md`** - Add "New Architecture (Recommended)" section:
   ```markdown
   ## Architecture

   WhisperDictation now supports two architectures:

   ### New Architecture (Recommended)

   Enable with `wd.useNewArchitecture = true`

   - Explicit state machine (IDLE, RECORDING, TRANSCRIBING, ERROR)
   - Direct callbacks (simpler, faster)
   - Better error messages
   - Automatic fallback chains

   See `docs/migration_guide.md` for details.

   ### Legacy Architecture (Deprecated)

   Default for backward compatibility. Will be removed in v3.0.
   ```

2. **`CLAUDE.md`** - Update architecture principles:
   ```markdown
   ## Architecture Principles (v2)

   1. **Single User, Non-Reentrant** - One recording at a time
   2. **Manager with Explicit States** - IDLE/RECORDING/TRANSCRIBING/ERROR
   3. **Minimal Tracking** - Counter + results array (not complex objects)
   4. **Direct Communication** - Callbacks, not EventBus
   5. **Lua Idioms** - Native patterns, not custom abstractions
   6. **UI Boundary** - Notifier is ONLY place for hs.alert.show()
   7. **Option-Style Returns** - (success, error) everywhere
   8. **Async Validation** - Fallback chains at startup
   ```

3. **`docs/migration_guide.md`** - Created in Step 9

4. **`testing.md`** - Update test count and architecture notes

---

## Git log

```
Refactor: Migrate to Manager-based state machine architecture

This major refactoring addresses critical architectural issues and
simplifies the codebase by 39% (~1300 lines removed).

Changes:
- Replace event-driven architecture with explicit state machine
- Remove EventBus and custom Promise library (use direct callbacks)
- Centralize UI alerts in Notifier (UI boundary pattern)
- Simplify transcription tracking (counter + array vs complex chunks)
- Rename Backend→Recorder, Method→Transcriber (domain language)
- Add async validation with automatic fallback chains
- Support dual API (old deprecated, new recommended)

Architecture improvements:
- Single source of truth for state (Manager.state)
- Explicit state transitions with validation
- Option-style returns (success, error) everywhere
- Minimal tracking reduces complexity
- Direct callbacks more Lua-idiomatic than Promises

Benefits:
- Easier debugging (explicit state transitions)
- Better error messages (Notifier categorizes all alerts)
- Fewer bugs (single source of truth prevents synchronization issues)
- Simpler codebase (39% reduction: 3300→2000 lines)
- Better user experience (async validation, automatic fallbacks)

Testing:
- 380 total tests (340 Lua + 40 Python)
- All existing tests rewritten for new architecture
- Python tests unchanged (whisper_stream.py kept as-is)
- Both old and new APIs fully tested

Migration:
- Old API deprecated but still works (shows warning)
- New API opt-in via useNewArchitecture=true
- See docs/migration_guide.md for details
- Old API will be removed in v3.0

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## Notes

### Implementation Order Rationale

Steps are ordered to build incrementally from foundation to complexity:

1. **Steps 1-3**: Foundation (Notifier, interfaces, Manager) - No dependencies
2. **Steps 4-5**: Simple implementations (Sox, WhisperCLI) - Prove the architecture
3. **Step 6**: Integration test - Verify core subset works end-to-end
4. **Step 7**: Complex implementations (Streaming, other transcribers) - Build on proven foundation
5. **Steps 8-9**: Integration (dual API, validation) - Connect to existing system
6. **Step 10**: Polish (deprecation, cleanup) - Finalize migration

### Key Transformation Pattern

**Old (Promise + EventBus):**
```lua
function Backend:startRecording(config)
  return Promise.new(function(resolve, reject)
    -- Do work
    self.eventBus:emit("recording:started", {...})
    resolve()
  end)
end
```

**New (Callback + Option-style):**
```lua
function Recorder:startRecording(config, onChunk, onError)
  -- Do work
  if onChunk then onChunk(audioFile, chunkNum, isFinal) end
  return true, nil  -- (success, error)
end
```

### Testing Strategy

- **Unit tests** - Each component in isolation (with mocks)
- **Integration tests** - Component interactions (Manager + Recorder + Transcriber)
- **Live tests** - Real Hammerspoon environment (unchanged, run separately)

### Backward Compatibility

Both APIs will coexist during transition:
- Old API deprecated but functional (default for now)
- New API opt-in via `useNewArchitecture = true`
- Same public methods (start, stop, toggle)
- Same end result (transcription in clipboard)

### Critical Success Factors

1. **Each step must leave system fully functional** - Both APIs work after every step
2. **Tests must pass before moving to next step** - No broken intermediate states
3. **Python code stays unchanged** - whisper_stream.py and its 40 tests remain as-is
4. **Gradual migration** - Users can switch when ready, not forced immediately
