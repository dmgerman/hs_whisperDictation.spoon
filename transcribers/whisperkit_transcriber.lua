--- WhisperKitTranscriber - Apple WhisperKit CLI transcription
---
--- Uses Apple's WhisperKit command-line tool (optimized for Apple Silicon).
--- Callback-based architecture (no Promises).
---
--- @module WhisperKitTranscriber

-- Get the spoon directory path from this file's location
local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
local ITranscriber = dofile(spoonPath .. "i_transcriber.lua")

local WhisperKitTranscriber = setmetatable({}, {__index = ITranscriber})
WhisperKitTranscriber.__index = WhisperKitTranscriber

--- Create a new WhisperKitTranscriber instance
---
--- @param config table Configuration options:
---   - executable: Path to whisperkit-cli executable (default: "whisperkit-cli")
---   - model: Model name (default: "large-v3")
--- @return table WhisperKitTranscriber instance
function WhisperKitTranscriber.new(config)
  config = config or {}
  local self = setmetatable({}, WhisperKitTranscriber)

  self.executable = config.executable or "whisperkit-cli"
  self.model = config.model or "large-v3"

  return self
end

--- Validate that whisperkit-cli is available
---
--- Checks if the executable is in PATH and accessible.
---
--- @return boolean success True if transcriber is ready to use
--- @return string|nil error Error message if validation failed
function WhisperKitTranscriber:validate()
  -- Use 'which' to check if executable is in PATH
  local handle = io.popen("which " .. self.executable .. " 2>/dev/null")
  if not handle then
    return false, "Failed to check for " .. self.executable
  end

  local result = handle:read("*a")
  handle:close()

  if not result or result == "" or result:match("not found") then
    return false, self.executable .. " not found. Install: brew install whisperkit-cli"
  end

  return true, nil
end

--- Transcribe an audio file
---
--- Executes whisperkit-cli command asynchronously and returns transcription via callback.
--- The CLI outputs transcription directly to stdout.
---
--- @param audioFile string Path to audio file
--- @param lang string Language code (e.g., "en", "es", "fr")
--- @param onSuccess function Callback with transcribed text: onSuccess(text)
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if transcription started successfully
--- @return string|nil error Error message if failed to start
function WhisperKitTranscriber:transcribe(audioFile, lang, onSuccess, onError)
  -- Validate audio file exists (synchronous precondition)
  local fileAttrs = hs.fs.attributes(audioFile)
  if not fileAttrs then
    return false, "Audio file not found: " .. audioFile
  end

  -- Build whisperkit-cli command
  -- Output goes to stdout
  local cmd = string.format(
    "%s transcribe --model=%s --audio-path='%s' --language=%s 2>&1",
    self.executable,
    self.model,
    audioFile,
    lang
  )

  -- Execute asynchronously (io.popen blocks, so use timer for async pattern)
  hs.timer.doAfter(0.01, function()
    -- Execute whisperkit-cli command
    local handle = io.popen(cmd)
    if not handle then
      if onError then
        onError("Failed to execute whisperkit-cli command")
      end
      return
    end

    local output = handle:read("*a")
    local success, exitType, exitCode = handle:close()

    if not success then
      if onError then
        onError("WhisperKit CLI failed: " .. (output or "unknown error"))
      end
      return
    end

    if not output or output == "" then
      if onError then
        onError("Empty transcription output from WhisperKit")
      end
      return
    end

    -- Trim whitespace
    local text = output:match("^%s*(.-)%s*$") or ""

    if text == "" then
      if onError then
        onError("Empty transcription result after trimming")
      end
      return
    end

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
function WhisperKitTranscriber:getName()
  return "WhisperKit"
end

--- Check if this transcriber supports a given language
---
--- WhisperKit supports all Whisper languages (100+).
---
--- @param lang string Language code
--- @return boolean supported True if language is supported
function WhisperKitTranscriber:supportsLanguage(lang)
  -- WhisperKit supports all Whisper languages
  return true
end

return WhisperKitTranscriber
