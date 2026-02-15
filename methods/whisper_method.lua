--- WhisperMethod - Local whisper.cpp transcription
-- Uses whisper.cpp command-line tool for local transcription

local WhisperMethod = {}
WhisperMethod.__index = WhisperMethod

--- Create a new WhisperMethod
-- @param config (table): Configuration
--   - modelPath (string): Path to whisper model file
--   - executable (string): Whisper executable name (default: "whisper-cpp")
-- @return (WhisperMethod): New instance
function WhisperMethod.new(config)
  local self = setmetatable({}, WhisperMethod)
  self.config = {
    modelPath = config.modelPath,
    executable = config.executable or "whisper-cpp",
  }
  return self
end

--- Get the name of this transcription method
-- @return (string): Method name
function WhisperMethod:getName()
  return "whisper"
end

--- Validate method is available and configured
-- @return (boolean, string?): success, error message if failed
function WhisperMethod:validate()
  -- Check if executable is available
  local handle = io.popen("which " .. self.config.executable .. " 2>/dev/null")
  if not handle then
    return false, "Failed to check for " .. self.config.executable
  end

  local result = handle:read("*a")
  handle:close()

  if not result or result == "" then
    return false, self.config.executable .. " not found. Please install whisper.cpp."
  end

  -- Check if model file exists
  local modelFile = io.open(self.config.modelPath, "r")
  if not modelFile then
    return false, "Model file not found: " .. self.config.modelPath
  end
  modelFile:close()

  return true
end

--- Check if this method supports a given language
-- @param lang (string): Language code
-- @return (boolean): true if language is supported
function WhisperMethod:supportsLanguage(lang)
  -- Whisper supports 100+ languages, so we'll accept all
  return true
end

--- Transcribe an audio file
-- @param audioFile (string): Path to audio file
-- @param lang (string): Language code
-- @return (Promise): Promise that resolves with transcribed text
function WhisperMethod:transcribe(audioFile, lang)
  local Promise = require("lib.promise")

  return Promise.new(function(resolve, reject)
    -- Check if audio file exists
    local file = io.open(audioFile, "r")
    if not file then
      reject("Audio file not found: " .. audioFile)
      return
    end
    file:close()

    -- Build whisper command
    local cmd = string.format(
      "%s -m %s -l %s -f %s --output-txt 2>&1",
      self.config.executable,
      self.config.modelPath,
      lang,
      audioFile
    )

    -- Execute whisper
    local handle = io.popen(cmd)
    if not handle then
      reject("Failed to execute whisper command")
      return
    end

    local output = handle:read("*a")
    local success, exitType, exitCode = handle:close()

    if not success then
      reject("Whisper failed: " .. (output or "unknown error"))
      return
    end

    -- Read transcription from output file
    -- whisper.cpp writes to <audiofile>.txt
    local txtFile = audioFile .. ".txt"
    local transcriptHandle = io.open(txtFile, "r")
    if not transcriptHandle then
      reject("Failed to read transcription output")
      return
    end

    local text = transcriptHandle:read("*a")
    transcriptHandle:close()

    -- Clean up output file
    os.remove(txtFile)

    -- Trim whitespace
    text = text:match("^%s*(.-)%s*$")

    resolve(text)
  end)
end

return WhisperMethod
