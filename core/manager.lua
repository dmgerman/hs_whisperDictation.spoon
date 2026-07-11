--- Manager - Core state machine for WhisperDictation v2 architecture
---
--- Manages the recording and transcription workflow with explicit state tracking
--- and minimal dependencies. Uses direct callbacks instead of EventBus/Promises.
---
--- @module Manager

-- Get the spoon directory path from this file's location
local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
local Notifier = dofile(spoonPath .. "../lib/notifier.lua")
local Loggers = dofile(spoonPath .. "../lib/loggers.lua")

local logger = Loggers.new("WhisperManager")

local Manager = {}
Manager.__index = Manager

-- State constants
Manager.STATES = {
  IDLE = "IDLE",
  RECORDING = "RECORDING",
  TRANSCRIBING = "TRANSCRIBING",
  ERROR = "ERROR",
}

-- If the first chunk's peak amplitude (float in [0, 1]) is below this,
-- the microphone is delivering silence and we abort the session instead
-- of wasting a transcriber round-trip and returning empty text. Working
-- mics in a quiet room floor around 0.005; a muted / off / permission-
-- denied device delivers ~0. 0.001 catches "no audio at all" without
-- flagging a genuinely quiet speaker. Only checked on chunk 1 — later
-- chunks may legitimately contain silence between phrases.
Manager.FIRST_CHUNK_SILENCE_PEAK = 0.001

