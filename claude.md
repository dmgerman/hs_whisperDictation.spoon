# Claude Code Instructions

## Code Quality Standards

- **CRITICAL: All filenames MUST be lowercase** - Use `readme.md`, NOT `README.md`
- Always document with LuaDoc format
- Use option-style returns for "fallible" functions where appropriate

## Architecture Principles

This spoon follows these core design principles (see `ai-docs/state-machine-architecture.md` for details):

1. **Single User, Non-Reentrant** - No concurrent operations, single Manager
2. **Manager with Explicit States** - Single source of truth for system state (IDLE, RECORDING, TRANSCRIBING, ERROR)
3. **Minimal Tracking** - Manager tracks only: state, pending count, results array (not complex chunk objects)
4. **Interface-Based Isolation** - `IRecorder`, `ITranscriber` for extensibility without over-engineering
5. **Direct Communication** - Lua callbacks, not EventBus or custom Promises
6. **UI Boundary Pattern** - `Notifier` is the ONLY place for `hs.alert.show()` calls
   - 4 categories: init, config, recording, transcription
   - 4 severities: debug, info, warning, error
   - Total: 16 finite message types
7. **Lua Idioms** - Native patterns over custom abstractions
8. **Per-Chunk Feedback** - Immediate user feedback during long recordings (essential requirement)
9. **Async Validation** - Validate dependencies at startup with fallback chains (StreamingRecorder → Sox, WhisperKit → whisper-cli)

### Component Naming
- Use domain language: **Recorder/Transcriber**, not Backend/Method
- Streaming-specific code goes in `recorders/streaming/` subdirectory

When reviewing or refactoring code, do a **complete systematic pass**:

1. **Review every file**, not just the ones immediately relevant
2. **Review every function** for:
   - Deep nesting (flatten with early returns)
   - Long functions (extract focused helpers)
   - Code duplication (consolidate into shared modules)
   - Magic numbers (lift to constants or config)
3. **Don't declare "done" until the full pass is complete**


### Checklist Before Declaring Work Complete

- [ ] Scanned all files in the module/spoon
- [ ] No functions over ~50 lines
- [ ] No nesting deeper than 3 levels
- [ ] No duplicated logic across files
- [ ] No magic numbers in logic (all in Theme/Config)
- [ ] All public APIs documented with LuaDoc
- [ ] Tests updated and passing (see `testing.md`)

## Testing

**CRITICAL**: This project has ~408 tests (368 Lua + 40 Python). Always update and run tests when modifying source code.

### Workflow (Required)

When modifying source code:
1. **Update tests first** (TDD approach)
2. Make the code changes
3. **Run full test suite**: `make test`
4. Verify all 368 tests pass
5. Only then declare work complete

### Running Tests

From spoon root directory:
- All tests: `make test` (~408 tests: 368 Lua + 40 Python) - **Run this before declaring work complete**
- Python tests only: `make test-python` (whisper_stream.py)
- Live tests (requires Hammerspoon): `make test-live` (verifies env + 5 backend tests)
  - 2 recording backends: sox, pythonstream
  - 3 transcription methods: whisperkit, whispercli, whisperserver
- Verbose: `busted` (Lua) or `pytest tests/python -v` (Python)
- Help: `make help`

### Test Infrastructure

- **Unit/Integration**: `tests/spec/unit/`, `tests/spec/integration/` - Busted 2.3.0+ with mocks
- **Live Tests**: `tests/test_*.sh` - Production-quality shell tests with TAP-style framework
- **Helpers**: `tests/helpers/mock_hs.lua`, `tests/lib/test_framework.sh`
- **Environment**: `tests/verify_environment.sh` - Comprehensive dependency checking

See [`testing.md`](testing.md) for detailed examples and best practices.

### Testing Patterns Validated in Step 6 (New Architecture)

**CRITICAL LEARNINGS**: Step 6 (Integration Tests) validated key patterns that apply to all remaining steps (7-10).

#### 1. Manager State Clearing Pattern

**Discovery**: Manager clears all tracking state when transitioning to IDLE:

```lua
function Manager:_onStateEntered(state, context)
  if state == Manager.STATES.IDLE then
    self.results = {}  -- ← CLEARED on IDLE entry!
    self.pendingTranscriptions = 0
    self.recordingComplete = false
    self.currentLanguage = nil
  end
end
```

