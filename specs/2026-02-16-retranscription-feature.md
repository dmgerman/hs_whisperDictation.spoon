# Chore: Add Retranscription Feature

## Chore Description

Add retranscription feature from v1.x architecture (commit 62af849) to the new v2 callback-based architecture. This feature allows users to re-transcribe previously recorded audio files using a different transcriber or to retry transcription when the original attempt failed.

**Key Features:**
- Show chooser with recent recordings (formatted dates, file sizes)
- Use configurable transcriber (or current if not specified)
- Extract language from filename (e.g., `en-20260124-175724.wav` → "en")
- Support callback parameter for custom handling
- Support auto-paste if same app as when chooser opened (new in v2)
- Bind to `retranscribe` hotkey

**Configuration:**
- `obj.retranscribeTranscriber = nil` - Transcriber to use (nil = use current)
- `obj.retranscribeCount = 10` - Number of recent recordings to show

## Relevant Files

**Existing Files to Modify:**

- **`init.lua`** (main spoon file)
  - Add configuration properties: `retranscribeTranscriber`, `retranscribeCount`
  - Add helper function: `getRecentRecordings(n)` - scan tempDir for recent .wav files
  - Add helper function: `showRetranscribeChooser(callback)` - display hs.chooser with files
  - Add helper function: `retranscribe(audioFile, lang, callback)` - perform retranscription
  - Add public API: `obj:transcribeLatestAgain(callback)` - entry point
  - Add `retranscribe` hotkey binding in `bindHotKeys()`
  - Track starting app for auto-paste functionality

- **`README.org`** (user documentation)
  - Add retranscription feature documentation
  - Document configuration options
  - Add usage examples
  - Document hotkey binding

- **`docs/architecture.md`** (technical documentation)
  - Document retranscription feature in architecture
  - Explain transcriber selection logic
  - Document auto-paste behavior

### New Files

- **`tests/spec/unit/retranscription_spec.lua`** (unit tests)
  - Test `getRecentRecordings()` - file scanning and sorting
  - Test filename parsing (language extraction)
  - Test chooser entry formatting
  - Test auto-paste app tracking

- **`tests/spec/integration/retranscription_integration_spec.lua`** (integration tests)
  - Test full retranscription flow with mock transcriber
  - Test with real audio files from fixtures
  - Test callback invocation
  - Test auto-paste vs clipboard behavior
  - Test with different transcribers

## Step by Step Tasks

### Step 1: Add Configuration Properties

- Add `obj.retranscribeTranscriber = nil` to configuration section in `init.lua`
  - Document: nil = use current transcriber, or specify transcriber name
  - Validate it matches one of: "whisperkit", "whispercli", "whisperserver"
- Add `obj.retranscribeCount = 10` to configuration section
  - Document: number of recent recordings to show in chooser
- Add internal state variable to track app where chooser was opened
  - `obj.retranscribeStartingApp = nil`

### Step 2: Implement getRecentRecordings() Helper

- Create `local function getRecentRecordings(n)` in `init.lua`
  - Scan `obj.tempDir` for .wav files using `hs.fs.dir()`
  - Collect file info: path, filename, modification time, size
  - Sort by modification time (newest first)
  - Return array of top N recordings: `{path, filename, modified, size}`
  - Handle empty directory case: return empty array `{}`
  - Handle permission errors gracefully: return empty array `{}` and log error

### Step 3: Implement Filename Parsing and Formatting

- Create `local function parseFilename(filename)` helper
  - Parse pattern: `{lang}-{YYYYMMDD}-{HHMMSS}.wav`
  - Extract language, date components, time components
  - Return: `{lang, year, month, day, hour, min, sec}` or nil if parse fails
- Create `local function formatRecordingEntry(recording)` helper
  - Parse filename using `parseFilename()`
  - If parsed: format as "lang - Mon DD, YYYY HH:MM:SS"
  - If not parsed: use raw filename
  - Add subText with filename and file size (MB)
  - Return chooser entry: `{text, subText, path, lang}`

### Step 4: Implement showRetranscribeChooser()

