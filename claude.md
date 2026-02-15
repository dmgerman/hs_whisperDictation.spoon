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

## Skills

- `/reload` - Reload Hammerspoon safely (see `.claude/commands/reload.md`)
- '/use-console-for-debugging.md' - access the console output (see `.claude/commands/use-console-for-debugging.md`)

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