**Implications for Testing**:
- ❌ **Cannot inspect `manager.results` after completion** - will always be empty
- ✅ **Must check clipboard** via `hs.pasteboard.getContents()` for final output
- ✅ **Can test in-progress state** before transition to IDLE completes
- This is **by design** for clean state resets, not a bug

**Example**:
```lua
-- ❌ WRONG - results cleared after completion
manager:startRecording("en")
manager:stopRecording()
assert.is_not_nil(manager.results[1])  -- FAILS - already cleared!

-- ✅ CORRECT - check clipboard instead
manager:startRecording("en")
manager:stopRecording()
local clipboard = MockHS.pasteboard.getContents()
assert.is_not_nil(clipboard)  -- PASSES - results copied before clearing
```

#### 2. Two-Layer Testing Strategy

**Pattern**: Every component should have TWO layers of integration tests:

**Layer 1: Mock Integration Tests**
- Fast (completes in seconds)
- Tests logic, state machines, error paths
- Uses MockRecorder + MockTranscriber
- Deterministic, no external dependencies
- Example: `tests/spec/integration/new_architecture_basic_spec.lua` (41 tests)

**Layer 2: Real Audio Integration Tests**
- Realistic validation with actual data
- Tests file handling, real components
- Uses real audio files from fixtures
- Still runs via `busted` (not live Hammerspoon)
- Example: `tests/spec/integration/new_architecture_real_audio_spec.lua` (27 tests)

**Why Both Are Essential**:
- Layer 1 catches logic bugs quickly
- Layer 2 validates real-world integration
- Don't skip either layer

**Apply This Pattern To**:
- Step 8: StreamingRecorder (mock + real audio layers)
- Step 8: Additional transcribers (mock + real audio layers)
- Step 9: Validation and fallback chains

#### 3. Mock Test Setup Pattern (CRITICAL)

**Correct Pattern** (validated across 68 tests):

```lua
-- At top of test file:
local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS  -- ← Must assign to global

-- In before_each:
MockHS._resetAll()  -- ← Note: _resetAll, not reset()

-- In after_each:
if recorder then recorder:cleanup() end  -- Clean up timers

-- In tests:
local alerts = MockHS.alert._getAlerts()  -- ← Note: _getAlerts
local clipboard = MockHS.pasteboard.getContents()
MockHS.fs._registerFile(path, { mode = "file", size = 1024 })
```

**Common Mistakes to Avoid**:
- ❌ `require("tests.helpers.mock_hs")` without `_G.hs = MockHS`
- ❌ `MockHS.reset()` instead of `MockHS._resetAll()`
- ❌ `MockHS.alert.getCalls()` instead of `MockHS.alert._getAlerts()`

#### 4. Three Testing Levels (Not Two)

**Discovery**: There are THREE distinct testing levels:

1. **Unit Tests with Mocks** (Steps 1-6)
   - Run via `busted`
   - No Hammerspoon process required
   - Synchronous mock behavior
   - Fast, deterministic

2. **Integration Tests with Real Components** (Step 6 Layer 2)
   - Run via `busted`
   - Uses real audio files from fixtures
   - Still uses mocks for Hammerspoon APIs
   - No live Hammerspoon process required

3. **Live Hammerspoon Tests** (Step 7+)
   - Run via shell scripts (`tests/test_*.sh`)
   - Actual Hammerspoon process running
   - Real async timing, real APIs
   - Test through spoon interface

**Why Live Tests Deferred to Step 7**:
- New architecture uses relative `dofile()` paths (e.g., `dofile("lib/notifier.lua")`)
- Requires correct working directory from init.lua
- Before Step 7 (init.lua integration), can't load via `hs.loadSpoon()`
- After Step 7, can use shell-based tests with `hs.loadSpoon("hs_whisperDictation")`

**Action for Steps 7+**: Add shell-based live tests after init.lua integration, following pattern from `tests/test_sox_integration.sh`.

#### 5. Fixture Infrastructure (Production-Ready)

**Available Test Data**:
- **44+ real audio recordings** with matching transcripts
- **3 fixture chunks**: short, medium, long
- **Automatic discovery**: `Fixtures.getCompleteRecordings()`
- **Smart comparison**: `Fixtures.compareTranscripts(actual, expected, tolerance)`
- **Normalization**: `Fixtures.normalizeTranscript(text)` handles whitespace/newlines
- **Performance**: <1 second to load all recordings

