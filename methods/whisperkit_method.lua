--- WhisperKitMethod - Apple WhisperKit CLI transcription
-- Uses Apple's WhisperKit command-line tool (optimized for Apple Silicon)

local WhisperKitMethod = {}
WhisperKitMethod.__index = WhisperKitMethod

--- Create a new WhisperKitMethod
-- @param config (table): Configuration
--   - executable (string): WhisperKit CLI executable (default: "whisperkit-cli")
--   - model (string): Model name (default: "large-v3")
-- @return (WhisperKitMethod): New instance
function WhisperKitMethod.new(config)
  local self = setmetatable({}, WhisperKitMethod)
  self.config = {
    executable = config.executable or "whisperkit-cli",
    model = config.model or "large-v3",
  }
  return self
end

--- Get the name of this transcription method
-- @return (string): Method name
function WhisperKitMethod:getName()
  return "whisperkit"
end

--- Validate method is available and configured
-- @return (boolean, string?): success, error message if failed
function WhisperKitMethod:validate()
  -- Check if executable is available
  local handle = io.popen("which " .. self.config.executable .. " 2>/dev/null")
  if not handle then
    return false, "Failed to check for " .. self.config.executable
  end

  local result = handle:read("*a")
  handle:close()

  if not result or result == "" then
    return false, self.config.executable .. " not found. Install: brew install whisperkit-cli"
  end

  return true
end

--- Check if this method supports a given language
-- @param lang (string): Language code
-- @return (boolean): true if language is supported
function WhisperKitMethod:supportsLanguage(lang)
  -- WhisperKit supports all Whisper languages
  return true
end

--- Transcribe an audio file
-- @param audioFile (string): Path to audio file
-- @param lang (string): Language code
-- @return (Promise): Promise that resolves with transcribed text
function WhisperKitMethod:transcribe(audioFile, lang)
  local Promise = require("lib.promise")

  return Promise.new(function(resolve, reject)
    -- Check if audio file exists
    local file = io.open(audioFile, "r")
    if not file then
      reject("Audio file not found: " .. audioFile)
      return
    end
    file:close()

    -- Build whisperkit-cli command
    local cmd = string.format(
      "%s transcribe --model=%s --audio-path=%s --language=%s 2>&1",
      self.config.executable,
      self.config.model,
      audioFile,
      lang
    )

    -- Execute whisperkit-cli (outputs to stdout)
    local handle = io.popen(cmd)
    if not handle then
      reject("Failed to execute whisperkit-cli command")
      return
    end

    local output = handle:read("*a")
    local success, exitType, exitCode = handle:close()

    if not success then
      reject("WhisperKit CLI failed: " .. (output or "unknown error"))
      return
    end

    if not output or output == "" then
      reject("Empty transcription output")
      return
    end

    -- Trim whitespace
    output = output:match("^%s*(.-)%s*$")

    resolve(output)
  end)
end

return WhisperKitMethod
