--- Manager - Core state machine for WhisperDictation v2 architecture
---
--- Manages the recording and transcription workflow with explicit state tracking
--- and minimal dependencies. Uses direct callbacks instead of EventBus/Promises.
---
--- @module Manager

-- Get the spoon directory path from this file's location
local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
local Notifier = dofile(spoonPath .. "../lib/notifier.lua")

local Manager = {}
Manager.__index = Manager

-- State constants
Manager.STATES = {
  IDLE = "IDLE",
  RECORDING = "RECORDING",
  TRANSCRIBING = "TRANSCRIBING",
  ERROR = "ERROR",
}

-- Valid state transitions
local VALID_TRANSITIONS = {
  IDLE = { RECORDING = true, ERROR = true },
  RECORDING = { TRANSCRIBING = true, ERROR = true },
  TRANSCRIBING = { IDLE = true, ERROR = true },
  ERROR = { IDLE = true },
}

--- Create a new Manager instance
---
--- @param recorder table IRecorder implementation
--- @param transcriber table ITranscriber implementation
--- @param config table Configuration (shared reference, treated as readonly)
---   - language: Default language code (e.g., "en")
---   - tempDir: Temporary directory for audio files
--- @return table Manager instance
function Manager.new(recorder, transcriber, config)
  local self = setmetatable({}, Manager)

  self.recorder = recorder
  self.transcriber = transcriber
  self.config = config

  -- State machine
  self.state = Manager.STATES.IDLE

  -- Minimal tracking
  self.pendingTranscriptions = 0
  self.results = {}  -- Array indexed by chunkNum
  self.recordingComplete = false
  self.currentLanguage = nil

  -- Track chunk errors for timeout/missing chunks
  self._chunkErrors = {}

  -- Callbacks for UI integration
  self.onStateChanged = nil  -- function(newState, oldState, context)

  return self
end

--- Transition to a new state
---
--- @param newState string Target state (use Manager.STATES constants)
--- @param context string|nil Optional context for logging
--- @return boolean success True if transition succeeded
--- @return string|nil error Error message if transition invalid
function Manager:transitionTo(newState, context)
  local currentState = self.state

  -- Validate transition
  local validTransitions = VALID_TRANSITIONS[currentState]
  if not validTransitions or not validTransitions[newState] then
    local msg = string.format(
      "Invalid state transition: %s -> %s (context: %s)",
      currentState, newState, context or "none"
    )
    Notifier.show("recording", "error", msg)
    return false, msg
  end

  -- Log transition (debug level - logged but not shown)
  Notifier.show("recording", "debug", string.format(
    "State transition: %s -> %s (context: %s)",
    currentState, newState, context or "none"
  ))

  self.state = newState

  -- Call state entry handler
  self:_onStateEntered(newState, context)

  -- Notify UI of state change
  if self.onStateChanged then
    self.onStateChanged(newState, currentState, context)
  end

  return true, nil
end

--- State entry handler
---
--- @param state string The state that was entered
--- @param context string|nil Optional context
function Manager:_onStateEntered(state, context)
  if state == Manager.STATES.IDLE then
    -- Reset tracking when entering IDLE
    self.pendingTranscriptions = 0
    self.results = {}
    self.recordingComplete = false
    self.currentLanguage = nil
    self._chunkErrors = {}
  end
end