**Usage Pattern for Real Transcriber Testing** (Step 8):

```lua
local Fixtures = require("tests.helpers.fixtures")

-- Get real recording with transcript
local recordings = Fixtures.getCompleteRecordings()
local recording = recordings[1]

-- Transcribe with real transcriber
transcriber:transcribe(recording.audio, "en",
  function(actualText)
    -- Compare with expected (allow variations)
    local expectedText = Fixtures.readTranscript(recording.transcript)
    local match, similarity = Fixtures.compareTranscripts(
      actualText,
      expectedText,
      0.85  -- 85% tolerance for model variations
    )
    assert.is_true(match, "Similarity: " .. similarity)
  end,
  function(err) error(err) end
)
```

**Don't Create New Test Audio**: Leverage existing 44+ recordings in `tests/fixtures/` and `tests/data/`.

#### 6. Error Recovery Patterns (Validated)

**Patterns That Work Well**:

1. **Auto-reset from ERROR**: `startRecording()` auto-resets to IDLE when in ERROR state
2. **Manual reset**: `manager:reset()` available for explicit recovery
3. **Graceful degradation**: Partial results when some chunks fail
4. **Error placeholders**: Failed chunks get `[chunk N: error - msg]` in results

**All New Components Should**:
- Transition to ERROR on validation failures
- Return `(false, errorMsg)` on synchronous failures
- Call `onError(errorMsg)` for async failures
- Allow recovery via auto-reset or manual reset

#### 7. Test File Organization

**Naming Convention** (maintain for Steps 7-10):

```
tests/spec/integration/
├── new_architecture_basic_spec.lua           # ✅ Layer 1: Mocks (41 tests)
├── new_architecture_real_audio_spec.lua      # ✅ Layer 2: Real audio (27 tests)
├── new_architecture_streaming_spec.lua       # Step 8: StreamingRecorder
├── new_architecture_transcribers_spec.lua    # Step 8: All transcribers
└── new_architecture_fallback_spec.lua        # Step 9: Validation chains
```

**Pattern**: `new_architecture_<component>_spec.lua` for clear identification.

### Testing Async/Callback Code with Mocks

**CRITICAL**: The mock infrastructure (`tests/helpers/mock_hs.lua`) executes all async operations **synchronously** for testing. This requires specific testing strategies.

#### Mock Behavior

```lua
-- In mock_hs.lua, hs.timer.doAfter executes immediately:
doAfter = function(delay, fn)
  -- Execute immediately in tests (can't wait for real delays)
  if fn then
    fn()
  end
end
```

**This means:**
- Timer callbacks fire immediately, not after a delay
- Task completion callbacks fire during `task:start()`
- All async chains complete before the calling function returns

#### Testing Patterns for Callback-Based Code

##### Pattern 1: Test Callback Invocation (Not State After Return)

❌ **WRONG** - Checking state after async operation returns:
```lua
it("should emit chunk", function()
  recorder:stopRecording(onComplete, onError)
  -- Task callback already fired, state already reset!
  assert.is_nil(recorder._currentAudioFile)  -- May fail
end)
```

✅ **CORRECT** - Verify callbacks are invoked:
```lua
it("emits chunk via callback when file created", function()
  local chunkReceived = nil

  recorder:startRecording(config,
    function(audioFile, chunkNum, isFinal)
      chunkReceived = { audioFile = audioFile, chunkNum = chunkNum, isFinal = isFinal }
    end,
    function() end
  )

  -- Register file so validation passes
  MockHS.fs._registerFile(recorder._currentAudioFile, { mode = "file", size = 1024 })

  recorder:stopRecording(function() end, function() end)

  -- Callback fired synchronously, chunkReceived is populated
  assert.is_not_nil(chunkReceived)
  assert.equals(1, chunkReceived.chunkNum)
  assert.is_true(chunkReceived.isFinal)
end)
```

##### Pattern 2: Use Explicit State Flags (Not Task/Timer State)

❌ **WRONG** - Relying on task existence for state:
```lua
function Recorder:isRecording()
  return self.task ~= nil  -- Task completion callback sets task=nil immediately!
end
```

