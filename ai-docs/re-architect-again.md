# Recommendation: Move Away From Event-Driven Architecture

## TL;DR

**The event-driven architecture adds complexity without clear benefits for this codebase.** Consider refactoring to direct function calls with Promise chains.

## Problems With Current Event-Driven Approach

### 1. Hidden Control Flow
```lua
-- What happens when this executes? Have to search entire codebase
eventBus:emit("recording:error", { context = "start" })

-- Could be handled in:
-- - init.lua
-- - Some other module
-- - Multiple places
-- - Or nowhere (silent failure)
```

**Impact**: Can't understand code by reading it linearly. Must grep for event handlers.

### 2. Debugging Nightmare
- Stack traces don't cross event boundaries
- "Where did this event come from?" → Search all `eventBus:emit("event_name")`
- "Who handles this event?" → Search all `eventBus:on("event_name")`
- Event name typos fail silently

### 3. False Decoupling
```lua
-- RecordingManager "doesn't know about UI"... right?
eventBus:emit("recording:started", { lang = lang })

-- But init.lua still has to wire everything:
eventBus:on("recording:started", function(data)
  updateMenuBar()
  showAlert()
  -- init.lua is a god object in disguise
end)
```

**Reality**: init.lua coordinates everything anyway. The "decoupling" is illusory.

### 4. Implicit Contracts
```lua
// Backend emits
{ chunk_num = 1, audio_file = "/tmp/x.wav", is_final = false }

// What fields are required?
// What's the type of each field?
// No compile-time checks, no clear interface
```

### 5. Integration Tests Required
We needed 12 integration tests to catch bugs that wouldn't exist with direct calls.

**Why?** Because events scatter control flow across components. Unit tests can't catch cross-component bugs when everything communicates through events.

**This is a symptom, not a feature.**

## What Events Actually Buy You

Event-driven architecture is good when:

### ✅ Multiple Independent Listeners
```lua
eventBus:emit("recording:progress", { duration = 10 })
// → Menubar updates
// → Floating progress window updates
// → Dock badge updates
// → Notification center updates
```

**Do we have this?** No. Only init.lua handles most events.

### ✅ Plugin Architecture
```lua
-- Third-party plugins can extend behavior
eventBus:on("transcription:completed", myCustomPlugin)
```

**Do we have this?** No. Not building a plugin system.

### ✅ Event Sourcing / Undo-Redo
```lua
-- Log all events for replay/debugging
```

**Do we have this?** No.

## Proposed Simpler Architecture

### Direct Function Calls + Promises

```lua
-- RecordingManager (no events)
function RecordingManager:startRecording(lang)
  local Promise = require("lib.promise")

  if not lang or lang == "" then
    return Promise.reject({
      type = "validation",
      message = "Language required"
    })
  end

  if self.state ~= "idle" then
    return Promise.reject({
      type = "already_recording",
      message = "Already recording"
    })
  end

  self.state = "recording"
  self.currentLang = lang
  self.startTime = os.time()

  return self.backend:startRecording(config)
end
```

```lua
-- init.lua (explicit control flow)
function obj:startRecordingSession(lang)
  self.recordingManager:startRecording(lang)
    :next(function()
      -- Success
      self:updateMenuBar("🎙️ Recording...")
      hs.alert.show("Recording started")
    end)
    :catch(function(err)
      -- Handle different error types explicitly
      if err.type == "already_recording" then
        -- Don't disrupt active recording
        hs.alert.show("Already recording!")
      elseif err.type == "validation" then
        hs.alert.show("Error: " .. err.message)
      else
        -- Unexpected error - stop and cleanup
        self:stopRecordingSession()
        hs.alert.show("Recording failed: " .. err.message)
      end
    end)
end
```

### Benefits

✅ **Explicit control flow** - Read code top to bottom
✅ **Clear error handling** - In Promise chain, not scattered event handlers
✅ **Type-safe errors** - Structured error objects, not string matching
✅ **Stack traces work** - No event boundary to cross
✅ **No typos** - `manager:startRecording()` fails at runtime if method doesn't exist
✅ **Simpler testing** - Unit tests are sufficient

## Before/After Comparison

### Before (Event-Driven)

```lua
-- recording_manager.lua
function RecordingManager:startRecording(lang)
  -- ... validation ...

  return self.backend:startRecording(config)
    :next(function()
      self.eventBus:emit("recording:started", { lang = lang })
    end)
    :catch(function(err)
      self.eventBus:emit("recording:error", {
        error = err,
        context = "start"
      })
    end)
end

-- init.lua (somewhere else in the file)
obj.eventBus:on("recording:started", function(data)
  updateMenuBar()
end)

obj.eventBus:on("recording:error", function(data)
  if data.context ~= "start" then
    stopRecordingSession()
  end
end)
```

**Problems:**
- Control flow split across files
- Error handling in event handler (hard to find)
- String matching on context
- No type safety

### After (Direct Calls)

```lua
-- recording_manager.lua
function RecordingManager:startRecording(lang)
  -- ... validation ...

  return self.backend:startRecording(config)
end

-- init.lua
function obj:startRecording(lang)
  self.recordingManager:startRecording(lang)
    :next(function()
      self:updateMenuBar()
    end)
    :catch(function(err)
      if err.type ~= "already_recording" then
        self:stopRecordingSession()
      end
      self:showError(err.message)
    end)
end
```

**Benefits:**
- All control flow in one place
- Error handling right there
- Structured error types
- Easy to read and debug

## Migration Strategy

If you decide to refactor:

### Phase 1: Core Flows (High Impact)
1. **Recording lifecycle**: start/stop recording
2. **Transcription flow**: transcribe → result
3. **Error handling**: Replace event-based with Promise chains

### Phase 2: UI Updates
Keep events for UI updates IF you have multiple UI components. Otherwise, use callbacks.

### Phase 3: Cleanup
- Remove EventBus from core modules
- Keep EventBus only where genuinely needed (multiple listeners)

### Incremental Approach
```lua
// Hybrid: Support both during migration
function RecordingManager:startRecording(lang, options)
  options = options or {}

  return self.backend:startRecording(config)
    :next(function()
      -- Backward compat: emit event
      if not options.skipEvents then
        self.eventBus:emit("recording:started", { lang = lang })
      end
      return { lang = lang }  -- Return value for direct calls
    end)
end
```

## When to Keep Events

**Keep events for:**
- Progress updates (if multiple UI components need them)
- Logging/debugging (event listener logs all events)
- Genuine plugin points (if you add plugin support later)

**Remove events for:**
- Core control flow (start/stop recording)
- Error handling
- One-to-one communication

## The Harsh Truth

The current architecture is **over-engineered** for this use case:

- ❌ Only one UI (init.lua), not multiple independent components
- ❌ Not a plugin system
- ❌ "Decoupling" is illusory when init.lua coordinates everything
- ❌ Integration tests needed to catch basic bugs = too much indirection

**Simpler is better.**

## Conclusion

Event-driven architecture added:
- ✅ Complexity
- ✅ Debugging difficulty
- ✅ Hidden control flow
- ❌ No real benefits for this codebase

**Recommendation**: Refactor to direct function calls with Promise chains. Save events for genuinely multi-listener scenarios.

The fact that you questioned this architecture means your instincts are correct. Trust them.

---

**Next Steps (If You Agree):**
1. Prototype one flow (e.g., startRecording) without events
2. Compare complexity and clarity
3. Decide whether to migrate the rest
4. Document decision (either way)