-- Valid state transitions
local VALID_TRANSITIONS = {
  IDLE = { RECORDING = true, ERROR = true },
  RECORDING = { TRANSCRIBING = true, IDLE = true, ERROR = true },
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
  self._recorderDone = false  -- Set by _onRecordingComplete callback
  self.currentLanguage = nil

  -- Track chunk errors for timeout/missing chunks
  self._chunkErrors = {}

  -- Callbacks for UI integration
  self.onStateChanged = nil  -- function(newState, oldState, context)
  self.onTextReady = nil  -- function(finalText) called with assembled text before clipboard

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
    self._recorderDone = false
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
  -- peak is optional (only StreamingRecorder emits it). nil is treated as
  -- "unknown" by _onChunkReceived and the first-chunk gate is skipped.
  local success, recorderErr = self.recorder:startRecording(
    recordingConfig,
    function(audioFile, chunkNum, isFinal, peak)
      self:_onChunkReceived(audioFile, chunkNum, isFinal, peak)
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
  Notifier.show("recording", "debug", "Recording started")

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
  Notifier.show("recording", "debug", "Recording stopped, transcribing...")

  -- Check completion now that we're in TRANSCRIBING state.
  -- The recorder's onComplete callback may have already fired (setting
  -- _recorderDone=true) and been deferred because we were in RECORDING.
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

--- Abort current recording or transcription and return to IDLE.
--- Can be called from any non-IDLE state.
---
--- @return boolean success True if aborted
--- @return string|nil error Error message if nothing to abort
function Manager:abort()
  if self.state == Manager.STATES.IDLE then
    return false, "Nothing to abort"
  end

  local fromState = self.state
  Notifier.show("recording", "info", "Aborted (" .. fromState .. ")")

  -- Stop recorder if still recording
  if self.state == Manager.STATES.RECORDING and self.recorder then
    pcall(function()
      self.recorder:stopRecording(function() end, function() end)
    end)
  end

  -- Transition to IDLE (clears all tracking state via _onStateEntered)
  self:transitionTo(Manager.STATES.IDLE, "abort")
  return true, nil
end

--- Get current state
---
--- @return string state Current state
function Manager:getState()
  return self.state
end

--- Callback invoked when recording completes
function Manager:_onRecordingComplete()
  -- Ignore if aborted (state reset to IDLE)
  if self.state == Manager.STATES.IDLE then return end

  Notifier.show("recording", "debug", "Recording complete callback received")
  self._recorderDone = true
  self:_checkIfComplete()
end

--- Describe the audio input device currently in use.
---
--- Prefers the recorder's explicit device config, then the system default.
--- Returns "unknown" if neither is resolvable — the abort message is still
--- useful without a device name, so this must never throw.
---
--- @return string Human-readable device description
function Manager:_describeAudioInput()
  if self.recorder and self.recorder.audioInputDevice then
    return self.recorder.audioInputDevice
  end
  if hs and hs.audiodevice and hs.audiodevice.defaultInputDevice then
    local ok, dev = pcall(hs.audiodevice.defaultInputDevice)
    if ok and dev and dev.name then
      return dev:name() .. " (system default)"
    end
  end
  return "unknown"
end

--- Build the alert message for a silent first chunk.
---
--- The two cases are distinguished by whether the peak is bit-exact zero
--- or merely near-zero. On macOS a process without microphone permission
--- gets samples silently replaced with 0.0 (no error, no warning); a
--- muted or disconnected device that IS producing samples still yields a
--- tiny noise floor. This is a heuristic — the wording says so explicitly.
---
--- @param peak number Peak amplitude of the first chunk in [0, 1]
--- @return string Multi-line alert / console message
function Manager:_buildSilentChunkMessage(peak)
  local device = self:_describeAudioInput()
  local reason
  if peak == 0 then
    reason = "Likely cause: macOS microphone permission denied for the recording " ..
      "process, or the input device is disconnected. Check System Settings → " ..
      "Privacy & Security → Microphone."
  else
    reason = "Likely cause: microphone muted, gain at zero, or device powered off. " ..
      "The device is producing samples but no signal."
  end
  return string.format(
    "No audio in first chunk (peak=%.5f, device=\"%s\"). %s",
    peak, device, reason
  )
end

--- Callback invoked when a chunk is received from recorder
---
--- @param audioFile string Path to audio file
--- @param chunkNum number Chunk number (1-indexed)
--- @param isFinal boolean True if this is the last chunk
--- @param peak number|nil Peak amplitude in [0, 1] if the recorder reports it
function Manager:_onChunkReceived(audioFile, chunkNum, isFinal, peak)
  -- Ignore chunks after abort (state reset to IDLE)
  if self.state == Manager.STATES.IDLE then return end

  Notifier.show("transcription", "debug", string.format(
    "Chunk received: #%d (final: %s, peak: %s, file: %s)",
    chunkNum, tostring(isFinal), tostring(peak), audioFile
  ))

  -- First-chunk silence gate: if the recorder can tell us the amplitude
  -- and the very first chunk is essentially silent, abort now rather than
  -- transcribing empty audio and letting the user keep talking into a
  -- muted / off / permission-denied microphone. Later chunks are not
  -- gated because a legitimate silence between phrases is fine.
  if chunkNum == 1 and peak ~= nil and peak < Manager.FIRST_CHUNK_SILENCE_PEAK then
    local msg = self:_buildSilentChunkMessage(peak)
    Notifier.show("recording", "error", msg)  -- alert + logs at error level
    self:abort()
    return
  end

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
    "Completion check: recorderDone=%s, pending=%d, state=%s",
    tostring(self._recorderDone), self.pendingTranscriptions, self.state
  ))

  -- Don't finalize from RECORDING — stopRecording() will transition
  -- to TRANSCRIBING first, then _checkIfComplete runs again from there
  if self.state == Manager.STATES.RECORDING then
    return
  end

  if self._recorderDone and self.pendingTranscriptions == 0 then
    -- All done - assemble and finalize
    self:_finalize()
  end
end

--- Finalize the session - assemble results and deliver text
function Manager:_finalize()
  -- Assemble results
  local finalText = self:_assembleResults()

  -- Deliver text via callback (supports async filtering) then transition to IDLE.
  -- IDLE transition must happen AFTER the callback completes, because
  -- onStateChanged triggers auto-paste which needs the clipboard set first.
  local function transitionToIdle()
    if self.state == Manager.STATES.TRANSCRIBING or self.state == Manager.STATES.ERROR then
      self:transitionTo(Manager.STATES.IDLE, "finalize")
    end
  end

  if self.onTextReady then
    self.onTextReady(finalText, transitionToIdle)
  else
    if hs and hs.pasteboard then
      hs.pasteboard.setContents(finalText)
      Notifier.show("transcription", "debug", "Transcription complete! Copied to clipboard.")
    else
      Notifier.show("transcription", "debug", "Transcription complete: " .. finalText)
    end
    transitionToIdle()
  end
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
