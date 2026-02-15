# WhisperDictation Test Suite

## Overview

Fully automatic test suite with **real audio fixtures** from actual usage.

## Quick Start

### 1. Install Testing Tools

```bash
# Install Lua and testing framework
brew install lua luarocks
luarocks install busted
luarocks install luassert
luarocks install luacov
```

### 2. Set Up Test Fixtures

```bash
# Copy real audio files from /tmp/whisper_dict
cd /Users/dmg/.hammerspoon/Spoons/hs_whisperDictation.spoon
./tests/setup_fixtures.sh
```

This will copy:
- 3 audio chunks (short, medium, long)
- 36 complete audio recordings
- 60 transcripts

### 3. Run Tests

```bash
# Run all tests
busted

# Run specific test suite
busted tests/spec/unit
busted tests/spec/integration

# Run with coverage
busted --coverage

# Run in watch mode (continuous testing)
busted --watch
```

---

## Test Structure

```
tests/
├── spec/
│   ├── unit/              # Isolated component tests
│   ├── integration/       # Component interaction tests
│   └── e2e/              # Full workflow tests
├── fixtures/              # Real audio & transcript data
│   ├── audio/
│   │   ├── chunks/       # Short audio clips for fast tests
│   │   └── complete/     # Full recordings with transcripts
│   └── transcripts/      # Expected transcription outputs
├── helpers/
│   ├── mock_hs.lua       # Mock Hammerspoon APIs
│   ├── fixtures.lua      # Fixture loading utilities
│   └── async_helpers.lua # Async test utilities
└── setup_fixtures.sh     # Fixture setup script
```

---

## Using Test Fixtures

### Load Audio Chunks

```lua
local Fixtures = require("tests.helpers.fixtures")

-- Get audio chunk for testing
local shortAudio = Fixtures.getAudioChunk("short")   -- ~1 second
local mediumAudio = Fixtures.getAudioChunk("medium") -- ~3 seconds
local longAudio = Fixtures.getAudioChunk("long")     -- ~5+ seconds
```

### Load Complete Recordings

```lua
-- Get all recordings with transcripts
local recordings = Fixtures.getCompleteRecordings()

for _, recording in ipairs(recordings) do
  print("Audio:", recording.audio)
  print("Transcript:", recording.transcript)
  print("Basename:", recording.basename)
end

-- Get random recording (for fuzz testing)
local random = Fixtures.getRandomRecording()
```

### Compare Transcripts

```lua
-- Handle extra line feeds and whitespace
local actual = "This is a test.\n\n\nWith extra LFs."
local expected = "This is a test. With extra LFs."

local match, similarity = Fixtures.compareTranscripts(actual, expected)

if match then
  print(string.format("Match! (%.0f%% similar)", similarity * 100))
else
  print(string.format("No match (%.0f%% similar)", similarity * 100))
end
```

---

## Example Test

```lua
-- tests/spec/unit/core/recording_manager_spec.lua
local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS  -- Replace hs.* with mocks

local RecordingManager = require("core.recording_manager")
local EventBus = require("lib.event_bus")

describe("RecordingManager", function()
  local manager, eventBus, backend

  before_each(function()
    MockHS._resetAll()  -- Reset mocks

    eventBus = EventBus.new()
    backend = createMockBackend()

    manager = RecordingManager.new(backend, eventBus, {
      tempDir = "/tmp/test"
    })
  end)

  it("starts recording", function()
    manager:startRecording("en")
    assert.equals("recording", manager.state)
  end)

  it("emits events", function()
    local eventFired = false
    eventBus:on("recording:started", function()
      eventFired = true
    end)

    manager:startRecording("en")
    assert.is_true(eventFired)
  end)
end)
```

---

## Mock Hammerspoon APIs

All `hs.*` APIs are mocked for testing. No need for Hammerspoon to be running!

```lua
local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS

-- Now use hs.* as normal in tests
hs.alert.show("Test alert")
hs.pasteboard.setContents("Test")

-- Verify mock behavior
local alerts = MockHS.alert._getAlerts()
assert.equals(1, #alerts)
assert.equals("Test alert", alerts[1].message)

local clipboard = MockHS.pasteboard.getContents()
assert.equals("Test", clipboard)
```

### Available Mocks

- `hs.task` - Process execution
- `hs.timer` - Timers and delays
- `hs.alert` - Alerts (recorded for assertions)
- `hs.menubar` - Menubar
- `hs.pasteboard` - Clipboard
- `hs.fs` - Filesystem (in-memory)
- `hs.socket` - TCP sockets
- `hs.drawing` - On-screen drawing
- `hs.eventtap` - Keyboard/mouse events
- `hs.hotkey` - Hotkeys
- `hs.chooser` - UI chooser
- `hs.json` - JSON encoding/decoding

---

## Test Fixtures Details

### Current Fixtures

**Audio Chunks (for fast unit tests):**
- `chunk_short.wav` - ~250KB, ~1 second
- `chunk_medium.wav` - ~140KB, ~3 seconds
- `chunk_long.wav` - ~94KB, ~5 seconds

**Complete Recordings (for integration tests):**
- 36 full recordings with matching transcripts
- Real-world audio from actual usage
- Includes various lengths and content

### Updating Fixtures

When you record new audio with WhisperDictation:

```bash
# Re-run fixture setup to get latest recordings
./tests/setup_fixtures.sh
```

This will copy any new recordings from `/tmp/whisper_dict`.

---

## Continuous Integration

### GitHub Actions

Tests run automatically on every push/PR:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Dependencies
        run: |
          brew install lua luarocks
          luarocks install busted luassert luacov
      - name: Run Tests
        run: busted
      - name: Upload Coverage
        uses: codecov/codecov-action@v3
```

### Pre-commit Hook

Tests run automatically before each commit:

```bash
# Install pre-commit hook
cp tests/pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Coverage Reports

```bash
# Generate coverage report
busted --coverage
luacov

# View report
cat luacov.report.out

# Check coverage threshold
grep "Total" luacov.report.out
```

**Target Coverage:** 80%+

---

## Troubleshooting

### "Fixture manifest not found"

```bash
# Run fixture setup
./tests/setup_fixtures.sh
```

### "Module not found"

```bash
# Ensure you're in the correct directory
cd /Users/dmg/.hammerspoon/Spoons/hs_whisperDictation.spoon

# Verify Lua path
lua -e "print(package.path)"
```

### "No recordings available"

```bash
# Check if /tmp/whisper_dict has audio files
ls -l /tmp/whisper_dict/*.wav

# If empty, record some audio first using the spoon
# Then run: ./tests/setup_fixtures.sh
```

---

## Next Steps

1. **Phase 0**: ✅ Test infrastructure set up
2. **Phase 1**: Write unit tests for lib/ components
3. **Phase 2**: Write unit tests for core/ components
4. **Phase 3**: Write integration tests
5. **Phase 4**: Write E2E tests with real audio
6. **Phase 5**: Achieve 80%+ coverage
7. **Phase 6**: Set up CI/CD

---

## Resources

- [Busted Documentation](https://lunarmodules.github.io/busted/)
- [LuaAssert Reference](https://lunarmodules.github.io/luassert/)
- [LuaCov Coverage Tool](https://keplerproject.github.io/luacov/)
