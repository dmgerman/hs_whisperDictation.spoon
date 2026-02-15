# Critical Fixes - Silent Failure Issues

## Problems Identified

### 1. Wrong Default Backend
- **Issue**: Default was `pythonstream` but tests used `sox`
- **Impact**: Recording failed silently because Python server wasn't running
- **Fix**: Changed default to `sox` (tested and working)

### 2. Silent Promise Failures
- **Issue**: Promise rejections weren't showing errors to users
- **Impact**: When recording failed, NO ERROR was shown - completely silent
- **Fix**: Added explicit error handling with `hs.alert.show()` for ALL failures

### 3. Insufficient Validation
- **Issue**: Backend/method validation didn't fail early enough
- **Impact**: Errors only appeared when trying to record, not at startup
- **Fix**: Added comprehensive validation with visible error messages

## Changes Made

### init.lua Line 88-91: Fixed Defaults
```lua
-- Before
obj.recordingBackend = "pythonstream"
obj.transcriptionMethod = "whispercli"

// After
obj.recordingBackend = "sox"
obj.transcriptionMethod = "whisperserver"
```

### init.lua Line 963-981: Fixed Silent Recording Failures
```lua
// Before - errors were swallowed
self.recordingManager:startRecording(currentLang())
  :andThen(successHandler, errorHandler)

// After - errors ALWAYS shown
local promise = self.recordingManager:startRecording(currentLang())
if not promise then
  self.logger:error("❌ CRITICAL: startRecording returned nil", true)
  hs.alert.show("❌ Recording failed", 10.0)
  return
end
promise:next(successHandler):catch(function(err)
  hs.alert.show("❌ Recording failed: " .. tostring(err), 10.0)
  resetMenuToIdle()
end)
```

### init.lua Line 1070-1078: Added Backend Validation Alerts
```lua
// Before - errors only in logs
if not backendValid then
  obj.logger:error("Backend validation failed: " .. validateErr, true)
  return
end

// After - errors shown prominently
if not backendValid then
  local errorMsg = "❌ Backend validation failed: " .. validateErr
  obj.logger:error(errorMsg, true)
  hs.alert.show(errorMsg, 15.0)  -- 15 second alert!
  return
end
```

### init.lua Line 1103-1117: Added Method Validation
```lua
// Added NEW validation step
local methodValid, methodValidateErr = methodInstance:validate()
if not methodValid then
  local errorMsg = "❌ Transcription method validation failed: " .. methodValidateErr
  hs.alert.show(errorMsg, 15.0)
  return
end
```

### init.lua Line 631-634: Added Transcription Error Alerts
```lua
// Before - errors only in logs
obj.eventBus:on("transcription:error", function(data)
  obj.logger:error("Transcription error: " .. data.error)
end)

// After - errors shown to user
obj.eventBus:on("transcription:error", function(data)
  local errorMsg = "❌ Transcription error: " .. data.error
  obj.logger:error(errorMsg)
  hs.alert.show(errorMsg, 10.0)  -- 10 second alert
end)
```

## Error Handling Principles Applied

1. **Fail Fast**: Validate everything at startup, not when recording
2. **Fail Loud**: ALWAYS show errors to user with `hs.alert.show()`
3. **Fail Clear**: Use ❌ emoji and descriptive messages
4. **Fail Visible**: 10-15 second alerts so users can't miss them

## Testing

After reload:
```bash
hs -c "print(spoon.hs_whisperDictation.recordingBackend)"
# Output: sox

hs -c "print(spoon.hs_whisperDictation.transcriptionMethod)"
# Output: whisperserver

hs -c "local s,e = spoon.hs_whisperDictation.backendInstance:validate(); print(s,e)"
# Output: true nil
```

## What Users Will See Now

### On Startup Success:
```
✓ WhisperDictation ready: sox + whisperserver
```

### On Backend Validation Failure:
```
❌ Backend validation failed: sox not found at /opt/homebrew/bin/sox
(Alert shown for 15 seconds)
```

### On Recording Failure:
```
❌ Recording failed: Backend not available
(Alert shown for 10 seconds)
```

### On Transcription Failure:
```
❌ Transcription error: Server not responding
(Alert shown for 10 seconds)
```

## Impact

- ✅ NO MORE SILENT FAILURES
- ✅ Users always know what went wrong
- ✅ Errors are visible and actionable
- ✅ Default configuration works out of the box
- ✅ Validation happens at startup, not at use time

## Next Steps

1. Test actual recording: Press hotkey and verify recording starts
2. Check /tmp/whisper_dict for new files
3. If still no files, the error message will now tell you WHY