--- Start recording
---
--- @param lang string Language code (e.g., "en", "es")
--- @return boolean success True if recording started
--- @return string|nil error Error message if failed
function Manager:startRecording(lang)
  -- Validate state
  if self.state ~= Manager.STATES.IDLE then
    -- Auto-reset from ERROR state
    if self.state == Manager.STATES.ERROR then
      Notifier.show("recording", "info", "Recovering from error state")
      self:transitionTo(Manager.STATES.IDLE, "auto-reset")
    else
      local msg = "Cannot start recording: not in IDLE state (current: " .. self.state .. ")"
      Notifier.show("recording", "warning", msg)
      return false, msg
    end
  end

  -- Validate language
  if not lang or type(lang) ~= "string" then
    local msg = "Invalid language: must be a non-empty string"
    Notifier.show("recording", "error", msg)
    self:transitionTo(Manager.STATES.ERROR, "invalid-language")
    return false, msg
  end

  -- Store language
  self.currentLanguage = lang

  -- Transition to RECORDING
  local ok, err = self:transitionTo(Manager.STATES.RECORDING, "start-recording")
  if not ok then
    return false, err
  end

  -- Prepare recording config
  local recordingConfig = {
    outputDir = self.config.tempDir or "/tmp",
    lang = lang,
  }

  -- Start recorder with callbacks
  local success, recorderErr = self.recorder:startRecording(
    recordingConfig,
    function(audioFile, chunkNum, isFinal)
      self:_onChunkReceived(audioFile, chunkNum, isFinal)
    end,
    function(errorMsg)
      self:_onRecordingError(errorMsg)
    end
  )

  if not success then
    local msg = "Failed to start recording: " .. (recorderErr or "unknown error")
    Notifier.show("recording", "error", msg)
    self:transitionTo(Manager.STATES.ERROR, "recorder-start-failed")
    return false, msg
  end

  -- Show feedback
  Notifier.show("recording", "info", "Recording started")

  return true, nil
end

--- Stop recording
---
--- @return boolean success True if stop initiated
--- @return string|nil error Error message if failed
function Manager:stopRecording()
  -- Validate state
  if self.state ~= Manager.STATES.RECORDING then
    local msg = "Cannot stop recording: not in RECORDING state (current: " .. self.state .. ")"
    Notifier.show("recording", "warning", msg)
    return false, msg
  end

  -- Mark recording as complete
  self.recordingComplete = true

  -- Stop recorder
  local success, recorderErr = self.recorder:stopRecording(
    function()
      self:_onRecordingComplete()
    end,
    function(errorMsg)
      self:_onRecordingError(errorMsg)
    end
  )

  if not success then
    local msg = "Failed to stop recording: " .. (recorderErr or "unknown error")
    Notifier.show("recording", "error", msg)
    self:transitionTo(Manager.STATES.ERROR, "recorder-stop-failed")
    return false, msg
  end

  -- Transition to TRANSCRIBING
  local ok, err = self:transitionTo(Manager.STATES.TRANSCRIBING, "stop-recording")
  if not ok then
    return false, err
  end

  -- Show feedback
  Notifier.show("recording", "info", "Recording stopped, transcribing...")

  -- Check if already complete (for StreamingRecorder where chunks emit during recording)
  -- For SoxRecorder, chunks emit in _onRecordingComplete() callback, so pending > 0
  -- For StreamingRecorder, chunks may already be transcribed, so pending might be 0
  self:_checkIfComplete()

  return true, nil
end

--- Reset from ERROR state to IDLE
---
--- @return boolean success True if reset succeeded
--- @return string|nil error Error message if failed
function Manager:reset()
  if self.state ~= Manager.STATES.ERROR then
    local msg = "Reset only available from ERROR state (current: " .. self.state .. ")"
    return false, msg
  end

  return self:transitionTo(Manager.STATES.IDLE, "manual-reset")
end

--- Get current state
---
--- @return string state Current state
function Manager:getState()
  return self.state
end

--- Callback invoked when recording completes
function Manager:_onRecordingComplete()
  Notifier.show("recording", "debug", "Recording complete callback received")
  -- Check if all transcriptions are done
  self:_checkIfComplete()
end

--- Callback invoked when a chunk is received from recorder
---
--- @param audioFile string Path to audio file
--- @param chunkNum number Chunk number (1-indexed)
--- @param isFinal boolean True if this is the last chunk
function Manager:_onChunkReceived(audioFile, chunkNum, isFinal)
  Notifier.show("transcription", "debug", string.format(
    "Chunk received: #%d (final: %s, file: %s)",
    chunkNum, tostring(isFinal), audioFile
  ))

  -- Increment pending counter
  self.pendingTranscriptions = self.pendingTranscriptions + 1

  -- Start async transcription
  local success, err = self.transcriber:transcribe(
    audioFile,
    self.currentLanguage,
    function(text)
      self:_onTranscriptionSuccess(chunkNum, text)
    end,
    function(errorMsg)
      self:_onTranscriptionError(chunkNum, errorMsg)
    end
  )

  if not success then
    -- Synchronous failure (e.g., file not found)
    self:_onTranscriptionError(chunkNum, err or "Failed to start transcription")
  end