✅ **CORRECT** - Use explicit state flag:
```lua
function Recorder:isRecording()
  return self._isRecording  -- Set/cleared explicitly in start/stop
end

function Recorder:startRecording(config, onChunk, onError)
  -- ... create and start task ...
  self._isRecording = true  -- Set AFTER task:start() returns
  return true, nil
end

function Recorder:stopRecording(onComplete, onError)
  if not self._isRecording then  -- Check flag, not task
    return false, "Not recording"
  end

  self._isRecording = false  -- Clear immediately
  if self.task then
    self.task:terminate()  -- May already be nil
    self.task = nil
  end
  -- ... rest of stop logic ...
end
```

##### Pattern 3: Test "Already Active" Scenarios by Setting State Directly

❌ **WRONG** - Trying to create actual async overlap:
```lua
it("rejects if already recording", function()
  recorder:startRecording(...)  -- Auto-completes immediately in tests!
  recorder:startRecording(...)  -- First one already done, won't fail
end)
```

✅ **CORRECT** - Set state flag directly:
```lua
it("returns false and error if already recording", function()
  recorder._isRecording = true  -- Simulate recording in progress

  local success, err = recorder:startRecording(config, onChunk, onError)

  assert.is_false(success)
  assert.equals("Already recording", err)

  recorder._isRecording = false  -- Cleanup
end)
```

##### Pattern 4: Integration Tests - Expect Completion, Not In-Progress State

❌ **WRONG** - Expecting intermediate state:
```lua
it("works with Manager", function()
  manager:startRecording("en")
  manager:stopRecording()

  assert.equals(Manager.STATES.TRANSCRIBING, manager.state)  -- Already IDLE!
end)
```

✅ **CORRECT** - Expect final state and verify results:
```lua
it("works with Manager full recording cycle", function()
  manager:startRecording("en")
  MockHS.fs._registerFile(recorder._currentAudioFile, { mode = "file", size = 1024 })
  manager:stopRecording()

  -- Everything completes synchronously in tests
  assert.equals(Manager.STATES.IDLE, manager.state)
  assert.equals(0, manager.pendingTranscriptions)

  -- Verify result in clipboard
  local clipboard = MockHS.pasteboard.getContents()
  assert.is_not_nil(clipboard)
  assert.is_true(clipboard:match("Transcribed:") ~= nil)
end)
```

##### Pattern 5: Mock File System for Validation

Always register files in mock before operations that check file existence:

```lua
it("calls onError if file not created", function()
  local errorMsg = nil

  recorder:startRecording(config, function() end, function() end)

  -- DON'T register file - simulate file not created

  recorder:stopRecording(
    function() end,
    function(err) errorMsg = err end
  )

  assert.is_not_nil(errorMsg)
  assert.equals("Recording file was not created", errorMsg)
end)
```

#### Common Pitfalls

1. **Task auto-completion**: Task completion callbacks fire during `task:start()` in tests
2. **Timer immediate execution**: `hs.timer.doAfter(0.1, fn)` calls `fn()` immediately
3. **State race conditions**: State changes happen before function returns
4. **File mock fallback**: Mock checks real filesystem if file not registered (use non-existent paths)

#### Quick Reference

| Real Behavior | Mock Behavior | Test Strategy |
|---------------|---------------|---------------|
| Timer fires after delay | Fires immediately | Test callback invocation, not timing |
| Task runs async | Completion callback fires in start() | Use explicit state flags |
| Multiple async operations | All complete synchronously | Test final state, not intermediate |
| File I/O is async | Synchronous in mock | Register files with `MockHS.fs._registerFile()` |

#### Example: SoxRecorder Testing

See `tests/spec/unit/recorders/sox_recorder_spec.lua` for comprehensive examples of all these patterns in practice.

### Testing with Real Hammerspoon (Live Integration Tests)

For testing with the actual Hammerspoon environment (not mocks), use the shell-based integration test framework.

#### Test Framework Structure

All live tests use `tests/lib/test_framework.sh` which provides:

**Helper Functions:**
- `hs_eval "lua code"` - Execute Lua in Hammerspoon (with 3s timeout)
- `hs_eval_silent "lua code"` - Execute without output
- `clear_console()` - Clear Hammerspoon console before tests
- `get_recent_console N` - Get console output from last N seconds

