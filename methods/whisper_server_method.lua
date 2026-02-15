--- WhisperServerMethod - HTTP server-based transcription
-- Sends audio files to a local/remote whisper server via HTTP POST

local WhisperServerMethod = {}
WhisperServerMethod.__index = WhisperServerMethod

--- Create a new WhisperServerMethod
-- @param config (table): Configuration
--   - host (string): Server host (default: "127.0.0.1")
--   - port (number): Server port (default: 8080)
--   - curlCmd (string): curl command path (default: "curl")
-- @return (WhisperServerMethod): New instance
function WhisperServerMethod.new(config)
  local self = setmetatable({}, WhisperServerMethod)
  self.config = {
    host = config.host or "127.0.0.1",
    port = config.port or 8080,
    curlCmd = config.curlCmd or "curl",
  }
  return self
end

--- Get the name of this transcription method
-- @return (string): Method name
function WhisperServerMethod:getName()
  return "whisper-server"
end

--- Validate method is available and configured
-- @return (boolean, string?): success, error message if failed
function WhisperServerMethod:validate()
  -- Check if curl is available
  local handle = io.popen("which " .. self.config.curlCmd .. " 2>/dev/null")
  if not handle then
    return false, "Failed to check for curl"
  end

  local result = handle:read("*a")
  handle:close()

  if not result or result == "" then
    return false, "curl not found"
  end

  return true
end

--- Check if this method supports a given language
-- @param lang (string): Language code
-- @return (boolean): true if language is supported
function WhisperServerMethod:supportsLanguage(lang)
  -- Whisper server supports all Whisper languages
  return true
end

--- Transcribe an audio file
-- @param audioFile (string): Path to audio file
-- @param lang (string): Language code
-- @return (Promise): Promise that resolves with transcribed text
function WhisperServerMethod:transcribe(audioFile, lang)
  local Promise = require("lib.promise")

  return Promise.new(function(resolve, reject)
    -- Check if audio file exists
    local file = io.open(audioFile, "r")
    if not file then
      reject("Audio file not found: " .. audioFile)
      return
    end
    file:close()

    -- Build server URL
    local serverUrl = string.format(
      "http://%s:%s/inference",
      self.config.host,
      self.config.port
    )

    -- Build curl command
    local cmd = string.format(
      [[%s -s -S -X POST '%s' \
        -F 'file=@%s' \
        -F 'response_format=text' \
        -F 'language=%s' 2>&1]],
      self.config.curlCmd,
      serverUrl,
      audioFile,
      lang
    )

    -- Execute curl request
    local handle = io.popen(cmd)
    if not handle then
      reject("Failed to execute curl command")
      return
    end

    local output = handle:read("*a")
    local success, exitType, exitCode = handle:close()

    if not success then
      reject("curl failed: " .. (output or "unknown error"))
      return
    end

    if not output or output == "" then
      reject("Empty response from server")
      return
    end

    -- Check for server error response (JSON error)
    if output:match('^{"error"') then
      reject("Server error: " .. output)
      return
    end

    -- Post-process: remove leading spaces from each line
    local lines = {}
    for line in output:gmatch("[^\n]+") do
      local trimmed = line:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        table.insert(lines, trimmed)
      end
    end

    local text = table.concat(lines, "\n")

    if text == "" then
      reject("Empty transcription result")
      return
    end

    resolve(text)
  end)
end

return WhisperServerMethod
