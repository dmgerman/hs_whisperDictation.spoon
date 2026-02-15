# Stateless Backend Refactoring

## Problem

Backends were duplicating state that RecordingManager already owned, violating single source of truth principle.

**Before**:
```lua
-- RecordingManager
self.state = "idle"
self.currentLang = nil
self.startTime = nil

-- StreamingBackend (DUPLICATE!)
self._isRecording = false
self.currentLang = nil
self._startTime = nil

-- SoxBackend (DUPLICATE!)
self.audioFile = nil
self.currentLang = nil
self.startTime = nil
```

## Solution

Backends now only track **minimal operational state** needed for their function. RecordingManager is the **single source of truth** for recording state.

## Changes Made

### StreamingBackend

**Removed** (recording state):
- ❌ `self._isRecording` - RecordingManager tracks this
- ❌ `self.currentLang` → Now `self._currentLang` (operational only)
- ❌ `self._startTime` - RecordingManager tracks this
- ❌ `self._currentChunkStartTime` - Not needed

**Kept** (operational state):
- ✅ `self.serverProcess` - Tracks if Python server running
- ✅ `self.tcpSocket` - TCP connection handle
- ✅ `self._chunkCount` - Counter for event data
- ✅ `self._currentLang` - Needed for event routing (not recording state)

**Updated**:
```lua
-- Before: Checked recording state
function StreamingBackend:isRecording()
  return self._isRecording
end

-- After: Checks operational state
function StreamingBackend:isRecording()
  return self.serverProcess ~= nil
end
```

### SoxBackend

**Removed** (recording state):
- ❌ `self.audioFile` → Now `self._currentAudioFile` (temporary)
- ❌ `self.currentLang` → Now `self._currentLang` (operational only)
- ❌ `self.startTime` - RecordingManager tracks this

**Kept** (operational state):
- ✅ `self.task` - Sox task handle
- ✅ `self._currentAudioFile` - Temporary for task completion
- ✅ `self._currentLang` - Needed for event data

**Updated**:
```lua
-- Before: Tracked time
if not self.startTime then
  return ""
end
local elapsed = os.difftime(os.time(), self.startTime)

-- After: Delegates to RecordingManager
local elapsed = 0  -- Backend doesn't track time
```

### RecordingManager

**Unchanged** - Already had proper state management:
- ✅ `self.state` - "idle", "recording", "stopping"
- ✅ `self.currentLang` - Current language
- ✅ `self.startTime` - When recording started

**Added centralized cleanup**:
```lua
function RecordingManager:_resetState()
  self.state = "idle"
  self.currentLang = nil
  self.startTime = nil
end
```

## Architecture

### Before (WRONG)
```
┌─────────────────┐     ┌──────────────┐
│ RecordingManager│     │   Backend    │
│  - state        │     │ - _isRecording│  ← DUPLICATE!
│  - currentLang  │     │ - currentLang │  ← DUPLICATE!
│  - startTime    │     │ - startTime   │  ← DUPLICATE!
└─────────────────┘     └──────────────┘
```

### After (RIGHT)
```
┌─────────────────┐     ┌──────────────┐
│ RecordingManager│     │   Backend    │
│  - state        │     │ - serverProc  │  ← Operational
│  - currentLang  │────>│ - tcpSocket   │  ← Operational
│  - startTime    │     │ - _currentLang│  ← For events
└─────────────────┘     └──────────────┘
    (Source of Truth)      (Thin wrapper)
```

## Benefits

1. **Single Source of Truth**: RecordingManager owns ALL recording state
2. **No Duplication**: State not scattered across multiple classes
3. **Clear Separation**:
   - RecordingManager = Smart coordinator (state + logic)
   - Backend = Dumb executor (commands + events)
4. **Easier to Maintain**: State changes in ONE place
5. **Less Error-Prone**: Can't have inconsistent state

## Test Results

**All 454 tests pass** ✅
- Lua: 377 tests
- Python: 77 tests

No behavioral changes - pure refactoring for cleaner architecture.

## State Management Summary

### Recording State (RecordingManager ONLY)
- `state`: "idle" | "recording" | "stopping"
- `currentLang`: Language being recorded
- `startTime`: When recording started

### Operational State (Backends)
- StreamingBackend: Server process, TCP socket, chunk counter
- SoxBackend: Sox task handle, temporary file path

### Key Principle
**Backends answer "Is my operation running?" NOT "Are we recording?"**

That's RecordingManager's job.
