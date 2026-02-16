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
---   - executable: Path to whisper-server binary (for auto-start)
---   - modelPath: Path to whisper model file (for auto-start)
---   - startupTimeout: Server startup timeout in seconds (default: 10)
--- @return table WhisperServerTranscriber instance
function WhisperServerTranscriber.new(config)
  config = config or {}
  local self = setmetatable({}, WhisperServerTranscriber)

  self.host = config.host or "127.0.0.1"
  self.port = config.port or 8080
  self.curlCmd = config.curlCmd or "curl"
  self.executable = config.executable
  self.modelPath = config.modelPath
  self.startupTimeout = config.startupTimeout or 10

  -- Track server process (if we started it)
  self.serverTask = nil
  self.serverStartedByUs = false

  return self
end

--- Check if server is running
---
--- @return boolean running True if server is responding
function WhisperServerTranscriber:_isServerRunning()
  local healthUrl = string.format("http://%s:%s/health", self.host, self.port)
  local cmd = string.format("%s -s --connect-timeout 2 '%s' >/dev/null 2>&1", self.curlCmd, healthUrl)

  local result = os.execute(cmd)
  return result == 0 or result == true
end

--- Start the whisper server
---
--- @return boolean success True if server started successfully
--- @return string|nil error Error message if failed
function WhisperServerTranscriber:_startServer()
  if not self.executable then
    return false, "No executable configured for auto-start"
  end

  if not self.modelPath then
    return false, "No modelPath configured for auto-start"
  end

  -- Check if executable exists
  local execAttrs = hs.fs.attributes(self.executable)
  if not execAttrs then
    return false, "Executable not found: " .. self.executable
  end

  -- Check if model exists
  local modelAttrs = hs.fs.attributes(self.modelPath)
  if not modelAttrs then
    return false, "Model file not found: " .. self.modelPath
  end

  print("[WhisperServerTranscriber] Starting server: " .. self.executable)
  print("[WhisperServerTranscriber] Model: " .. self.modelPath)
  print("[WhisperServerTranscriber] Port: " .. self.port)

  -- Start server using hs.task (async, non-blocking)
  self.serverTask = hs.task.new(
    self.executable,
    nil,  -- no completion callback needed (server runs indefinitely)
    function(task, stdout, stderr)
      -- Stream callback for server output
      if stdout and stdout ~= "" then
        print("[WhisperServer] " .. stdout)
      end
      if stderr and stderr ~= "" then
        print("[WhisperServer] " .. stderr)
      end
      return true  -- Continue streaming
    end,
    {
      "--host", self.host,
      "--port", tostring(self.port),
      "--model", self.modelPath,
    }
  )

  if not self.serverTask:start() then
    self.serverTask = nil
    return false, "Failed to start server task"
  end

  self.serverStartedByUs = true

  -- Wait for server to become ready (up to startupTimeout seconds)
  local maxWait = self.startupTimeout
  local checkInterval = 0.5
  local waited = 0

  while waited < maxWait do
    hs.timer.usleep(checkInterval * 1000000)  -- Convert to microseconds

    if self:_isServerRunning() then
      print("[WhisperServerTranscriber] ✓ Server ready after " .. waited .. "s")
      return true, nil
    end

    waited = waited + checkInterval
  end

  -- Timeout - server didn't become ready
  if self.serverTask then
    self.serverTask:terminate()
    self.serverTask = nil
  end
  self.serverStartedByUs = false

  return false, "Server failed to start within " .. maxWait .. "s"
end

--- Validate that prerequisites are met and server is running
---
--- Checks curl availability and ensures server is running (auto-starts if needed).
---
--- @return boolean success True if transcriber is ready
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

  -- Check if server is running
  if self:_isServerRunning() then
    print("[WhisperServerTranscriber] ✓ Server already running")
    return true, nil
  end

  -- Server not running - try to auto-start if configured
  if self.executable then
    print("[WhisperServerTranscriber] Server not running, attempting auto-start...")
    local ok, err = self:_startServer()
    if not ok then
      return false, "Server auto-start failed: " .. tostring(err)
    end
    return true, nil
  end

  -- No auto-start configured and server not running
  return false, string.format(
    "Server not running on %s:%s and no executable configured for auto-start",
    self.host,
    self.port
  )
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

--- Clean up resources (stop server if we started it)
---
--- Should be called when spoon is stopped/unloaded.
function WhisperServerTranscriber:cleanup()
  if self.serverTask and self.serverStartedByUs then
    print("[WhisperServerTranscriber] Stopping server (pid: " .. tostring(self.serverTask:pid()) .. ")")
    self.serverTask:terminate()
    self.serverTask = nil
    self.serverStartedByUs = false
  end
end

return WhisperServerTranscriber