- Create `local function showRetranscribeChooser(callback)` in `init.lua`
  - Call `getRecentRecordings(obj.retranscribeCount)` to get files
  - If no recordings found (empty array):
    - Show warning alert: "⚠️ No recent recordings found in [tempDir]"
    - Use `obj.logger:warn()` with `showAlert = true`
    - Return early (don't show chooser)
  - Build chooser choices using `formatRecordingEntry()` for each recording
  - Store starting app: `obj.retranscribeStartingApp = hs.window.focusedWindow():application()`
  - Create `hs.chooser.new()` with callback:
    - If choice selected: call `retranscribe(choice.path, choice.lang, callback)`
    - If cancelled: reset `obj.retranscribeStartingApp = nil`
  - Set choices and show chooser

### Step 5: Implement retranscribe() Helper

- Create `local function retranscribe(audioFile, lang, callback)` in `init.lua`
  - Determine which transcriber to use:
    - If `obj.retranscribeTranscriber` is nil: use `obj.transcriber` (current)
    - Else: create instance of specified transcriber from `obj.config[obj.retranscribeTranscriber]`
  - If creating new transcriber instance:
    - Load transcriber file: `dofile(spoonPath .. "transcribers/" .. name .. "_transcriber.lua")`
    - Create instance: `Transcriber.new(obj.config[name])`
    - Validate: call `:validate()`, show error if fails
  - Parse language from filename if not provided (use `parseFilename()`)
  - If no language: default to `currentLang()`
  - Show alert: "🔄 Re-transcribing with [TranscriberName] ([lang])..."
  - Update menubar: show transcribing indicator
  - Call transcriber's `transcribe()` method:
    - `onSuccess(text)`: call `handleRetranscriptionResult(true, text, callback)`
    - `onError(err)`: call `handleRetranscriptionResult(false, err, callback)`

### Step 6: Implement handleRetranscriptionResult() Helper

- Create `local function handleRetranscriptionResult(success, textOrError, callback)` in `init.lua`
  - Reset menubar to idle state
  - If failed:
    - Show error alert with icon
    - Reset `obj.retranscribeStartingApp = nil`
    - Return
  - If callback provided:
    - Call `callback(textOrError)`
  - Else (no callback):
    - Check if auto-paste should happen:
      - Get current focused app
      - If same as `obj.retranscribeStartingApp`: auto-paste
      - Else: copy to clipboard only
    - If auto-paste:
      - Copy to clipboard: `hs.pasteboard.setContents(textOrError)`
      - Wait `obj.autoPasteDelay` seconds
      - Paste: use `obj.pasteWithEmacsYank` to determine key combo
    - Else:
      - Copy to clipboard: `hs.pasteboard.setContents(textOrError)`
      - Show alert: "📋 Retranscription copied to clipboard"
  - Reset `obj.retranscribeStartingApp = nil`

### Step 7: Implement Public API Method

- Add `function obj:transcribeLatestAgain(callback)` in `init.lua`
  - Validate spoon is started (check `obj.manager ~= nil`)
  - Call `showRetranscribeChooser(callback)`
  - Return `self` for method chaining

### Step 8: Add Hotkey Binding

- Modify `obj:bindHotKeys(mapping)` in `init.lua`
  - Add case for `name == "retranscribe"`:
    - Bind hotkey: `hs.hotkey.bind(spec[1], spec[2], "Retranscribe recent recording", function() obj:transcribeLatestAgain() end)`
    - Log: "Bound hotkey: retranscribe to [keys]"
- Update `obj.defaultHotkeys` to include example (commented out):
  - `-- retranscribe = {{"ctrl", "cmd"}, "r"},`

### Step 9: Write Unit Tests

- Create `tests/spec/unit/retranscription_spec.lua`
  - Test getRecentRecordings():
    - Returns empty array for empty directory
    - Returns recordings sorted by modification time (newest first)
    - Limits to N recordings
    - Handles missing tempDir gracefully
  - Test parseFilename():
    - Parses valid filenames correctly
    - Returns nil for invalid formats
    - Handles edge cases (invalid dates, missing components)
  - Test formatRecordingEntry():
    - Formats valid recordings with dates
    - Handles unparseable filenames
    - Shows file size in MB
  - Test app tracking:
    - Tracks starting app when chooser opens
    - Resets when chooser cancelled
    - Resets after retranscription completes

### Step 10: Write Integration Tests

- Create `tests/spec/integration/retranscription_integration_spec.lua`
  - Setup: Use real audio files from `tests/fixtures/audio/complete/`
  - Test retranscription with current transcriber:
    - Mock transcriber
    - Select file via programmatic chooser selection
    - Verify transcriber called with correct audio file and language
    - Verify callback invoked with result
  - Test retranscription with different transcriber:
    - Configure `obj.retranscribeTranscriber = "whispercli"`
    - Verify correct transcriber instance created
    - Verify transcription uses specified transcriber
  - Test auto-paste behavior:
    - Mock same app scenario: verify paste attempted
    - Mock different app scenario: verify clipboard only
  - Test callback behavior:
    - Provide callback: verify called, no clipboard/paste
    - No callback: verify clipboard/paste logic runs
  - Test error handling:
    - No recordings available: verify warning "No recent recordings found in [tempDir]" shown
    - Transcription fails: verify error alert shown
    - Invalid retranscribeTranscriber: verify validation error shown

### Step 11: Update Documentation

- Update `README.org`:
  - Add "Retranscription" section under features
  - Document configuration options:
    - `obj.retranscribeTranscriber` - which transcriber to use (nil = current)
    - `obj.retranscribeCount` - number of recent recordings to show
  - Add usage example:
    ```lua
    wd.retranscribeTranscriber = "whisperkit"  -- or nil for current
    wd.retranscribeCount = 15  -- show 15 recent recordings
    wd:bindHotKeys({
      toggle = {{"ctrl", "cmd"}, "d"},
      retranscribe = {{"ctrl", "cmd"}, "r"},
    })
    ```
  - Document auto-paste behavior (same app = paste, different = clipboard)
  - Add use case: "Re-try failed transcription" or "Use better transcriber"

- Update `docs/architecture.md`:
  - Add "Retranscription Feature" section
  - Document transcriber selection logic (retranscribeTranscriber vs current)
  - Document auto-paste behavior
  - Document filename parsing for language extraction
  - Note: uses same ITranscriber interface, just creates different instance

### Step 12: Run Validation Commands

Execute all validation commands to ensure no regressions.

## Validation Commands

Execute every command to validate the chore is complete with zero regressions:

```bash
# Run full test suite (must pass all tests)
make test

# Run unit tests specifically
busted tests/spec/unit/retranscription_spec.lua

# Run integration tests specifically
busted tests/spec/integration/retranscription_integration_spec.lua

# Verify no syntax errors in init.lua
luac -p init.lua

# Manual validation (requires Hammerspoon running)
# 1. Create test recordings:
mkdir -p /tmp/whisper_dict
cp tests/fixtures/audio/complete/en-*.wav /tmp/whisper_dict/

# 2. In Hammerspoon console, verify chooser shows files:
hs.loadSpoon("hs_whisperDictation")
wd = spoon.hs_whisperDictation
wd:start()
wd:transcribeLatestAgain()
# Verify: chooser appears with formatted dates and file sizes

# 3. Select a file, verify retranscription works
# Verify: alert shows "Re-transcribing with [Transcriber]..."
# Verify: result copied to clipboard or pasted

# 4. Test with different transcriber:
wd.retranscribeTranscriber = "whispercli"
wd:transcribeLatestAgain()
# Verify: uses whispercli instead of current transcriber

# 5. Test hotkey binding:
wd:bindHotKeys({retranscribe = {{"ctrl", "cmd"}, "r"}})
# Press Ctrl+Cmd+R
# Verify: chooser appears
```

## Document Changes

### README.org Updates

Add new section after "Multiple Languages":

```org
** Retranscription

Sometimes you want to re-transcribe a recording with a different transcriber, or retry a failed transcription.

*** Basic Usage

#+begin_src lua
wd:bindHotKeys({
  toggle = {{"ctrl", "cmd"}, "d"},
  retranscribe = {{"ctrl", "cmd"}, "r"},  -- Add this
})
#+end_src

Press *Ctrl+Cmd+R*, pick a recent recording, and it will be retranscribed.

*** Configuration

#+begin_src lua
-- Use a specific transcriber for retranscription
wd.retranscribeTranscriber = "whisperkit"  -- or nil to use current

-- Number of recent recordings to show
wd.retranscribeCount = 15  -- default is 10
#+end_src

*** Auto-Paste Behavior

- If you stay in the same app: text auto-pastes
- If you switch apps: text copies to clipboard

*** Use Cases

- Original transcription failed or had errors
- Want to try a more accurate transcriber (e.g., WhisperKit instead of WhisperCLI)
- Want to re-transcribe old recordings
```

### docs/architecture.md Updates

Add new section under "Extension Points":

```markdown
## Retranscription Feature

The retranscription feature allows users to re-transcribe previously recorded audio files.

### How It Works

1. User triggers retranscription (hotkey or API call)
2. System scans `obj.tempDir` for recent .wav files
3. Displays hs.chooser with formatted entries (date, size)
4. User selects file
5. System extracts language from filename (e.g., `en-20260216-120000.wav` → "en")
6. System transcribes using configured transcriber:
   - If `obj.retranscribeTranscriber` is set: use that transcriber
   - If nil: use current transcriber (`obj.transcriber`)
7. Result handled based on context:
   - Callback provided: call callback with result
   - Same app: auto-paste result
   - Different app: copy to clipboard

### Transcriber Selection

Two modes:
- **Current transcriber** (default): Uses `obj.transcriber` already initialized
- **Specific transcriber**: Creates new instance of specified transcriber

This allows flexibility (e.g., normal recording uses WhisperCLI, retranscription uses WhisperKit for higher accuracy).

### Language Extraction

Language is extracted from filename pattern: `{lang}-{YYYYMMDD}-{HHMMSS}.wav`

If parsing fails, falls back to current language (`currentLang()`).

### Auto-Paste Logic

Tracks starting app when chooser opens. If same app when retranscription completes, auto-pastes. Otherwise, copies to clipboard only.
```

## Git Log

```
Add retranscription feature to v2 architecture

Implement retranscription feature from v1.x (commit 62af849) adapted
for v2 callback-based architecture.

Features:
- obj:transcribeLatestAgain(callback) - public API method
- obj.retranscribeTranscriber - configurable transcriber (nil = current)
- obj.retranscribeCount - number of recent recordings to show
- retranscribe hotkey binding
- Auto-paste if same app (new in v2)
- Language extraction from filename

Implementation:
- getRecentRecordings(n) - scan tempDir for .wav files
- showRetranscribeChooser(callback) - display hs.chooser
- retranscribe(audioFile, lang, callback) - perform retranscription
- handleRetranscriptionResult() - handle success/error with auto-paste
- Unit tests for helpers
- Integration tests for full flow

Documentation:
- Updated README.org with retranscription section
- Updated docs/architecture.md with technical details
- Added configuration examples and use cases

Tests: 408+ tests still passing (added ~20 new tests)
```

## Notes

### Key Design Decisions

1. **Transcriber Selection**: Separate `retranscribeTranscriber` config allows using different transcriber for retranscription without affecting normal recording workflow. Common use case: quick recording with WhisperCLI, retranscribe with WhisperKit for accuracy.

2. **Language Extraction**: Parse language from filename to maintain original language. Fallback to current language if parsing fails.

3. **Auto-Paste Enhancement**: New in v2 - track starting app and auto-paste if user stays in same app. This is more convenient than v1's clipboard-only behavior.

4. **Callback Support**: Maintain v1 API compatibility - support callback parameter for custom handling (e.g., send to webhook instead of clipboard).

5. **Validation**: Only create transcriber instance if different from current. If using current transcriber, reuse existing instance (already validated at startup).

### Implementation Considerations

- **File scanning performance**: `hs.fs.dir()` is synchronous, but tempDir should have relatively few files (user's recordings). If performance becomes issue, consider caching.

- **Transcriber lifecycle**: If creating new transcriber instance for retranscription, no need to call cleanup() - instance is used once and garbage collected.

- **Chooser cancellation**: Reset `retranscribeStartingApp` when chooser cancelled to avoid memory leak.

- **Error handling**: Show user-friendly errors for common cases (no recordings, invalid transcriber, validation failures).

### Testing Strategy

- **Unit tests**: Test helpers in isolation (file scanning, parsing, formatting)
- **Integration tests**: Test full flow with mocks (no real Hammerspoon needed)
- **Manual testing**: Test real workflow with Hammerspoon running (optional, not CI)

### Migration from v1

No migration needed - this is a new feature in v2. Users upgrading from v1 will need to:
1. Update config: `retranscribeMethod` → `retranscribeTranscriber`
2. Bind hotkey: add `retranscribe` to `bindHotKeys()` call

### Future Enhancements (Not in Scope)

- Multi-file selection (retranscribe multiple files at once)
- Language override in chooser (requires multi-step UI)
- Batch retranscription (all recent recordings)
- Export retranscription results to file
