--- MockTranscriber - Mock implementation of ITranscriber for testing
---
--- Simulates transcription behavior with configurable timing and error conditions
---
--- @module MockTranscriber

local ITranscriber = dofile("transcribers/i_transcriber.lua")

local MockTranscriber = setmetatable({}, {__index = ITranscriber})
MockTranscriber.__index = MockTranscriber

--- Create a new MockTranscriber
---
--- @param config table Configuration options:
---   - transcriptPrefix: Prefix for transcribed text (default: "Transcribed: ")
---   - delay: Delay before transcription completes in seconds (default: 0.1)
---   - shouldFail: If true, simulates transcription failure (default: false)
---   - failureMode: "sync" (fail immediately) or "async" (fail after delay) (default: "async")
---   - supportedLanguages: Array of supported language codes (default: {"en", "es", "fr"})
--- @return table MockTranscriber instance
function MockTranscriber.new(config)
  config = config or {}
  local self = setmetatable({}, MockTranscriber)

  self.transcriptPrefix = config.transcriptPrefix or "Transcribed: "
  self.delay = config.delay or 0.1
  self.shouldFail = config.shouldFail or false
  self.failureMode = config.failureMode or "async"
  self.supportedLanguages = config.supportedLanguages or {"en", "es", "fr", "de", "ja", "zh"}

  self._timers = {}

  return self
end

--- Schedule a delayed callback with cancellation support
--- Works with mock hs.timer that executes immediately
---
--- @param delay number Delay in seconds (ignored in mock, executes immediately)
--- @param fn function Function to execute
--- @return table timer Timer-like object with stop() method
function MockTranscriber:_scheduleCallback(delay, fn)
  local timer = {
    _cancelled = false,
    running = function(self) return not self._cancelled end,
    stop = function(self) self._cancelled = true end
  }

  table.insert(self._timers, timer)

  -- Execute via hs.timer.doAfter (immediate in mock)
  hs.timer.doAfter(delay, function()
    if not timer._cancelled then
      fn()
    end
  end)

  return timer
end

--- Transcribe an audio file (mock implementation)
---
--- @param audioFile string Path to audio file
--- @param lang string Language code
--- @param onSuccess function Callback with transcribed text: onSuccess(text)
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if transcription started
--- @return string|nil error Error message if failed
function MockTranscriber:transcribe(audioFile, lang, onSuccess, onError)
  -- Simulate synchronous failure (e.g., file not found)
  if self.shouldFail and self.failureMode == "sync" then
    return false, "MockTranscriber: Transcription failed (sync)"
  end

  -- Simulate asynchronous transcription
  self:_scheduleCallback(self.delay, function()
    if self.shouldFail and self.failureMode == "async" then
      if onError then
        onError("MockTranscriber: Transcription failed (async)")
      end
    else
      -- Generate mock transcription text based on filename
      local filename = audioFile:match("([^/]+)$") or audioFile
      local text = self.transcriptPrefix .. filename

      if onSuccess then
        onSuccess(text)
      end
    end
  end)

  return true, nil
end

--- Validate mock transcriber (always succeeds unless configured to fail)
---
--- @return boolean success True if valid
--- @return string|nil error Error message if invalid
function MockTranscriber:validate()
  if self.shouldFail and self.failureMode == "validate" then
    return false, "MockTranscriber: Validation failed"
  end
  return true, nil
end

--- Get transcriber name
---
--- @return string name Transcriber name
function MockTranscriber:getName()
  return "MockTranscriber"
end

--- Check if language is supported
---
--- @param lang string Language code
--- @return boolean supported True if supported
function MockTranscriber:supportsLanguage(lang)
  for _, supportedLang in ipairs(self.supportedLanguages) do
    if supportedLang == lang then
      return true
    end
  end
  return false
end

--- Cleanup all pending timers
--- Should be called in test teardown to prevent timer pollution
function MockTranscriber:cleanup()
  for _, timer in ipairs(self._timers) do
    if timer:running() then
      timer:stop()
    end
  end
  self._timers = {}
end

return MockTranscriber
