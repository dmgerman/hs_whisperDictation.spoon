--- WhisperServerTranscriber - HTTP server-based transcription
---
--- Sends audio files to a local/remote whisper server via HTTP POST.
--- Callback-based architecture (no Promises).
---
--- @module WhisperServerTranscriber

-- Get the spoon directory path from this file's location
local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
local ITranscriber = dofile(spoonPath .. "i_transcriber.lua")

local WhisperServerTranscriber = setmetatable({}, {__index = ITranscriber})
WhisperServerTranscriber.__index = WhisperServerTranscriber

--- Create a new WhisperServerTranscriber instance
---
--- @param config table Configuration options:
---   - host: Server host (default: "127.0.0.1")
---   - port: Server port (default: 8080)
---   - curlCmd: curl command path (default: "curl")
--- @return table WhisperServerTranscriber instance
function WhisperServerTranscriber.new(config)
  config = config or {}
  local self = setmetatable({}, WhisperServerTranscriber)

  self.host = config.host or "127.0.0.1"
  self.port = config.port or 8080
  self.curlCmd = config.curlCmd or "curl"

  return self
end

--- Validate that curl is available
---
--- Checks if curl is in PATH. Note: Does not verify server is running.
---
--- @return boolean success True if transcriber prerequisites are met
--- @return string|nil error Error message if validation failed
function WhisperServerTranscriber:validate()
  -- Check if curl is available
  local handle = io.popen("which " .. self.curlCmd .. " 2>/dev/null")
  if not handle then
    return false, "Failed to check for curl"
  end

  local result = handle:read("*a")
  handle:close()

  if not result or result == "" or result:match("not found") then
    return false, "curl not found"
  end

  return true, nil
end

--- Transcribe an audio file
---
--- Sends audio file to whisper server via HTTP POST and returns transcription.
--- Server is expected to respond with plain text transcription.
---
--- @param audioFile string Path to audio file
--- @param lang string Language code (e.g., "en", "es", "fr")
--- @param onSuccess function Callback with transcribed text: onSuccess(text)
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if transcription started successfully
--- @return string|nil error Error message if failed to start
function WhisperServerTranscriber:transcribe(audioFile, lang, onSuccess, onError)
  -- Validate audio file exists (synchronous precondition)
  local fileAttrs = hs.fs.attributes(audioFile)
  if not fileAttrs then
    return false, "Audio file not found: " .. audioFile
  end

  -- Build server URL
  local serverUrl = string.format(
    "http://%s:%s/inference",
    self.host,
    self.port
  )

  -- Build curl command with form data
  -- Server expects: file (audio), response_format (text), language (lang code)
  local cmd = string.format(
    [[%s -s -S -X POST '%s' -F 'file=@%s' -F 'response_format=text' -F 'language=%s' 2>&1]],
    self.curlCmd,
    serverUrl,
    audioFile,
    lang
  )

  -- Execute asynchronously (io.popen blocks, so use timer for async pattern)
  hs.timer.doAfter(0.01, function()
    -- Execute curl request
    local handle = io.popen(cmd)
    if not handle then
      if onError then
        onError("Failed to execute curl command")
      end
      return
    end

    local output = handle:read("*a")
    local success, exitType, exitCode = handle:close()

    if not success then
      if onError then
        onError("curl request failed: " .. (output or "unknown error"))
      end
      return
    end

    if not output or output == "" then
      if onError then
        onError("Empty response from whisper server")
      end
      return
    end

    -- Check for server error response (JSON error format)
    if output:match('^{%s*"error"') or output:match('^{"error"') then
      if onError then
        onError("Server error: " .. output)
      end
      return
    end

    -- Post-process: remove leading/trailing whitespace from each line
    -- This handles servers that may add indentation or extra whitespace
    local lines = {}
    for line in output:gmatch("[^\n]+") do
      local trimmed = line:match("^%s*(.-)%s*$")
      if trimmed and trimmed ~= "" then
        table.insert(lines, trimmed)
      end
    end

    local text = table.concat(lines, "\n")

    if text == "" then
      if onError then
        onError("Empty transcription result after processing")
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
function WhisperServerTranscriber:getName()
  return "WhisperServer"
end

--- Check if this transcriber supports a given language
---
--- WhisperServer supports all Whisper languages (100+).
---
--- @param lang string Language code
--- @return boolean supported True if language is supported
function WhisperServerTranscriber:supportsLanguage(lang)
  -- Whisper server supports all Whisper languages
  return true
end

return WhisperServerTranscriber
