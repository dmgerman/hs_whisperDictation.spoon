--- SoxRecorder - Simple sox-based audio recording
---
--- Records a single audio file using sox, emits chunk via callback when stopped.
--- Callback-based architecture (no Promises or EventBus).
---
--- @module SoxRecorder

-- Get the spoon directory path from this file's location
local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
local IRecorder = dofile(spoonPath .. "i_recorder.lua")

local SoxRecorder = setmetatable({}, {__index = IRecorder})
SoxRecorder.__index = SoxRecorder

--- Create a new SoxRecorder instance
---
--- @param config table Configuration {soxCmd, tempDir, audioInputDevice}
---   - soxCmd: Path to sox executable (default: "/opt/homebrew/bin/sox")
---   - tempDir: Directory for audio files (default: "/tmp/whisper_dict")
---   - audioInputDevice: Audio input device name (default: nil = system default)
---                       Examples: "BlackHole 2ch", "Built-in Microphone"
--- @return table SoxRecorder instance
function SoxRecorder.new(config)
  config = config or {}
  local self = setmetatable({}, SoxRecorder)

  self.soxCmd = config.soxCmd or "/opt/homebrew/bin/sox"
  self.tempDir = config.tempDir or "/tmp/whisper_dict"
  self.audioInputDevice = config.audioInputDevice  -- nil = default device

  -- Operational state only (NOT recording state - that's in Manager)
  self.task = nil  -- hs.task object when recording
  self._isRecording = false  -- Explicit recording flag (more robust than checking task ~= nil)
  self._currentAudioFile = nil  -- Temporary for task completion
  self._onChunk = nil  -- Stored callback
  self._onError = nil  -- Stored error callback

  return self
end

--- Validate sox command is available
---
--- @return boolean success True if sox exists
--- @return string|nil error Error message if validation failed
function SoxRecorder:validate()
  local attrs = hs.fs.attributes(self.soxCmd)
  if attrs then
    return true, nil
  else
    return false, "sox not found at: " .. self.soxCmd
  end
end

--- Start recording audio
---
--- @param config table Configuration {outputDir, lang}
---   - outputDir: Directory for audio files (required)
---   - lang: Language code for filename prefix (required)
--- @param onChunk function Callback when chunk ready: onChunk(audioFile, chunkNum, isFinal)
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if recording started successfully
--- @return string|nil error Error message if failed to start
function SoxRecorder:startRecording(config, onChunk, onError)
  if self._isRecording then
    return false, "Already recording"
  end

  -- Generate timestamped filename
  local timestamp = os.date("%Y%m%d-%H%M%S")
  local outputDir = config.outputDir or self.tempDir
  local filenamePrefix = config.lang or "audio"

  local audioFile = string.format("%s/%s-%s.wav", outputDir, filenamePrefix, timestamp)

  -- Store for later use in stopRecording
  self._currentAudioFile = audioFile
  self._onChunk = onChunk
  self._onError = onError

  -- Build sox arguments based on audio input device
  local soxArgs
  if self.audioInputDevice then
    -- Use specified device: sox -q -t coreaudio "device name" output.wav
    soxArgs = {"-q", "-t", "coreaudio", self.audioInputDevice, audioFile}
  else
    -- Use default device: sox -q -d output.wav
    soxArgs = {"-q", "-d", audioFile}
  end

  -- Create sox task
  self.task = hs.task.new(
    self.soxCmd,
    function(exitCode, stdOut, stdErr)
      -- Task completed (either stopped or error)
      -- Just cleanup task reference - don't change _isRecording
      -- (_isRecording is managed explicitly in start/stop methods)
      self.task = nil
    end,
    soxArgs
  )

  if not self.task then
    self:_resetState()
    return false, "Failed to create sox task"
  end

  -- Start sox
  local ok, err = pcall(function()
    self.task:start()
  end)

  if not ok then
    self.task = nil
    self:_resetState()
    return false, "Failed to start sox: " .. tostring(err)
  end

  -- Set recording flag after successful start
  self._isRecording = true

  return true, nil
end

--- Stop recording audio
---
--- @param onComplete function Callback when stop completes: onComplete()
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if stop initiated successfully
--- @return string|nil error Error message if failed to stop
function SoxRecorder:stopRecording(onComplete, onError)
  if not self._isRecording then
    return false, "Not recording"
  end

  local audioFile = self._currentAudioFile
  local onChunk = self._onChunk

  -- Terminate sox (only if task still exists)
  if self.task then
    self.task:terminate()
    self.task = nil
  end
  self._isRecording = false

  -- Give sox time to flush the file
  hs.timer.doAfter(0.1, function()
    -- Check if file was created
    local attrs = hs.fs.attributes(audioFile)
    if not attrs then
      self:_resetState()
      if onError then
        onError("Recording file was not created")
      end
      return
    end

    -- Clear state before emitting chunk
    self:_resetState()

    -- Emit single chunk (chunkNum=1, isFinal=true)
    if onChunk then
      onChunk(audioFile, 1, true)
    end

    if onComplete then
      onComplete()
    end
  end)

  return true, nil
end

--- Reset operational state
function SoxRecorder:_resetState()
  self._currentAudioFile = nil
  self._onChunk = nil
  self._onError = nil
  self._isRecording = false
end

--- Check if currently recording
---
--- @return boolean recording True if recording
function SoxRecorder:isRecording()
  return self._isRecording
end

--- Get recorder name
---
--- @return string name Recorder name
function SoxRecorder:getName()
  return "sox"
end

return SoxRecorder
