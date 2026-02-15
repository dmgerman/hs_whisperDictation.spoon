# Testing Infrastructure

The spoon has a comprehensive test suite using [Busted](https://olivinelabs.com/busted/) 2.3.0+ with 255+ tests covering all core components.

## Directory Structure

```
tests/
├── spec/                      # Test specifications
│   ├── sanity_spec.lua       # Basic sanity checks
│   ├── unit/                 # Unit tests
│   │   ├── core/            # Core component tests
│   │   ├── backends/        # Recording backend tests
│   │   ├── methods/         # Transcription method tests
│   │   └── lib/             # Library tests
│   └── integration/          # Integration tests
└── helpers/                  # Test utilities
    ├── mock_hs.lua          # Hammerspoon API mocks
    ├── async_helper.lua     # Promise/async utilities
    ├── fixtures.lua         # Test fixtures
    ├── server_manager.lua   # Test server management
    └── generate_transcripts.lua
```

## Running Tests

### Using Make (Recommended)

```bash
# Run all tests (Lua + Python, ~408 tests total)
# Uses mocks - doesn't require Hammerspoon running
make test

# Run only Python tests
make test-python

# Run live integration tests with real Hammerspoon (3 tests)
# Automatically verifies environment, reloads Hammerspoon, runs backend tests
make test-live

# Clean temporary files
make clean

# Show help
make help
```

**`make test`** (default):
- Runs all tests: 368 Lua tests + 69 Python tests = 437 total
- Lua tests: busted with mocks
- Python tests: pytest with mocks (includes file integration tests)
- Doesn't require Hammerspoon running
- Quiet mode - only shows failures
- Fast (~30-45 seconds)

**`make test-live`**:
- [1/3] Verifies environment (dependencies, configuration) - fails fast if environment issues
- [2/3] Reloads Hammerspoon to load current code
- [3/3] Runs all backend tests:
  - ✓ Sox recording backend
  - ✓ Pythonstream recording backend
  - ✓ WhisperKit transcription
  - ✓ Whisper CLI transcription
  - ✓ Whisper Server transcription
- Requires: Hammerspoon running, spoon loaded, microphone access
- Production-quality tests with proper assertions and TAP-style output
- Tests actual recording, transcription, file validation, error checking

### Using Busted Directly

You can also run busted directly (from spoon root directory):

**All tests:**
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
busted tests/spec/unit/lib/promise_spec.lua
```

**Verbose output:**
```bash
busted --verbose
```

## Test Categories

- **Lua Unit Tests** (`tests/spec/unit/`): Test individual Lua components in isolation using mocks (327 tests)
- **Lua Integration Tests** (`tests/spec/integration/`): Test interactions between Lua components using mocks (38 tests)
- **Python Unit Tests** (`tests/python/`): Test whisper_stream.py Python script (69 tests)
  - `test_audio_processing.py` - Audio normalization, silence detection, format conversion
  - `test_tcp_server.py` - TCP server communication and connection handling
  - `test_event_output.py` - JSON event output functions
  - `test_dependencies.py` - Dependency checking
  - `test_continuous_recorder.py` - VAD, chunk detection, recording lifecycle
  - `test_file_integration.py` - **File input integration tests** - Tests full pipeline with real audio files
    - Uses `--test-file` mode to inject pre-recorded WAV files instead of microphone
    - Validates VAD, chunking, silence detection, and event emission with known audio
    - See [docs/file_input_testing.md](docs/file_input_testing.md) for details
- **Live Integration Tests** (`tests/test_*.sh`): Production-quality shell tests with proper assertions
  - **Recording Backends:**
    - `test_sox_integration.sh` - Sox backend (13 test cases)
    - `test_pythonstream_integration.sh` - Pythonstream backend with VAD (16 test cases)
  - **Transcription Methods:**
    - `test_transcription_whisperkit.sh` - WhisperKit CLI transcription
    - `test_transcription_whispercli.sh` - Whisper CLI transcription
    - `test_transcription_whisperserver.sh` - Whisper server transcription
  - **Master Test:** `test_all_backends.sh` - Runs all backend tests with summary
  - Uses `tests/lib/test_framework.sh` - TAP-style test framework with assertions
- **Environment Verification** (`tests/verify_environment.sh`): Comprehensive dependency and configuration checks
- **E2E Tests** (`tests/spec/e2e/`): End-to-end tests (directory exists but not yet implemented)

## Writing Tests

### Basic Test Structure

```lua
--- My Component Unit Tests

describe("MyComponent", function()
  local MyComponent
  local component

  before_each(function()
    MyComponent = require("core.my_component")
    component = MyComponent.new()
  end)

  after_each(function()
    component = nil
  end)

  describe("methodName()", function()
    it("should do something", function()
      local result = component:methodName()
      assert.is_not_nil(result)
      assert.equals("expected", result)
    end)

    it("should handle errors", function()
      assert.has_error(function()
        component:methodName(nil)
      end)
    end)
  end)
end)
```

### Testing with Hammerspoon Mocks

```lua
local mock_hs = require("tests.helpers.mock_hs")

describe("Component using hs APIs", function()
  before_each(function()
    _G.hs = mock_hs  -- Replace global hs with mocks
  end)

  after_each(function()
    mock_hs._resetAll()  -- Reset mock state
    _G.hs = nil
  end)

  it("should show alert", function()
    hs.alert.show("test message")
    local alerts = hs.alert._getAlerts()
    assert.equals(1, #alerts)
    assert.equals("test message", alerts[1].message)
  end)
end)
```

### Testing Promises/Async Code

```lua
local AsyncHelper = require("tests.helpers.async_helper")

describe("Async operations", function()
  it("should resolve promise", function()
    local promise = MyComponent:asyncMethod()

    AsyncHelper.waitFor(promise, function(result)
      assert.equals("expected", result)
    end)
  end)

  it("should reject promise on error", function()
    local promise = MyComponent:failingMethod()

    assert.has_error(function()
      AsyncHelper.waitFor(promise)
    end)
  end)
end)
```

### Testing EventBus Events

```lua
local EventBus = require("lib.event_bus")

describe("Event emission", function()
  local bus

  before_each(function()
    bus = EventBus.new()
  end)

  it("should emit event with data", function()
    local received = nil

    bus:on("test-event", function(data)
      received = data
    end)

    bus:emit("test-event", {value = "test"})

    assert.is_not_nil(received)
    assert.equals("test", received.value)
  end)
end)
```

## Test Helpers

### `mock_hs.lua`
Mocks for Hammerspoon APIs:
- `hs.alert`, `hs.pasteboard`, `hs.task`, `hs.timer`, `hs.fs`
- Call `mock_hs._resetAll()` in `after_each()` to reset state

### `async_helper.lua`
Promise testing utilities:
- `AsyncHelper.waitFor(promise, assertions)` - Wait for promise resolution
- `AsyncHelper.resolved(value)` - Create resolved promise
- `AsyncHelper.rejected(reason)` - Create rejected promise

### `fixtures.lua`
Test data and fixtures:
- Common test audio files, transcripts, configurations

### `server_manager.lua`
Integration test server management:
- Start/stop test servers for integration tests

## Test Configuration

The `.busted` file configures test patterns and output:
- Default output: TAP (Test Anything Protocol)
- Pattern matching: `*_spec.lua`
- Separate configurations for unit/integration/e2e tests

## Best Practices

1. **Always update tests when modifying source code**
2. **Run tests before declaring work complete**
3. **Use mocks for Hammerspoon APIs** - Don't require Hammerspoon to be running
4. **Test both success and error paths**
5. **Keep tests focused** - One assertion per test when possible
6. **Use descriptive test names** - "should do X when Y"
7. **Clean up in after_each()** - Reset mocks and state
8. **Test public APIs, not implementation details**
9. **For async code, use AsyncHelper.waitFor()**
10. **Verify no regressions** - All tests must pass

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
assert.has_no_error(function() code() end)

-- Type checking
assert.is_table(value)
assert.is_string(value)
assert.is_number(value)
assert.is_function(value)
```

## Workflow

When modifying source code:

1. **Update or write tests first** (TDD approach)
2. **Make the code changes**
3. **Run the full test suite**: `busted`
4. **Verify all tests pass**
5. **Check for regressions**
6. **Only then declare work complete**

**CRITICAL**: Never skip running tests after code changes!