**Assertions:**
- `assert_command_exists cmd` - Check command is in PATH
- `assert_equals expected actual [desc]` - Compare values
- `assert_hs_running` - Verify Hammerspoon is running
- `assert_spoon_loaded` - Verify spoon is loaded
- `assert_file_exists filepath` - Check file exists

**Test Structure:**
- `test_suite "Name"` - Start a test suite
- `test_case "description"` - Declare a test case
- `pass` - Mark current test as passed
- `fail "reason"` - Mark current test as failed
- `skip "reason"` - Skip current test

#### Example: Testing SoxRecorder with Real Hammerspoon

```bash
#!/bin/bash
set -e
cd "$(dirname "$0")/.."
source tests/lib/test_framework.sh

test_suite "SoxRecorder Integration"

# Prerequisites
test_case "Hammerspoon is running"
assert_hs_running && pass

test_case "sox command is available"
assert_command_exists sox && pass

# Configuration - assumes spoon is loaded with new architecture
test_case "can create SoxRecorder"
hs_eval_silent "
  package.path = package.path .. ';/path/to/spoon/?.lua'
  SoxRecorder = dofile('/path/to/spoon/recorders/sox_recorder.lua')
  recorder = SoxRecorder.new({soxCmd = '/opt/homebrew/bin/sox'})
"
IS_CREATED=$(hs_eval "print(recorder ~= nil)")
assert_equals "true" "$IS_CREATED" && pass

# Validation
test_case "recorder validates successfully"
VALID=$(hs_eval "local ok, err = recorder:validate(); print(tostring(ok))")
assert_equals "true" "$VALID" && pass

# Recording lifecycle - use Manager + SoxRecorder + MockTranscriber
test_case "can start recording"
hs_eval_silent "
  MockTranscriber = dofile('/path/to/spoon/tests/mocks/mock_transcriber.lua')
  Manager = dofile('/path/to/spoon/core_v2/manager.lua')
  manager = Manager.new(recorder, MockTranscriber.new(), {language='en', tempDir='/tmp/test'})
  manager:startRecording('en')
"
sleep 1  # Allow recording to start

IS_RECORDING=$(hs_eval "print(tostring(recorder:isRecording()))")
assert_equals "true" "$IS_RECORDING" && pass

test_case "recording stays active"
sleep 2  # Record for 2 seconds
IS_RECORDING=$(hs_eval "print(tostring(recorder:isRecording()))")
assert_equals "true" "$IS_RECORDING" && pass

test_case "can stop recording"
hs_eval_silent "manager:stopRecording()"
sleep 1  # Allow stop to complete
IS_RECORDING=$(hs_eval "print(tostring(recorder:isRecording()))")
assert_equals "false" "$IS_RECORDING" && pass

# Verify results
test_case "audio file was created"
AUDIO_FILE=$(find /tmp/test -name "en-*.wav" -mmin -1 2>/dev/null | head -1)
assert_not_equals "" "$AUDIO_FILE" && pass

test_case "audio file is valid WAV"
file "$AUDIO_FILE" | grep -q "WAVE audio" && pass

test_case "no errors in console"
CONSOLE=$(get_recent_console 60)
ERROR_COUNT=$(echo "$CONSOLE" | grep -E "\[ERROR\]" | wc -l | tr -d ' ')
[ "$ERROR_COUNT" -eq 0 ] && pass

# Cleanup
rm -f "$AUDIO_FILE"

test_summary
exit $?
```

#### Key Patterns for Live Tests

1. **Always use timeouts**: `timeout 3 hs -c "..."` (hs_eval does this automatically)

2. **Use sleep between operations**: Allow async operations to complete
   ```bash
   hs_eval_silent "manager:startRecording('en')"
   sleep 1  # Wait for recording to start
   IS_RECORDING=$(hs_eval "print(tostring(recorder:isRecording()))")
   ```

3. **Check Hammerspoon console for errors**:
   ```bash
   CONSOLE=$(get_recent_console 60)
   ERROR_COUNT=$(echo "$CONSOLE" | grep -E "\[ERROR\]" | wc -l)
   ```

4. **Verify files on disk**:
   ```bash
   AUDIO_FILE=$(find /tmp/test -name "en-*.wav" -mmin -1 | head -1)
   assert_not_equals "" "$AUDIO_FILE"
   ```

