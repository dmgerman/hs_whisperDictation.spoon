--- GroqMethod - Groq API remote transcription
-- Uses Groq's Whisper API for fast, accurate transcription

local GroqMethod = {}
GroqMethod.__index = GroqMethod

--- Create a new GroqMethod
-- @param config (table): Configuration
--   - apiKey (string): Groq API key
--   - model (string): Model name (default: "whisper-large-v3")
--   - timeout (number): Request timeout in seconds (default: 30)
-- @return (GroqMethod): New instance
function GroqMethod.new(config)
  local self = setmetatable({}, GroqMethod)
  self.config = {
    apiKey = config.apiKey,
    model = config.model or "whisper-large-v3",
    timeout = config.timeout or 30,
    apiUrl = "https://api.groq.com/openai/v1/audio/transcriptions",
  }
  return self
end

--- Get the name of this transcription method
-- @return (string): Method name
function GroqMethod:getName()
  return "groq"
end

--- Validate method is available and configured
-- @return (boolean, string?): success, error message if failed
function GroqMethod:validate()
  -- Check if API key is configured
  if not self.config.apiKey or self.config.apiKey == "" then
    return false, "Groq API key not configured"
  end

  -- Check if curl is available
  local handle = io.popen("which curl 2>/dev/null")
  if not handle then
    return false, "Failed to check for curl command"
  end

  local result = handle:read("*a")
  handle:close()

  if not result or result == "" then
    return false, "curl not found. Please install curl."
  end

  return true
end

--- Check if this method supports a given language
-- @param lang (string): Language code
-- @return (boolean): true if language is supported
function GroqMethod:supportsLanguage(lang)
  -- Groq's Whisper supports 100+ languages
  return true
end

--- Transcribe an audio file
-- @param audioFile (string): Path to audio file
-- @param lang (string): Language code
-- @return (Promise): Promise that resolves with transcribed text
function GroqMethod:transcribe(audioFile, lang)
  local Promise = require("lib.promise")

  return Promise.new(function(resolve, reject)
    -- Check if audio file exists
    local file = io.open(audioFile, "r")
    if not file then
      reject("Audio file not found: " .. audioFile)
      return
    end
    file:close()

    -- Build curl command for Groq API
    local cmd = string.format(
      [[curl -s -S --max-time %d -X POST '%s' \
        -H 'Authorization: Bearer %s' \
        -F 'file=@%s' \
        -F 'model=%s' \
        -F 'language=%s' \
        -F 'response_format=json' 2>&1]],
      self.config.timeout,
      self.config.apiUrl,
      self.config.apiKey,
      audioFile,
      self.config.model,
      lang
    )

    -- Execute API request
    local handle = io.popen(cmd)
    if not handle then
      reject("Failed to execute curl command")
      return
    end

    local output = handle:read("*a")
    local success, exitType, exitCode = handle:close()

    if not success then
      reject("API request failed: " .. (output or "unknown error"))
      return
    end

    -- Parse JSON response
    local text = self:_parseResponse(output)
    if not text then
      reject("Failed to parse API response: " .. output)
      return
    end

    resolve(text)
  end)
end

--- Parse Groq API JSON response
-- @private
-- @param json (string): JSON response
-- @return (string?): Transcribed text or nil if parsing failed
function GroqMethod:_parseResponse(json)
  -- Simple JSON parsing for "text" field
  -- In production, use a proper JSON library
  local text = json:match('"text"%s*:%s*"([^"]*)"')
  if text then
    -- Unescape JSON string
    text = text:gsub("\\n", "\n")
    text = text:gsub("\\t", "\t")
    text = text:gsub('\\"', '"')
    text = text:gsub("\\\\", "\\")
  end
  return text
end

return GroqMethod
