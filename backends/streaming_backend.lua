--- StreamingBackend - Adapter for recording-backend.lua pythonstream
-- This bridges the old callback-based interface to the new EventBus/Promise interface

local StreamingBackend = {}
StreamingBackend.__index = StreamingBackend

--- Create a new StreamingBackend
-- @param eventBus (EventBus): Event bus for emitting events
-- @param config (table): Configuration
-- @return (StreamingBackend): New instance
function StreamingBackend.new(eventBus, config)
  local self = setmetatable({}, StreamingBackend)
  self.eventBus = eventBus

  -- Load the working pythonstream backend from recording-backend.lua
  local RecordingBackends = dofile(debug.getinfo(1).source:match("@?(.*/)") .. "../recording-backend.lua")
  self.backend = RecordingBackends.pythonstream

  -- Configure it
  -- Resolve python path to full path (hs.task requires full paths)
  local pythonPath = config.pythonExecutable or self.backend.config.pythonCmd
  if not pythonPath:match("^/") then
    local handle = io.popen("which " .. pythonPath .. " 2>/dev/null")
    if handle then
      local result = handle:read("*l")
      handle:close()
      if result and result ~= "" then
        pythonPath = result
      end
    end
  end

  self.backend.config.pythonCmd = pythonPath
  self.backend.config.scriptPath = config.serverScript
  self.backend.config.port = config.tcpPort
  self.backend.config.silenceThreshold = config.silenceThreshold
  self.backend.config.minChunkDuration = config.minChunkDuration
  self.backend.config.maxChunkDuration = config.maxChunkDuration

  -- Set up callback adapter to convert callbacks to EventBus events
  self.backend._callback = function(event)
    self:_handleEvent(event)
  end

  return self
end

--- Handle events from old backend and emit to EventBus
-- @private
function StreamingBackend:_handleEvent(event)
  if event.type == "recording_started" then
    self.eventBus:emit("recording:started", { lang = self.currentLang })

  elseif event.type == "chunk_ready" then
    self.eventBus:emit("audio:chunk_ready", {
      chunkNum = event.chunk_num,
      audioFile = event.audio_file,
      lang = self.currentLang,
      isFinal = event.is_final,
    })

  elseif event.type == "recording_stopped" then
    self.eventBus:emit("recording:stopped", {})

  elseif event.type == "error" then
    self.eventBus:emit("recording:error", { error = event.error })
  end
end

--- Validate backend
function StreamingBackend:validate()
  return self.backend:validate()
end

--- Start recording
function StreamingBackend:startRecording(config)
  local Promise = require("lib.promise")

  self.currentLang = config.lang

  print("[StreamingBackend Adapter] startRecording called with lang=" .. config.lang)
  print("[StreamingBackend Adapter] outputDir=" .. (config.outputDir or "/tmp"))

  return Promise.new(function(resolve, reject)
    print("[StreamingBackend Adapter] Calling backend:startRecording...")
    local ok, err = self.backend:startRecording(
      config.outputDir or "/tmp",
      config.lang,
      config.lang,
      self.backend._callback
    )

    print("[StreamingBackend Adapter] Backend returned: ok=" .. tostring(ok) .. " err=" .. tostring(err))

    if ok then
      print("[StreamingBackend Adapter] Resolving promise")
      resolve()
    else
      print("[StreamingBackend Adapter] Rejecting promise: " .. tostring(err))
      reject(err or "Failed to start recording")
    end
  end)
end

--- Stop recording
function StreamingBackend:stopRecording()
  local Promise = require("lib.promise")

  return Promise.new(function(resolve, reject)
    local ok, err = self.backend:stopRecording()

    if ok then
      resolve()
    else
      reject(err or "Failed to stop recording")
    end
  end)
end

--- Check if recording
function StreamingBackend:isRecording()
  return self.backend:isRecording()
end

--- Get display text
function StreamingBackend:getDisplayText(lang)
  return self.backend:getRecordingDisplayText(lang)
end

--- Get backend name
function StreamingBackend:getName()
  return "streaming"
end

--- Shutdown
function StreamingBackend:shutdown()
  if self.backend.stopServer then
    self.backend:stopServer()
  end
  return true
end

return StreamingBackend
