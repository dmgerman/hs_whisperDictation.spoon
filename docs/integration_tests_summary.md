# Integration Tests for Error Handling

## Problem

Our test suite had 377 unit tests but was missing integration tests for error scenarios. Specifically, we didn't catch the bug where trying to start a recording while already recording would stop the active recording.

## Root Causes Identified

### 1. RecordingManager Not Emitting Error Events Consistently

**Problem**: `RecordingManager` only emitted `recording:error` events when the backend rejected, NOT when RecordingManager itself validated parameters or state (lines 30-36, 82-84).

**Impact**: The `init.lua` error handler couldn't differentiate between start errors and recording errors because start errors were never emitted as events.

**Fix**: Added error event emission for ALL failures in `RecordingManager`:

```lua
-- Before (NO event emitted)
if self.state ~= "idle" then
  return Promise.reject("Already recording")
end

-- After (event emitted)
if self.state ~= "idle" then
  local err = "Already recording"
  self.eventBus:emit("recording:error", {
    error = err,
    context = "start"
  })
  return Promise.reject(err)
end
```

Applied to:
- `startRecording()`: Empty lang validation (context="start")
- `startRecording()`: Already recording check (context="start")
- `stopRecording()`: Not recording check (context="stop")

### 2. Missing Integration Tests

**Problem**: Unit tests verified individual components but didn't test how components work together through events.

**What Was Missing**:
- Event flow testing across components
- State consistency during error scenarios
- Error context propagation to event handlers
- ChunkAssembler behavior during recording errors

## Solution

### Created Comprehensive Integration Tests

**File**: `tests/spec/integration/error_handling_integration_spec.lua`

**Coverage** (12 tests):

1. **Start errors don't disrupt active recording**
   - Verifies duplicate start attempts don't stop active recording
   - Tests error event emission with correct context
   - Validates RecordingManager and backend state remain consistent

2. **Backend state vs RecordingManager state alignment**
   - Tests operational state (backend) matches recording state (manager)
   - Verifies state survives start errors

3. **ChunkAssembler state consistency**
   - Confirms ChunkAssembler doesn't reset on start errors
   - Tests proper reset on new recording

4. **Error event propagation**
   - Validates error events include correct context
   - Tests error handlers can differentiate error types

5. **State recovery after errors**
   - Confirms clean recovery from start/stop errors
   - Tests multiple error scenarios in sequence

6. **Complete workflows**
   - Simulates real-world error recovery scenario
   - Tests init.lua error handler pattern

## Test Results

### Before Fix
- 377 unit tests passed
- 0 integration tests for error handling
- Bug: Start errors stopped active recordings

### After Fix
- **389 tests pass** (377 unit + 12 integration)
- All error scenarios covered
- Bug fixed: Start errors no longer disrupt active recordings

## Key Learnings

1. **Unit tests alone aren't enough**: We had unit tests for RecordingManager that verified it rejects duplicate starts, but we didn't test the EVENT FLOW or integration with init.lua handlers.

2. **Event-driven architecture needs event flow tests**: When components communicate via events, you need integration tests that verify the entire event chain.

3. **Error events need consistent emission**: If error handling depends on event context, ALL errors (not just backend errors) must emit events consistently.

4. **Integration tests catch cross-component bugs**: The bug we fixed (start errors stopping active recordings) only manifested when RecordingManager, EventBus, and init.lua worked together.

## Architecture Improvement

### Before
```
RecordingManager
  ├─ Backend errors → emit recording:error ✓
  └─ Validation errors → NO EVENT ✗
```

### After
```
RecordingManager
  ├─ Backend errors → emit recording:error ✓
  ├─ Validation errors → emit recording:error ✓
  └─ State errors → emit recording:error ✓
```

All errors now have consistent event emission with proper context.

## Files Changed

1. **core/recording_manager.lua**
   - Added error event emission for parameter validation
   - Added error event emission for state validation
   - All errors now include `context` field

2. **tests/spec/integration/error_handling_integration_spec.lua** (NEW)
   - 12 comprehensive integration tests
   - Tests error event flows
   - Tests state consistency across components
   - Tests real-world error scenarios

## Conclusion

The integration tests successfully caught the bug that our 377 unit tests missed. By fixing RecordingManager to emit error events consistently, the existing `init.lua` error handler (which checks `data.context != "start"`) now works correctly.

This demonstrates the importance of both unit AND integration testing in event-driven architectures.