5. **Extract complex return values**:
   ```bash
   # Get both success and error from option-style return
   RESULT=$(hs_eval "local ok, err = recorder:validate(); print(tostring(ok) .. '|' .. tostring(err or ''))")
   SUCCESS=$(echo "$RESULT" | cut -d'|' -f1)
   ERROR=$(echo "$RESULT" | cut -d'|' -f2)
   ```

6. **Test lifecycle explicitly**:
   - Prerequisites (Hammerspoon running, commands available)
   - Configuration (load components, validate)
   - Lifecycle (start → verify active → wait → stop → verify inactive)
   - Results (files created, state correct, no errors)
   - Cleanup (remove test files)

#### Running Live Tests

```bash
# Single test
./tests/test_sox_integration.sh

# All backend tests
./tests/test_all_backends.sh

# Via make
make test-live
```

**Important**: Live tests require:
- Hammerspoon running
- Spoon loaded (or manual component loading in test)
- Microphone access granted
- Required dependencies installed (sox, python packages, etc.)

#### When to Use Live Tests vs Unit Tests

**Unit Tests (with mocks):**
- Fast, run in CI
- Test logic and code paths
- Don't require Hammerspoon running
- Synchronous mock behavior

**Live Tests (real Hammerspoon):**
- Test actual integration with Hammerspoon APIs
- Verify real audio recording/playback
- Test with real async timing
- Validate dependencies
- Slower, manual execution

**Best Practice**: Write comprehensive unit tests first, then add focused live tests for critical flows.

### Testing with BlackHole Virtual Audio Device

**Overview**: For deterministic testing of audio recording/transcription, use BlackHole virtual audio device to route fixture audio as "microphone" input.

**Setup** (validated in Step 8a - WhisperKit/WhisperServer tests):

1. **Install BlackHole**:
   ```bash
   brew install blackhole-2ch
   ```

2. **Audio Routing Helper** (`tests/lib/audio_routing.sh`):
   - `setup_virtual_audio()` - Save current device, switch input to BlackHole
   - `teardown_virtual_audio()` - Restore original device
   - `play_fixture_to_virtual(audioFile)` - Play fixture through BlackHole output
   - **Uses SwitchAudioSource** (not osascript) for reliability

3. **Test Pattern**:
   ```bash
   #!/bin/bash
   set -e
   source tests/lib/test_framework.sh
   source tests/lib/audio_routing.sh

   # Prerequisites
   test_case "BlackHole virtual audio device is installed"
   assert_blackhole_installed && pass

   # Setup
   test_case "can setup virtual audio routing"
   setup_virtual_audio && pass

   # Configure spoon with BlackHole
   test_case "can load spoon with BlackHole device"
   timeout 10 hs -c "
     wd = hs.loadSpoon('hs_whisperDictation')
     wd.config = {
       recorder = 'sox',
       transcriber = 'whisperkit',
       sox = {
         soxCmd = '/opt/homebrew/bin/sox',
         audioInputDevice = 'BlackHole 2ch',  -- Use virtual device
         tempDir = '/tmp/test'
       }
     }
     wd:start()
   " >/dev/null 2>&1

   # Test recording
   test_case "can start recording"
   hs_eval_silent "wd:toggle()"
   sleep 0.5
   pass

   # Play fixture audio (becomes microphone input via BlackHole)
   test_case "play fixture audio through virtual device"
   FIXTURE_AUDIO="tests/fixtures/audio/complete/en-20260214-200536.wav"
   play_fixture_to_virtual "$FIXTURE_AUDIO" &
   PLAY_PID=$!
   sleep 2
   pass

   # Stop and verify
   test_case "can stop recording"
   timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
   sleep 2
   pass

   # Wait for transcription
   test_case "transcription completes"
   MAX_WAIT=60
   while [ $ELAPSED -lt $MAX_WAIT ]; do
     STATE=$(hs_eval "print(wd.manager.state)" 2>/dev/null || echo "UNKNOWN")
     [ "$STATE" = "IDLE" ] && break
     sleep 3
   done

   # Cleanup (automatic via trap in audio_routing.sh)
   teardown_virtual_audio
   ```

**Key Patterns**:

