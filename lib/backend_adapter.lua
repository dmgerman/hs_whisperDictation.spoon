--- Backend Adapter
-- Adapts callback-based recording-backend.lua backends to Promise-based interface
-- This allows RecordingManager to work with the old backends

local BackendAdapter = {}
BackendAdapter.__index = BackendAdapter

--- Wrap a callback-based backend to expose Promise-based interface
-- @param callbackBackend (table): The callback-based backend from recording-backend.lua
-- @param eventBus (EventBus): EventBus for emitting events
-- @return (table): Adapted backend with Promise-based interface
function BackendAdapter.wrap(callbackBackend, eventBus)
  local self = setmetatable({}, BackendAdapter)
  self.callbackBackend = callbackBackend
  self.eventBus = eventBus
  return self
end

function BackendAdapter:validate()
  return self.callbackBackend:validate()
end

function BackendAdapter:startRecording(config)
  local Promise = require("lib.promise")

  return Promise.new(function(resolve, reject)
    -- Create callback for backend events
    local callback = function(event)
      if event.type == "chunk_ready" then
        self.eventBus:emit("audio:chunk_ready", {
          audioFile = event.audioFile or event.audio_file,
          chunkNum = event.chunkNum or event.chunk_num,
          lang = config.lang,
          isFinal = event.isFinal or event.is_final,
        })
      elseif event.type == "recording_started" then
        self.eventBus:emit("recording:started", {lang = config.lang})
      elseif event.type == "recording_stopped" then
        self.eventBus:emit("recording:stopped", {})
      elseif event.type == "error" then
        self.eventBus:emit("recording:error", {error = event.error or event.message})
      end
    end

    -- Start the backend with callback
    local success, err = pcall(function()
      self.callbackBackend:startRecording(
        config.outputDir,
        config.filenamePrefix,
        config.lang,
        callback
      )
    end)

    if success then
      resolve()
    else
      reject(err)
    end
  end)
end

function BackendAdapter:stopRecording()
  local Promise = require("lib.promise")

  return Promise.new(function(resolve, reject)
    local success, err = pcall(function()
      self.callbackBackend:stopRecording()
    end)

    if success then
      resolve()
    else
      reject(err)
    end
  end)
end

function BackendAdapter:isRecording()
  return self.callbackBackend:isRecording()
end

function BackendAdapter:getName()
  return self.callbackBackend.name or "adapted-backend"
end

function BackendAdapter:getDisplayText(lang)
  if self.callbackBackend.getDisplayText then
    return self.callbackBackend:getDisplayText(lang)
  end
  return "🎙️ " .. lang
end

return BackendAdapter
