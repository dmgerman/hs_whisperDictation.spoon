# Testing Infrastructure

The spoon has a comprehensive test suite using [Busted](https://olivinelabs.com/busted/) 2.3.0+ with **408+ tests** covering all core components.

## Directory Structure

```
tests/
├── spec/                      # Test specifications
│   ├── sanity_spec.lua       # Basic sanity checks
│   ├── unit/                 # Unit tests
│   │   ├── core/            # Manager tests
│   │   ├── recorders/       # Recorder tests (sox, streaming)
│   │   ├── transcribers/    # Transcriber tests (whisperkit, whispercli, whisperserver)
│   │   ├── mocks/           # Mock component tests
│   │   └── lib/             # Library tests (notifier)
│   └── integration/          # Integration tests
│       ├── new_architecture_*.lua  # Current architecture integration tests
│       └── init_fallback_spec.lua  # Fallback chain tests
├── python/                    # Python tests
│   ├── test_audio_processing.py
│   ├── test_continuous_recorder.py
│   ├── test_tcp_server.py
│   └── ...
├── helpers/                  # Test utilities
│   ├── mock_hs.lua          # Hammerspoon API mocks
│   ├── fixtures.lua         # Test fixtures (44+ audio files with transcripts)
│   ├── server_manager.lua   # Test server management
│   └── load_new_architecture.lua
├── mocks/                    # Mock components
│   ├── mock_recorder.lua    # Mock IRecorder implementation
│   └── mock_transcriber.lua # Mock ITranscriber implementation
├── lib/                      # Test framework
│   ├── test_framework.sh    # TAP-style shell test framework
│   └── audio_routing.sh     # BlackHole virtual audio helpers
├── test_*.sh                 # Live Hammerspoon integration tests
└── verify_environment.sh     # Dependency checking
```

## Running Tests

### Using Make (Recommended)

```bash
# Run all tests (Lua + Python, ~408 tests total)
# Uses mocks - doesn't require Hammerspoon running
make test

# Run only Python tests (40 tests)
make test-python

# Run live integration tests with real Hammerspoon
# Automatically verifies environment, reloads Hammerspoon, runs backend tests
make test-live

# Clean temporary files
make clean

# Show help
make help
```

**`make test`** (default):
- Runs all tests: 368 Lua tests + 40 Python tests = 408 total
- Lua tests: busted with mocks
- Python tests: pytest with mocks
- Doesn't require Hammerspoon running
- Quiet mode - only shows failures
- Fast (~30-45 seconds)

**`make test-live`**:
- Tests with actual Hammerspoon process running
- Uses BlackHole virtual audio for deterministic testing
- Tests: sox, streaming, whisperkit, whispercli, whisperserver
- Requires: Hammerspoon running, spoon loaded, microphone access
- Production-quality tests with proper assertions

### Using Busted Directly

You can also run busted directly (from spoon root directory):

**All Lua tests:**
```bash
busted
```

**Unit tests only:**
```bash
busted tests/spec/unit/
```

**Integration tests only:**
```bash
busted tests/spec/integration/
```

**Specific test file:**
```bash
busted tests/spec/unit/core/manager_spec.lua
```

**Verbose output:**
```bash
busted --verbose
```

### Using Pytest Directly

**All Python tests:**
```bash
pytest tests/python/
```

**Specific test file:**
```bash
pytest tests/python/test_continuous_recorder.py -v
```

## Test Categories

### Lua Unit Tests (tests/spec/unit/)
Tests individual Lua components in isolation using mocks.

**Core:**
- `core/manager_spec.lua` - Manager state machine, callbacks, coordination

**Recorders:**
- `recorders/sox_recorder_spec.lua` - Sox recorder implementation
- `recorders/streaming_recorder_spec.lua` - Streaming recorder with Python server
- `recorders/i_recorder_spec.lua` - IRecorder interface

**Transcribers:**
- `transcribers/whisperkit_transcriber_spec.lua` - WhisperKit implementation
- `transcribers/whispercli_transcriber_spec.lua` - WhisperCLI implementation
- `transcribers/whisperserver_transcriber_spec.lua` - WhisperServer implementation
- `transcribers/i_transcriber_spec.lua` - ITranscriber interface

**Mocks:**
- `mocks/mock_recorder_spec.lua` - Mock recorder for testing Manager
- `mocks/mock_transcriber_spec.lua` - Mock transcriber for testing Manager

**Library:**
- `lib/notifier_spec.lua` - UI boundary pattern

### Lua Integration Tests (tests/spec/integration/)
Tests interactions between components using mocks.

- `new_architecture_init_spec.lua` - Init.lua integration with Manager
- `new_architecture_real_audio_spec.lua` - Real audio file testing
- `new_architecture_streaming_spec.lua` - StreamingRecorder integration
- `new_architecture_transcribers_spec.lua` - All transcribers integration
- `init_fallback_spec.lua` - Validation and fallback chains

**Two-Layer Strategy:**
1. **Mock layer** - Fast, deterministic, tests logic
2. **Real audio layer** - Validates with actual audio files from fixtures

### Python Unit Tests (tests/python/)
Tests whisper_stream.py Python script (40 tests).

- `test_audio_processing.py` - Audio normalization, silence detection, format conversion
- `test_tcp_server.py` - TCP server communication and connection handling
- `test_event_output.py` - JSON event output functions
- `test_dependencies.py` - Dependency checking
- `test_continuous_recorder.py` - VAD, chunk detection, recording lifecycle
- `test_file_integration.py` - File input integration tests (uses `--test-file` mode)
- `test_silence_detection.py` - Silence detection edge cases
- `test_microphone_failure.py` - Microphone error handling

### Live Integration Tests (tests/test_*.sh)
Production-quality shell tests with real Hammerspoon process.

**New Architecture Tests:**
- `test_new_architecture_e2e.sh` - End-to-end test (2 recording cycles)
- `test_streaming_recorder_integration.sh` - StreamingRecorder with Manager (26 tests)
- `test_streaming_simple.sh` - Quick StreamingRecorder smoke test (13 tests)

**Component Tests:**
- `test_whisperkit_integration.sh` - WhisperKit with BlackHole audio (19 tests)
- `test_whisperserver_integration.sh` - WhisperServer integration

**Old Architecture Tests (still working):**
- `test_sox_integration.sh` - Sox backend (13 tests)
- `test_pythonstream_integration.sh` - Pythonstream backend (16 tests)
- `test_all_backends.sh` - Master test runner

**Uses:**
- `tests/lib/test_framework.sh` - TAP-style test framework
- `tests/lib/audio_routing.sh` - BlackHole virtual audio routing

## Writing Tests

### Basic Test Structure

```lua
--- My Component Unit Tests

describe("MyComponent", function()
  local MyComponent
  local MockHS
  local component

  before_each(function()
    -- Load mock Hammerspoon APIs
    MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    MyComponent = require("core.my_component")
    component = MyComponent.new()
  end)

  after_each(function()
    MockHS._resetAll()
    component = nil
    _G.hs = nil
  end)

  describe("methodName()", function()
    it("should do something", function()
      local result = component:methodName()
      assert.is_not_nil(result)
      assert.equals("expected", result)
    end)

    it("should handle errors", function()
      local success, err = component:methodName(nil)
      assert.is_false(success)
      assert.is_string(err)
    end)
  end)
end)
```

### Testing with Hammerspoon Mocks

```lua
local MockHS = require("tests.helpers.mock_hs")

describe("Component using hs APIs", function()
  before_each(function()
    _G.hs = MockHS  -- Replace global hs with mocks
  end)

  after_each(function()
    MockHS._resetAll()  -- Reset mock state
    _G.hs = nil
  end)

  it("should show alert", function()
    hs.alert.show("test message")
    local alerts = MockHS.alert._getAlerts()
    assert.equals(1, #alerts)
    assert.equals("test message", alerts[1].message)
  end)

  it("should register files in mock filesystem", function()
    MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })
    local attrs = hs.fs.attributes("/tmp/test.wav")
    assert.is_not_nil(attrs)
    assert.equals(1024, attrs.size)
  end)
end)
```

### Testing Callbacks

```lua
describe("Async operations with callbacks", function()
  it("should call onSuccess callback", function()
    local result = nil

    recorder:startRecording(config,
      function(audioFile, chunkNum, isFinal)
        result = { audioFile = audioFile, chunkNum = chunkNum }
      end,
      function() end
    )

    -- In tests, callbacks fire synchronously via mocks
    assert.is_not_nil(result)
    assert.equals(1, result.chunkNum)
  end)

  it("should call onError callback on failure", function()
    local errorMsg = nil

    transcriber:transcribe("/nonexistent.wav", "en",
      function() end,
      function(err) errorMsg = err end
    )

    assert.is_not_nil(errorMsg)
  end)
end)
```

### Testing with Real Audio Fixtures

```lua
local Fixtures = require("tests.helpers.fixtures")

describe("Real audio transcription", function()
  it("should transcribe real audio file", function()
    local recordings = Fixtures.getCompleteRecordings()
    local recording = recordings[1]

    local actualText = nil
    transcriber:transcribe(recording.audio, "en",
      function(text) actualText = text end,
      function() end
    )

    local expectedText = Fixtures.readTranscript(recording.transcript)
    local match, similarity = Fixtures.compareTranscripts(
      actualText,
      expectedText,
      0.85  -- 85% tolerance for model variations
    )

    assert.is_true(match, "Similarity: " .. similarity)
  end)
end)
```

## Test Helpers

### `mock_hs.lua`
Mocks for Hammerspoon APIs:
- `hs.alert`, `hs.pasteboard`, `hs.task`, `hs.timer`, `hs.fs`, `hs.socket`
- **Critical:** Executes async operations synchronously for testing
- Call `MockHS._resetAll()` in `after_each()` to reset state
- Use `MockHS.fs._registerFile(path, attrs)` to mock filesystem

### `fixtures.lua`
Test data and fixtures:
- 44+ real audio recordings with matching transcripts
- `Fixtures.getCompleteRecordings()` - Get all recordings
- `Fixtures.compareTranscripts(actual, expected, tolerance)` - Smart comparison
- `Fixtures.normalizeTranscript(text)` - Normalize whitespace

### `server_manager.lua`
Integration test server management:
- Start/stop test servers for integration tests
- Port management to avoid conflicts

### `load_new_architecture.lua`
Helper to load new architecture components with correct paths.

## Mock Behavior (CRITICAL)

The mock infrastructure executes all async operations **synchronously**:

```lua
-- In mock_hs.lua, timers fire immediately
hs.timer.doAfter(delay, fn)  -- Calls fn() immediately

-- Task completion callbacks fire during task:start()
task:start()  -- Completion callback already fired when this returns
```

**This means:**
- Timer callbacks fire immediately, not after delay
- Task completion callbacks fire during `task:start()`
- All async chains complete before function returns

**Test Strategy:**
- Test callback invocation, not timing
- Use explicit state flags (`_isRecording`), not object existence
- Expect final state in integration tests, not intermediate
- Register mock files before operations that check file existence

## Best Practices

1. **Always update tests when modifying source code** (TDD approach)
2. **Run full test suite before declaring work complete:** `make test`
3. **Use mocks for Hammerspoon APIs** - Don't require Hammerspoon running
4. **Test both success and error paths**
5. **Keep tests focused** - One assertion per test when possible
6. **Use descriptive test names** - "should do X when Y"
7. **Clean up in after_each()** - Reset mocks and state
8. **Test public APIs, not implementation details**
9. **For Manager integration, check clipboard not results array** (results cleared on IDLE)
10. **Verify no regressions** - All 408+ tests must pass

## Common Assertions

```lua
-- Equality
assert.equals(expected, actual)
assert.same(expected_table, actual_table)  -- Deep equality

-- Truthiness
assert.is_true(value)
assert.is_false(value)
assert.is_nil(value)
assert.is_not_nil(value)

-- Errors
assert.has_error(function() code() end)
assert.has_no_errors(function() code() end)

-- Type checking
assert.is_table(value)
assert.is_string(value)
assert.is_number(value)
assert.is_function(value)
assert.is_boolean(value)

-- Option-style returns
local success, err = component:validate()
assert.is_true(success)
assert.is_nil(err)
```

## Testing Patterns

### Pattern 1: Test Callback Invocation

```lua
it("emits chunk via callback", function()
  local chunkReceived = nil

  recorder:startRecording(config,
    function(audioFile, chunkNum, isFinal)
      chunkReceived = { audioFile = audioFile, chunkNum = chunkNum }
    end,
    function() end
  )

  -- Callback fired synchronously in tests
  assert.is_not_nil(chunkReceived)
  assert.equals(1, chunkReceived.chunkNum)
end)
```

### Pattern 2: Use Explicit State Flags

```lua
function Recorder:isRecording()
  return self._isRecording  -- Use flag, not task existence
end
```

### Pattern 3: Test "Already Active" by Setting State Directly

```lua
it("rejects if already recording", function()
  recorder._isRecording = true  -- Simulate in progress

  local success, err = recorder:startRecording(config, onChunk, onError)

  assert.is_false(success)
  assert.equals("Already recording", err)

  recorder._isRecording = false  -- Cleanup
end)
```

### Pattern 4: Integration Tests - Expect Completion

```lua
it("completes full recording cycle", function()
  manager:startRecording("en")
  MockHS.fs._registerFile(recorder._currentAudioFile, { mode = "file", size = 1024 })
  manager:stopRecording()

  -- Everything completes synchronously in tests
  assert.equals(Manager.STATES.IDLE, manager.state)

  -- Check clipboard for results (not manager.results - cleared on IDLE)
  local clipboard = MockHS.pasteboard.getContents()
  assert.is_not_nil(clipboard)
end)
```

### Pattern 5: Mock Filesystem for Validation

```lua
it("validates file exists", function()
  -- Register file in mock before validation
  MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

  local attrs = hs.fs.attributes("/tmp/test.wav")
  assert.is_not_nil(attrs)
  assert.equals("file", attrs.mode)
end)
```

## Workflow

When modifying source code:

1. **Update or write tests first** (TDD approach)
2. **Make the code changes**
3. **Run the full test suite**: `make test`
4. **Verify all 408+ tests pass**
5. **Check for regressions**
6. **Run live tests if touching recorder/transcriber**: `make test-live`
7. **Only then declare work complete**

**CRITICAL**: Never skip running tests after code changes!

## Test Configuration

### `.busted`
Configures busted test patterns and output:
- Default output: TAP (Test Anything Protocol)
- Pattern matching: `*_spec.lua`
- Excludes: Python tests, shell scripts

### `pytest.ini`
Configures pytest for Python tests:
- Test discovery: `tests/python/`
- Pattern: `test_*.py`

## Troubleshooting

**"Cannot find module"**: Make sure you're running from spoon root directory

**"Mock not resetting"**: Call `MockHS._resetAll()` in `after_each()`

**"Async test fails"**: Remember mocks execute synchronously - test final state

**"File not found in mock"**: Register files with `MockHS.fs._registerFile()` before use

**Live tests hang**: Use timeouts (`timeout 5 hs -c "..."`) and fire-and-forget pattern

---

**For architecture details, see:** `docs/architecture.md`
**For BlackHole audio testing, see:** `tests/lib/audio_routing.sh`
