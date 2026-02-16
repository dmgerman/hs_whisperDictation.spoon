--- WhisperCLITranscriber - Local whisper.cpp command-line transcription
---
--- Uses whisper.cpp CLI tool for local audio transcription.
--- Callback-based architecture (no Promises).
---
--- @module WhisperCLITranscriber

-- Get the spoon directory path from this file's location
local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
local ITranscriber = dofile(spoonPath .. "i_transcriber.lua")

local WhisperCLITranscriber = setmetatable({}, {__index = ITranscriber})
WhisperCLITranscriber.__index = WhisperCLITranscriber

--- Create a new WhisperCLITranscriber instance
---
--- @param config table Configuration options:
---   - executable: Path to whisper executable (default: "whisper-cpp")
---   - modelPath: Path to whisper model file (required)
--- @return table WhisperCLITranscriber instance
function WhisperCLITranscriber.new(config)
  config = config or {}
  local self = setmetatable({}, WhisperCLITranscriber)

  self.executable = config.executable or "whisper-cpp"
  self.modelPath = config.modelPath

  return self
end

--- Validate that whisper-cpp and model are available
---
--- @return boolean success True if transcriber is ready to use
--- @return string|nil error Error message if validation failed
function WhisperCLITranscriber:validate()
  -- Check if executable exists
  local execAttrs = hs.fs.attributes(self.executable)
  if not execAttrs then
    return false, "Whisper executable not found: " .. self.executable
  end

  -- Check if model file exists
  if not self.modelPath then
    return false, "Model path not configured"
  end

  local modelAttrs = hs.fs.attributes(self.modelPath)
  if not modelAttrs then
    return false, "Model file not found: " .. self.modelPath
  end

  return true, nil
end

--- Transcribe an audio file
---
--- @param audioFile string Path to audio file
--- @param lang string Language code (e.g., "en", "es", "fr")
--- @param onSuccess function Callback with transcribed text: onSuccess(text)
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if transcription started successfully
--- @return string|nil error Error message if failed to start
function WhisperCLITranscriber:transcribe(audioFile, lang, onSuccess, onError)
  -- Validate audio file exists (synchronous precondition)
  local fileAttrs = hs.fs.attributes(audioFile)
  if not fileAttrs then
    return false, "Audio file not found: " .. audioFile
  end

  -- Build whisper command
  -- whisper-cli creates output as <audioFile>.txt (appends .txt to full filename)
  local cmd = string.format(
    "%s -np -m %s -l %s --output-txt '%s' 2>&1",
    self.executable,
    self.modelPath,
    lang,
    audioFile
  )

  -- Execute asynchronously (io.popen blocks, so use timer for async pattern)
  hs.timer.doAfter(0.01, function()
    -- Execute whisper command
    local handle = io.popen(cmd)
    if not handle then
      if onError then
        onError("Failed to execute whisper command")
      end
      return
    end

    local output = handle:read("*a")
    local success, exitType, exitCode = handle:close()

    if not success then
      if onError then
        onError("Whisper command failed: " .. (output or "unknown error"))
      end
      return
    end

    -- Read transcription from output file
    -- whisper-cli writes to <audioFile>.txt (appends .txt to full filename)
    local txtFile = audioFile .. ".txt"
    local transcriptHandle = io.open(txtFile, "r")
    if not transcriptHandle then
      if onError then
        onError("Failed to read transcription output file: " .. txtFile)
      end
      return
    end

    local text = transcriptHandle:read("*a")
    transcriptHandle:close()

    -- Clean up output file
    os.remove(txtFile)

    -- Trim whitespace
    text = text:match("^%s*(.-)%s*$") or ""

    -- Success!
    if onSuccess then
      onSuccess(text)
    end
  end)

  return true, nil  -- Transcription started successfully
end

--- Get the name of this transcriber
---
--- @return string name Transcriber name
function WhisperCLITranscriber:getName()
  return "WhisperCLI"
end

--- Check if this transcriber supports a given language
---
--- Whisper supports 100+ languages, so we accept all language codes.
---
--- @param lang string Language code
--- @return boolean supported True if language is supported
function WhisperCLITranscriber:supportsLanguage(lang)
  -- Whisper supports 100+ languages
  return true
end

return WhisperCLITranscriber
