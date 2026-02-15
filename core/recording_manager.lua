--- RecordingManager - Manage recording lifecycle and state
-- Coordinates with backend and emits events for UI/other components

local RecordingManager = {}
RecordingManager.__index = RecordingManager

--- Create a new RecordingManager
-- @param backend (IRecordingBackend): Recording backend implementation
-- @param eventBus (EventBus): Event bus for communication
-- @param config (table): Configuration {tempDir, languages, ...}
-- @return (RecordingManager): New instance
function RecordingManager.new(backend, eventBus, config)
  local self = setmetatable({}, RecordingManager)
  self.backend = backend
  self.eventBus = eventBus
  self.config = config
  self.state = "idle"  -- idle, recording, stopping
  self.currentLang = nil
  self.startTime = nil
  return self
end

--- Start recording
-- @param lang (string): Language code (e.g., "en", "ja")
-- @return (Promise): Resolves when recording starts, rejects on error
function RecordingManager:startRecording(lang)
  local Promise = require("lib.promise")

  -- CRITICAL: Validate parameters
  if not lang or lang == "" then
    local err = "Language parameter is required and cannot be empty"
    self.eventBus:emit("recording:error", {
      error = err,
      context = "start"
    })
    return Promise.reject(err)
  end

  if self.state ~= "idle" then
    local err = "Already recording"
    self.eventBus:emit("recording:error", {
      error = err,
      context = "start"
    })
    return Promise.reject(err)
  end

  self.state = "recording"
  self.currentLang = lang
  self.startTime = os.time()

  return self.backend:startRecording({
    outputDir = self.config.tempDir,
    filenamePrefix = lang,
    lang = lang,
  })
    :next(function()
      -- Success handler - emit event and return to continue chain
      self.eventBus:emit("recording:started", {
        lang = lang,
        startTime = self.startTime,
      })
      return true  -- Return value to propagate success
    end)
    :catch(function(err)
      -- Error handler - cleanup and emit event
      self:_resetState()
      self.eventBus:emit("recording:error", {
        error = err,
        context = "start"
      })
      -- Return rejected promise to propagate error
      return Promise.reject(err)
    end)
end

--- Stop recording
-- @return (Promise): Resolves when recording stops, rejects on error
function RecordingManager:stopRecording()
  local Promise = require("lib.promise")

  if self.state ~= "recording" then
    local err = "Not recording"
    self.eventBus:emit("recording:error", {
      error = err,
      context = "stop"
    })
    return Promise.reject(err)
  end

  self.state = "stopping"

  return self.backend:stopRecording()
    :next(function()
      -- Success handler
      local duration = self.startTime and (os.time() - self.startTime) or 0
      self:_resetState()

      self.eventBus:emit("recording:stopped", {
        duration = duration,
      })
      return true  -- Return value to propagate success
    end)
    :catch(function(err)
      -- Error handler - cleanup and emit event
      self:_resetState()
      self.eventBus:emit("recording:error", {
        error = err,
        context = "stop"
      })
      -- Return rejected promise to propagate error
      return Promise.reject(err)
    end)
end

--- Reset state to idle (single source of truth)
function RecordingManager:_resetState()
  self.state = "idle"
  self.currentLang = nil
  self.startTime = nil
end

--- Check if currently recording
-- @return (boolean): true if recording
function RecordingManager:isRecording()
  return self.state == "recording"
end

--- Get current status
-- @return (table): Status information
function RecordingManager:getStatus()
  return {
    state = self.state,
    isRecording = self:isRecording(),
    currentLang = self.currentLang,
    startTime = self.startTime,
    duration = self.startTime and (os.time() - self.startTime) or 0,
  }
end

return RecordingManager
