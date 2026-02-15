--- SoxBackend - Simple sox-based audio recording
-- Records a single audio file, emits chunk_ready when stopped
-- Clean Promise-based architecture with EventBus

local SoxBackend = {}
SoxBackend.__index = SoxBackend

--- Create a new SoxBackend instance
-- @param eventBus (EventBus): Event bus for emitting events
-- @param config (table): Configuration {soxCmd, tempDir}
-- @return (SoxBackend): New instance
function SoxBackend.new(eventBus, config)
  local self = setmetatable({}, SoxBackend)

  self.eventBus = eventBus
  self.soxCmd = config.soxCmd or "/opt/homebrew/bin/sox"
  self.tempDir = config.tempDir or "/tmp/whisper_dict"

  -- Operational state only (NOT recording state)
  self.task = nil
  self._currentAudioFile = nil  -- Temporary for task completion
  self._currentLang = nil  -- Needed for event data

  return self
end

--- Validate sox command is available
-- @return (boolean, string?): success, error message if failed
function SoxBackend:validate()
  local attrs = hs.fs.attributes(self.soxCmd)
  if attrs then
    return true
  else
    return false, "sox not found at: " .. self.soxCmd
  end
end

--- Start recording audio
-- @param config (table): {outputDir, filenamePrefix, lang}
-- @return (Promise): Resolves when recording starts
function SoxBackend:startRecording(config)
  local Promise = require("lib.promise")

  if self.task then
    return Promise.reject("Already recording")
  end

  return Promise.new(function(resolve, reject)
    -- Generate timestamped filename
    local timestamp = os.date("%Y%m%d-%H%M%S")
    local outputDir = config.outputDir or self.tempDir
    local filenamePrefix = config.lang or "audio"

    local audioFile = string.format("%s/%s-%s.wav", outputDir, filenamePrefix, timestamp)
    self._currentAudioFile = audioFile  -- Store temporarily for task completion
    self._currentLang = config.lang  -- Store for event data

    -- Create sox task: sox -q -d output.wav
    self.task = hs.task.new(
      self.soxCmd,
      function(exitCode, stdOut, stdErr)
        -- Task completed (either stopped or error)
        self.task = nil
      end,
      {"-q", "-d", audioFile}
    )

    if not self.task then
      reject("Failed to create sox task")
      return
    end

    -- Start sox
    local ok, err = pcall(function()
      self.task:start()
    end)

    if not ok then
      self.task = nil
      reject("Failed to start sox: " .. tostring(err))
      return
    end

    -- Emit recording started event
    self.eventBus:emit("recording:started", {
      lang = self._currentLang,
    })

    resolve()
  end)
end

--- Stop recording audio
-- @return (Promise): Resolves when recording stops and file is ready
function SoxBackend:stopRecording()
  local Promise = require("lib.promise")

  if not self.task then
    return Promise.reject("Not recording")
  end

  return Promise.new(function(resolve, reject)
    local audioFile = self._currentAudioFile
    local lang = self._currentLang

    -- Terminate sox
    self.task:terminate()
    self.task = nil

    -- Give sox time to flush the file
    hs.timer.doAfter(0.1, function()
      -- Check if file was created
      local attrs = hs.fs.attributes(audioFile)
      if not attrs then
        self:_resetState()

        self.eventBus:emit("recording:error", {
          error = "Recording file was not created",
        })
        reject("Recording file was not created")
        return
      end

      -- Clear state
      self.audioFile = nil
      self.currentLang = nil
      self.startTime = nil

      -- Emit chunk ready event (sox creates one file)
      self.eventBus:emit("audio:chunk_ready", {
        audioFile = audioFile,
        chunkNum = 1,
        lang = lang,
        isFinal = true,
      })

      -- Emit recording stopped event
      self.eventBus:emit("recording:stopped", {})

      resolve()
    end)
  end)
end

--- Reset operational state
function SoxBackend:_resetState()
  self._currentAudioFile = nil
  self._currentLang = nil
end

--- Check if currently recording
-- @return (boolean): true if recording
function SoxBackend:isRecording()
  return self.task ~= nil
end

--- Get backend name
-- @return (string): Backend name
function SoxBackend:getName()
  return "sox"
end

--- Get display text for menubar
-- @param lang (string): Current language
-- @return (string): Display text
function SoxBackend:getDisplayText(lang)
  if not self.startTime then
    return string.format("🎙️ %s", lang)
  end

  local elapsed = os.difftime(os.time(), self.startTime)
  return string.format("🎙️ %ds (%s)", elapsed, lang)
end

return SoxBackend