end

--- Callback invoked when transcription succeeds
---
--- @param chunkNum number Chunk number
--- @param text string Transcribed text
function Manager:_onTranscriptionSuccess(chunkNum, text)
  Notifier.show("transcription", "debug", string.format(
    "Chunk #%d transcribed successfully: %s",
    chunkNum, text
  ))

  -- Store result
  self.results[chunkNum] = text

  -- Decrement pending counter
  self.pendingTranscriptions = self.pendingTranscriptions - 1

  -- Show per-chunk feedback
  Notifier.show("transcription", "info", string.format(
    "Chunk %d: %s",
    chunkNum, text
  ))

  -- Check if complete
  self:_checkIfComplete()
end

--- Callback invoked when transcription fails
---
--- @param chunkNum number Chunk number
--- @param errorMsg string Error message
function Manager:_onTranscriptionError(chunkNum, errorMsg)
  Notifier.show("transcription", "warning", string.format(
    "Chunk #%d transcription failed: %s",
    chunkNum, errorMsg
  ))

  -- Store error placeholder
  self.results[chunkNum] = string.format("[chunk %d: error - %s]", chunkNum, errorMsg)

  -- Decrement pending counter
  self.pendingTranscriptions = self.pendingTranscriptions - 1

  -- Check if complete (graceful degradation - continue with partial results)
  self:_checkIfComplete()
end

--- Callback invoked when recording error occurs
---
--- @param errorMsg string Error message
function Manager:_onRecordingError(errorMsg)
  local msg = "Recording error: " .. errorMsg
  Notifier.show("recording", "error", msg)

  -- Transition to ERROR state
  self:transitionTo(Manager.STATES.ERROR, "recording-error")
end

--- Check if recording and all transcriptions are complete
function Manager:_checkIfComplete()
  Notifier.show("transcription", "debug", string.format(
    "Completion check: recordingComplete=%s, pending=%d",
    tostring(self.recordingComplete), self.pendingTranscriptions
  ))

  if self.recordingComplete and self.pendingTranscriptions == 0 then
    -- All done - assemble and finalize
    self:_finalize()
  end
end

--- Finalize the session - assemble results and copy to clipboard
function Manager:_finalize()
  -- Assemble results
  local finalText = self:_assembleResults()

  -- Copy to clipboard
  if hs and hs.pasteboard then
    hs.pasteboard.setContents(finalText)
    Notifier.show("transcription", "info", "Transcription complete! Copied to clipboard.")
  else
    -- Fallback for testing
    Notifier.show("transcription", "info", "Transcription complete: " .. finalText)
  end

  -- Transition back to IDLE (only if in valid state)
  -- RECORDING -> IDLE is invalid (stopRecording will handle transition to TRANSCRIBING)
  -- TRANSCRIBING -> IDLE is valid
  -- ERROR -> IDLE is valid
  if self.state == Manager.STATES.TRANSCRIBING or self.state == Manager.STATES.ERROR then
    self:transitionTo(Manager.STATES.IDLE, "finalize")
  end
  -- If still in RECORDING state, don't transition - stopRecording() will handle it
end

--- Assemble results from all chunks
---
--- @return string finalText Concatenated transcription text
function Manager:_assembleResults()
  local parts = {}

  -- Find max chunk number to handle gaps
  local maxChunk = 0
  for chunkNum, _ in pairs(self.results) do
    if chunkNum > maxChunk then
      maxChunk = chunkNum
    end
  end

  -- Concatenate results in order
  for i = 1, maxChunk do
    local text = self.results[i]
    if text then
      table.insert(parts, text)
    else
      -- Handle missing chunk (should be rare with error handling)
      table.insert(parts, string.format("[chunk %d: missing]", i))
    end
  end

  -- Join with double newlines
  return table.concat(parts, "\n\n")
end

return Manager