1. **Deterministic testing** - Same fixture audio produces consistent transcriptions
2. **No real microphone needed** - Tests run on headless systems
3. **Automatic cleanup** - `teardown_virtual_audio()` uses trap to restore device
4. **Graceful dependency checking**:
   ```bash
   test_case "optional dependency available"
   if ! command -v whisperkit-cli &> /dev/null; then
     skip "whisperkit-cli not installed (brew install whisperkit-cli)"
   fi
   pass
   ```

5. **IPC timeout handling for spoon loading**:
   ```bash
   # Use 10s timeout (not default 3s) for spoon loading
   timeout 10 hs -c "wd = hs.loadSpoon('hs_whisperDictation'); wd:start()" >/dev/null 2>&1

   # Use fallbacks for state transitions
   timeout 5 hs -c "wd:toggle()" >/dev/null 2>&1 || true
   sleep 2  # Give Hammerspoon time to process

   # Check state with fallback
   IS_REC=$(timeout 5 hs -c "print(tostring(wd.recorder:isRecording()))" 2>&1 || echo "false")
   ```

**See Also**:
- `tests/test_whisperkit_integration.sh` - Full example (19 tests, all passing)
- `tests/test_whisperserver_integration.sh` - Same pattern for HTTP-based transcriber
- `tests/lib/audio_routing.sh` - Audio device management helpers
- `tests/lib/test_framework.sh` - TAP-style test framework

**When to Use**:
- ✅ Testing transcribers (need real audio → real transcription)
- ✅ End-to-end integration tests (recording → transcription → clipboard)
- ✅ Multiple recording cycles (verify state machine reset)
- ❌ Unit tests (use mocks instead - faster and more focused)

## Skills

- `/reload` - Reload Hammerspoon safely (see `.claude/commands/reload.md`)
- '/use-console-for-debugging.md' - access the console output (see `.claude/commands/use-console-for-debugging.md`)

## Important Constraints

- **Git Command Restrictions** - Never use modifying git commands (git add, git commit, git reset, git push, etc.). The user will handle all git modifications. Read-only commands are allowed (git log, git diff, git show, git status).

## Lessons Learned

- 2026-02: "Done" means systematically reviewed, not "compiles and runs"
- 2026-02: **Always verify changes work before reporting success**:
  1. Make the change
  2. Reload Hammerspoon (use `/reload` skill - run in background to avoid hang)
  3. Check console/logs for errors
  4. Actually test the feature works (trigger the hotkey, open the menu, etc.)
  5. Only then report success
- 2026-02: **Hammerspoon reload hangs** - `hs -c "hs.reload()"` breaks IPC connection.
  Run in background instead: `timeout 2 hs -c "hs.reload()" &; sleep 2; timeout 2 hs -c "print('ready')"`
