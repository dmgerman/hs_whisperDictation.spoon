--- MockRecorder - Mock implementation of IRecorder for testing
---
--- Simulates recording behavior with configurable chunk emission,
--- timing, and error conditions
---
--- @module MockRecorder

local IRecorder = dofile("recorders/i_recorder.lua")

local MockRecorder = setmetatable({}, {__index = IRecorder})
MockRecorder.__index = MockRecorder

--- Create a new MockRecorder
---
--- @param config table Configuration options:
---   - chunkCount: Number of chunks to emit (default: 1)
---   - chunkDelays: Array of delays per chunk in seconds (default: all use base delay)
---   - delay: Base delay for chunks if chunkDelays not specified (default: 0.1)
---   - shouldFail: If true, simulates recording failure (default: false)
---   - failureMode: "sync" (fail on start) or "async" (fail during recording) (default: "sync")
--- @return table MockRecorder instance
function MockRecorder.new(config)
  config = config or {}
  local self = setmetatable({}, MockRecorder)

  self.chunkCount = config.chunkCount or 1
  self.chunkDelays = config.chunkDelays or nil
  self.baseDelay = config.delay or 0.1
  self.shouldFail = config.shouldFail or false
  self.failureMode = config.failureMode or "sync"

  self._isRecording = false
  self._timers = {}
  self._emittedChunks = 0

  return self
end

--- Start recording (mock implementation)
---
--- @param config table Recording configuration
--- @param onChunk function Callback for chunk emission: onChunk(audioFile, chunkNum, isFinal)
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if started successfully
--- @return string|nil error Error message if failed
function MockRecorder:startRecording(config, onChunk, onError)
  if self._isRecording then
    return false, "Already recording"
  end

  -- Simulate synchronous failure
  if self.shouldFail and self.failureMode == "sync" then
    return false, "MockRecorder: Failed to start recording"
  end

  self._isRecording = true
  self._emittedChunks = 0
  self._onChunk = onChunk
  self._onError = onError
  self._config = config

  -- Simulate asynchronous failure during recording
  if self.shouldFail and self.failureMode == "async" then
    self:_scheduleCallback(self.baseDelay, function()
      self._isRecording = false
      if onError then
        onError("MockRecorder: Recording failed during operation")
      end
    end)
    return true, nil
  end

  -- Schedule chunk emissions
  for i = 1, self.chunkCount do
    local delay = self.chunkDelays and self.chunkDelays[i] or (self.baseDelay * i)
    self:_scheduleCallback(delay, function()
      self:_emitChunk(i)
    end)
  end

  return true, nil
end

--- Stop recording (mock implementation)
---
--- @param onComplete function Callback invoked when stop completes
--- @param onError function Callback for errors
--- @return boolean success True if stopped successfully
--- @return string|nil error Error message if failed
function MockRecorder:stopRecording(onComplete, onError)
  if not self._isRecording then
    return false, "Not recording"
  end

  self._isRecording = false
  self._onComplete = onComplete

  -- Cancel any pending chunk emissions
  self:cleanup()

  -- Invoke completion callback asynchronously
  if onComplete then
    hs.timer.doAfter(0.01, function()
      onComplete()
    end)
  end

  return true, nil
end

--- Validate mock recorder (always succeeds unless configured to fail)
---
--- @return boolean success True if valid
--- @return string|nil error Error message if invalid
function MockRecorder:validate()
  if self.shouldFail and self.failureMode == "validate" then
    return false, "MockRecorder: Validation failed"
  end
  return true, nil
end

--- Check if currently recording
---
--- @return boolean isRecording True if recording
function MockRecorder:isRecording()
  return self._isRecording
end

--- Get recorder name
---
--- @return string name Recorder name
function MockRecorder:getName()
  return "MockRecorder"
end

--- Schedule a delayed callback with cancellation support
--- Works with mock hs.timer that executes immediately
---
--- @param delay number Delay in seconds (ignored in mock, executes immediately)
--- @param fn function Function to execute
--- @return table timer Timer-like object with stop() method
function MockRecorder:_scheduleCallback(delay, fn)
  local cancelled = false
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

--- Emit a single chunk (internal method)
---
--- @param chunkNum number Chunk number to emit
function MockRecorder:_emitChunk(chunkNum)
  if not self._isRecording then
    return
  end

  self._emittedChunks = self._emittedChunks + 1

  -- Generate mock audio file path
  local timestamp = os.date("%Y%m%d-%H%M%S")
  local audioFile = string.format("%s/%s-chunk-%d-%s.wav",
    self._config.outputDir or "/tmp",
    self._config.lang or "en",
    chunkNum,
    timestamp)

  -- INVARIANT: isFinal is true ONLY when chunkNum == chunkCount
  local isFinal = (chunkNum == self.chunkCount)

  -- Invoke callback
  if self._onChunk then
    self._onChunk(audioFile, chunkNum, isFinal)
  end
end

--- Cleanup all pending timers
--- Should be called in test teardown to prevent timer pollution
function MockRecorder:cleanup()
  for _, timer in ipairs(self._timers) do
    if timer:running() then
      timer:stop()
    end
  end
  self._timers = {}
end

return MockRecorder