- 2026-02: **Never use CAPITALIZED names** for any files.
- 2026-02: **State management bugs from multiple sources of truth** - Found critical bug where `StreamingBackend._isRecording` was never set to true, making `stopRecording()` always fail. Root cause: multiple components tracking state independently. Solution: Manager pattern with single source of truth (see `ai-docs/architectural-evaluation.md`)
- 2026-02: **UI alerts scattered throughout code** - `hs.alert.show()` calls in many files makes it impossible to control messaging. Solution: UI Boundary pattern with `Notifier` having finite message types (4 categories × 4 severities = 16 types)
- 2026-02: **Manager doesn't need to know about chunks** - Chunks are a Recorder implementation detail. Manager only needs minimal tracking: pending count + results array. Simple counter is cleaner than complex chunk objects.
- 2026-02: **Testing async/callback code with synchronous mocks** - Mock's `hs.timer.doAfter()` executes immediately, causing task completion callbacks to fire during `task:start()`. Solution: Use explicit state flags (`_isRecording`) instead of checking task existence, test callback invocation rather than state after return, and expect final states in integration tests. See "Testing Async/Callback Code with Mocks" section above for detailed patterns.
- 2026-02: **Live Hammerspoon testing framework** - Use shell-based integration tests in `tests/test_*.sh` with the test framework in `tests/lib/test_framework.sh`. Key patterns: use `hs_eval()` with timeout, `sleep` between async operations, check console for errors with `get_recent_console()`, verify files on disk, test full lifecycle (start → active → stop → inactive). See "Testing with Real Hammerspoon" section for detailed examples.
- 2026-02: **Live integration tests require spoon integration** - New architecture components use relative `dofile()` paths (e.g., `dofile("recorders/i_recorder.lua")`), which only work when loaded from init.lua (correct working directory). Before Step 8 (init.lua integration), use comprehensive unit tests with mocks. After Step 8, add full shell-based integration tests through `spoon.hs_whisperDictation` interface like old architecture tests.
- 2026-02: **Step 6 validated critical testing patterns** - Manager clears results on IDLE transition (check clipboard, not results array). Two-layer testing (mocks + real audio) is essential, not optional. Three testing levels exist: unit tests, integration tests via busted, and live Hammerspoon tests. Mock test setup requires `_G.hs = MockHS` and `MockHS._resetAll()`. Fixture infrastructure with 44+ recordings is production-ready for Steps 7-10. See "Testing Patterns Validated in Step 6" section for complete details.
- 2026-02: **Manager state clearing is by design** - When Manager transitions to IDLE, it clears `results`, `pendingTranscriptions`, `recordingComplete`, etc. This is intentional for clean state resets. Always check clipboard for final output after completion, never `manager.results` (will be empty). This is NOT a bug.
- 2026-02-15: **WhisperCLI output file behavior** - whisper-cli appends `.txt` to the FULL filename including extension (e.g., `audio.wav` → `audio.wav.txt`), NOT by replacing the extension. Don't use `--output-file` parameter as it doesn't work reliably with absolute paths. Correct pattern: `whisper-cli -np -m model -l lang --output-txt audioFile` then read `audioFile .. ".txt"`. See working implementation in `transcribers/whispercli_transcriber.lua`.
- 2026-02-15: **Manager completion checking race condition** - NEVER call `_checkIfComplete()` immediately after `stopRecording()`. The recorder's chunk emission is async (via callbacks), so chunks haven't been emitted yet when stopRecording() returns. The manager will think it's complete with 0 pending transcriptions. Only call `_checkIfComplete()` in: (1) `_onRecordingComplete()` callback, (2) after transcription success/failure. This was a critical bug that caused premature completion.
- 2026-02-15: **Manager needs UI update callbacks** - Manager is isolated from UI layer (init.lua). To update menubar/status indicators when state changes, Manager needs an `onStateChanged` callback that init.lua can set. Pattern: `manager.onStateChanged = function(newState, oldState, context)` called in `transitionTo()`. This enables menubar to update on RECORDING → 🎙️, TRANSCRIBING → ⏳, IDLE → 🎤 without Manager knowing about UI details.
- 2026-02-15: **Audio device management with SwitchAudioSource** - For reliable audio device switching in tests, use `SwitchAudioSource -t input -c` to get current device and `SwitchAudioSource -s "DeviceName" -t input` to set device. The osascript approach (`tell application "System Events"...`) fails silently and doesn't work reliably. SwitchAudioSource is available via `brew install switchaudio-osx`.
- 2026-02-15: **Integration tests must restore global state** - Tests that reconfigure global objects (like `wd` spoon with test temp directories) MUST restore original configuration at the end. Otherwise, they leave the system in a broken state for actual use. Pattern: Add `hs.reload()` at end of test to restore spoon to normal configuration loaded from init.lua. The "message port was invalidated" error during reload is expected and normal.
- 2026-02-15: **E2E tests need multiple cycles** - End-to-end integration tests should run at least 2 complete recording cycles to verify: (1) state machine properly resets to IDLE, (2) menubar updates correctly on second cycle, (3) no state leaks between recordings, (4) transcription works consistently. Single-cycle tests miss reset bugs.
- 2026-02-15: **BlackHole virtual audio for deterministic testing** - Use BlackHole 2ch virtual audio device + fixture audio playback for deterministic transcription testing. Key patterns: (1) `setup_virtual_audio()` saves current device and switches to BlackHole, (2) `play_fixture_to_virtual(audioFile)` routes fixture through BlackHole output (becomes recorder input), (3) `teardown_virtual_audio()` restores original device via trap, (4) Use SwitchAudioSource (not osascript) for reliable device switching, (5) Longer timeouts for spoon loading (10s) and state transitions (5s with `|| true` fallback). See `tests/test_whisperkit_integration.sh` (19 tests) and `tests/lib/audio_routing.sh` for complete implementation. This enables testing transcribers without real microphone input and produces consistent results.
