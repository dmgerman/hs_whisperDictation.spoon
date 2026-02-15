--- StreamingBackend - Python streaming server backend with Silero VAD
-- Real implementation using hs.task and hs.socket directly
-- Emits EventBus events and returns Promises

local ErrorHandler = require("lib.error_handler")

local StreamingBackend = {}
StreamingBackend.__index = StreamingBackend

--- Create a new StreamingBackend
-- @param eventBus (EventBus): Event bus for emitting events
-- @param config (table): Configuration
--   - pythonExecutable (string): Python executable path
--   - serverScript (string): Path to whisper_stream.py
--   - tcpPort (number): TCP port for server communication
--   - silenceThreshold (number): Silence duration for chunk boundary
--   - minChunkDuration (number): Minimum chunk duration
--   - maxChunkDuration (number): Maximum chunk duration
-- @return (StreamingBackend): New instance
function StreamingBackend.new(eventBus, config)
  local self = setmetatable({}, StreamingBackend)
  self.eventBus = eventBus

  -- Store original config values
  self.config = {
    pythonExecutable = config.pythonExecutable or "python3",
    serverScript = config.serverScript,
    host = "127.0.0.1",
    tcpPort = config.tcpPort or 12341,
    serverStartupTimeout = 5.0,
    silenceThreshold = config.silenceThreshold or 2.0,
    minChunkDuration = config.minChunkDuration or 3.0,
    maxChunkDuration = config.maxChunkDuration or 600.0,
  }

  -- Internal state
  -- Operational state only (NOT recording state)
  self.serverProcess = nil
  self.tcpSocket = nil
  self._serverStarting = false
  self._chunkCount = 0
  self._currentLang = nil  -- Needed for event routing, not recording state

  return self
end

--- Resolve Python executable to full path
-- @private
-- @return (string): Full path to Python executable
function StreamingBackend:_resolvePythonPath()
  local pythonPath = self.config.pythonExecutable
  if not pythonPath:match("^/") then
    -- Relative path, resolve it
    local handle = io.popen("which " .. pythonPath .. " 2>/dev/null")
    if handle then
      local result = handle:read("*l")
      handle:close()
      if result and result ~= "" then
        return result
      end
    end
  end
  return pythonPath
end

--- Validate backend is available
-- @return (boolean, string?): success, error message if failed
function StreamingBackend:validate()
  -- Check Python exists
  local pythonPath = self.config.pythonExecutable
  if not pythonPath:match("^/") then
    -- Relative path, try to find it
    local findPython = io.popen("which " .. pythonPath .. " 2>/dev/null")
    if findPython then
      local found = findPython:read("*l")
      findPython:close()
      if not found or found == "" then
        return false, "Python not found in PATH: " .. pythonPath
      end
    end
  elseif _G.hs and _G.hs.fs and not _G.hs.fs.attributes(pythonPath) then
    return false, "Python not found at " .. pythonPath
  end

  -- Check script exists
  if not self.config.serverScript then
    return false, "Server script not specified"
  end

  if _G.hs and _G.hs.fs then
    if not _G.hs.fs.attributes(self.config.serverScript) then
      return false, "Server script not found at " .. self.config.serverScript
    end
  else
    -- Fallback: use io.open for testing
    local f = io.open(self.config.serverScript, "r")
    if not f then
      return false, "Server script not found at " .. self.config.serverScript
    end
    f:close()
  end

  return true, nil
end

--- Check if server is running
-- @private
-- @return (boolean): true if server is running
function StreamingBackend:_isServerRunning()
  if not _G.hs or not _G.hs.task then
    return self.serverProcess ~= nil and self.tcpSocket ~= nil
  end

  return self.serverProcess ~= nil
    and self.serverProcess:isRunning()
    and self.tcpSocket ~= nil
end

--- Start the Python server
-- @private
-- @param outputDir (string): Directory for audio files
-- @param filenamePrefix (string): Prefix for audio filenames
-- @return (boolean, string?): success, error message if failed
function StreamingBackend:_startServer(outputDir, filenamePrefix)
  -- Check if port is in use
  local handle = io.popen(string.format("lsof -i :%d 2>/dev/null", self.config.tcpPort))
  local result = handle and handle:read("*a") or ""
  if handle then handle:close() end

  if result and #result > 0 then
    -- Port in use - cleanup
    print(string.format("[StreamingBackend] Port %d in use, cleaning up...", self.config.tcpPort))
    os.execute(string.format("lsof -ti:%d | xargs kill -9 2>/dev/null", self.config.tcpPort))
    if _G.hs and _G.hs.timer then
      _G.hs.timer.usleep(500000)  -- 500ms
    else
      os.execute("sleep 0.5")
    end
  end

  -- Build args
  local args = {
    self.config.serverScript,
    "--tcp-port", tostring(self.config.tcpPort),
    "--output-dir", outputDir,
    "--filename-prefix", filenamePrefix,
    "--silence-threshold", tostring(self.config.silenceThreshold),
    "--min-chunk-duration", tostring(self.config.minChunkDuration),
    "--max-chunk-duration", tostring(self.config.maxChunkDuration),
  }

  -- Check if we're in test mode (no hs.task)
  if not _G.hs or not _G.hs.task then
    -- Test mode: pretend server started
    self.serverProcess = { test_mode = true }
    self.tcpSocket = { test_mode = true }
    return true
  end

  local serverReady = false
  local serverError = nil
  local self_ref = self

  -- Resolve Python path to full path (hs.task requires full paths)
  local pythonPath = self:_resolvePythonPath()

  -- Start server subprocess
  local self_ref = self
  self.serverProcess = _G.hs.task.new(
    pythonPath,
    function(exitCode, stdOut, stdErr)
      -- Exit callback
      print(string.format("[StreamingBackend] Server exited: exitCode=%d", exitCode))
      if exitCode ~= 0 then
        ErrorHandler.handleServerCrash(exitCode, stdErr, self_ref.eventBus)
      end
    end,
    args
  )

  if not self.serverProcess then
    return false, "Failed to create server process"
  end

  -- Capture stderr to detect "listening" message
  self.serverProcess:setStreamingCallback(function(task, stdOut, stdErr)
    if stdErr and #stdErr > 0 then
      print("[StreamingBackend] Server: " .. stdErr)

      -- Check for listening message
      if stdErr:match('"status":%s*"listening"') then
        serverReady = true
      end

      -- Check for errors
      if stdErr:match('"status":%s*"error"') then
        local ok, errorData = pcall(_G.hs.json.decode, stdErr)
        if ok and errorData and errorData.error then
          serverError = errorData.error
          if serverError:match("Address already in use") or serverError:match("Errno 48") then
            ErrorHandler.showWarning(string.format("Port %d in use!", self_ref.config.tcpPort), 5)
          end
        else
          serverError = "Unknown server error"
        end
      end
    end
  end)

  local ok, err = pcall(function() self.serverProcess:start() end)
  if not ok then
    self.serverProcess = nil
    return false, "Failed to start server: " .. tostring(err)
  end

  -- Wait for port to be listening
  local waited = 0
  local timeoutMs = self.config.serverStartupTimeout * 1000
  local portListening = false

  while not portListening and not serverError and waited < timeoutMs do
    handle = io.popen(string.format("lsof -i :%d 2>/dev/null", self.config.tcpPort))
    if handle then
      result = handle:read("*a")
      handle:close()
      if result and #result > 0 then
        portListening = true
      end
    end

    if not portListening then
      if _G.hs and _G.hs.timer then
        _G.hs.timer.usleep(100000)  -- 100ms
      else
        os.execute("sleep 0.1")
      end
      waited = waited + 100
    end
  end

  if serverError then
    if self.serverProcess then
      self.serverProcess:terminate()
      self.serverProcess = nil
    end
    return false, serverError
  end

  if not portListening then
    if self.serverProcess then
      self.serverProcess:terminate()
      self.serverProcess = nil
    end
    return false, "Server startup timeout (port not listening)"
  end

  print("[StreamingBackend] ✓ Server is listening on port " .. self.config.tcpPort)
  return true, nil
end

--- Connect TCP socket to server
-- @private
function StreamingBackend:_connectTCPSocket()
  if not _G.hs or not _G.hs.socket then
    -- Test mode
    self.tcpSocket = { test_mode = true }
    return
  end

  local self_ref = self
  local socket = _G.hs.socket.new()

  socket:setCallback(function(data, tag)
    self_ref:_handleSocketData(data, tag)
  end)

  -- Connect to server
  local connected = socket:connect(self.config.host, self.config.tcpPort)
  if connected then
    self.tcpSocket = socket
    -- Start reading
    self.tcpSocket:read("\n", 1)
  else
    ErrorHandler.showError("Failed to connect to server on port " .. self.config.tcpPort, self.eventBus, 15.0)
  end
end

--- Handle data from TCP socket
-- @private
function StreamingBackend:_handleSocketData(data, tag)
  if not data or data == "" then
    return
  end

  -- Parse JSON event
  local ok, event = pcall(_G.hs.json.decode, data)
  if not ok or not event or not event.type then
    ErrorHandler.handleInvalidMessage(data, self.eventBus)
    return
  end

  self:_handleServerEvent(event, self._currentLang)

  -- Continue reading
  if self.tcpSocket and not self.tcpSocket.test_mode then
    self.tcpSocket:read("\n", 1)
  end
end

--- Handle event from server
-- @private
-- @param event (table): Event object from server
-- @param lang (string): Current language
function StreamingBackend:_handleServerEvent(event, lang)
  local eventType = event.type

  if eventType == "server_ready" then
    self.eventBus:emit("streaming:server_ready", {})
    print("[StreamingBackend] ✓ Server ready")

  elseif eventType == "recording_started" then
    self.eventBus:emit("streaming:server_started", {})
    print("[StreamingBackend] Recording started")

  elseif eventType == "chunk_ready" then
    self._chunkCount = self._chunkCount + 1
    self._currentChunkStartTime = os.time()

    print(string.format("[StreamingBackend] Chunk %d ready: %s", event.chunk_num, event.audio_file))

    self.eventBus:emit("audio:chunk_ready", {
      chunkNum = event.chunk_num,
      audioFile = event.audio_file,
      lang = lang,
      isFinal = event.is_final,
    })

  elseif eventType == "recording_stopped" then
    self.eventBus:emit("recording:stopped", {})
    print("[StreamingBackend] Recording stopped")
    self._isRecording = false

  elseif eventType == "complete_file" then
    self.eventBus:emit("streaming:complete_file", {
      filePath = event.file_path,
    })

  elseif eventType == "error" then
    print("[StreamingBackend] Server error: " .. tostring(event.error))
    self.eventBus:emit("recording:error", { error = event.error })

  elseif eventType == "silence_warning" then
    local message = event.message or "Microphone appears to be off"
    -- ErrorHandler.showError already emits recording:error
    ErrorHandler.showError(message, self.eventBus, 10.0)
    -- Note: Python server should send recording_stopped after this
  else
    -- Unknown event type - report it
    ErrorHandler.handleUnknownEvent(eventType, self.eventBus)
  end
end

--- Send command to server via TCP
-- @private
-- @param command (table): Command object
-- @return (boolean): true if sent successfully
function StreamingBackend:_sendCommand(command)
  if not self.tcpSocket then
    if not _G.hs or not _G.hs.socket then
      return true  -- Test mode
    end

    ErrorHandler.showError("Cannot send command: no TCP connection", self.eventBus)
    return false
  end

  -- Test mode
  if self.tcpSocket.test_mode then
    return true
  end

  -- Encode and send
  local ok, json = pcall(_G.hs.json.encode, command)
  if not ok then
    ErrorHandler.showError("Failed to encode command as JSON", self.eventBus)
    return false
  end

  local sent = self.tcpSocket:write(json .. "\n")
  if not sent then
    ErrorHandler.showError("Failed to send command to server", self.eventBus)
    return false
  end

  return true
end

--- Start server if not running
-- @private
-- @param outputDir (string): Directory for audio files
-- @param filenamePrefix (string): Prefix for audio filenames
-- @return (boolean, string?): success, error message if failed
function StreamingBackend:_ensureServerRunning(outputDir, filenamePrefix)
  if self:_isServerRunning() then
    return true, nil
  end

  if self._serverStarting then
    -- Server is starting, wait
    local waited = 0
    while self._serverStarting and waited < 10000 do
      if _G.hs and _G.hs.timer then
        _G.hs.timer.usleep(100000)
      else
        os.execute("sleep 0.1")
      end
      waited = waited + 100
    end
    if self:_isServerRunning() then
      return true, nil
    end
  end

  self._serverStarting = true

  -- Start server
  local started, err = self:_startServer(outputDir, filenamePrefix)
  if not started then
    self._serverStarting = false
    return false, err
  end

  -- Connect TCP client
  if not self.tcpSocket then
    self:_connectTCPSocket()

    -- Wait briefly for socket to establish
    if _G.hs and _G.hs.timer then
      _G.hs.timer.usleep(100000)  -- 100ms
    else
      os.execute("sleep 0.1")
    end
  end

  self._serverStarting = false
  print("[StreamingBackend] ✓ Server started and connected")
  return true, nil
end

--- Start recording
-- @param config (table): Recording configuration
-- @return (Promise): Resolves when recording starts, rejects on error
function StreamingBackend:startRecording(config)
  local Promise = require("lib.promise")

  if self.serverProcess then
    return Promise.reject("Server already running")
  end

  local lang = config.lang
  self._currentLang = lang  -- Store for event routing
  self._chunkCount = 0  -- Reset operational counter

  print("[StreamingBackend] startRecording called with lang=" .. lang)

  return Promise.new(function(resolve, reject)
    -- Ensure server is running
    local started, err = self:_ensureServerRunning(config.outputDir or "/tmp", lang)
    if not started then
      ErrorHandler.showError("Server startup failed: " .. (err or "Unknown error"), self.eventBus, 15.0)
      reject(err or "Failed to start server")
      return
    end

    -- Send start_recording command
    local success = self:_sendCommand({command = "start_recording"})
    if not success then
      ErrorHandler.showError("Failed to send start command", self.eventBus)
      reject("Failed to send start_recording command")
      return
    end

    -- Emit event with lang from config (not stored state)
    self.eventBus:emit("recording:started", { lang = lang })
    print("[StreamingBackend] ✓ Recording started")
    resolve()
  end)
end

--- Stop recording
-- @return (Promise): Resolves when recording stops, rejects on error
function StreamingBackend:stopRecording()
  local Promise = require("lib.promise")

  if not self._isRecording then
    return Promise.reject("Not recording")
  end

  return Promise.new(function(resolve, reject)
    -- Send stop_recording command
    local success = self:_sendCommand({command = "stop_recording"})
    if not success then
      ErrorHandler.showError("Failed to send stop command", self.eventBus)
      reject("Failed to send stop command")
      return
    end

    print("[StreamingBackend] ✓ Stop command sent")
    -- _isRecording will be set to false when we receive recording_stopped event
    resolve()
  end)
end

--- Check if backend is operational (server running)
-- Note: This checks operational state, NOT recording state
-- RecordingManager is the source of truth for recording state
-- @return (boolean): true if server is running
function StreamingBackend:isRecording()
  return self.serverProcess ~= nil
end

--- Get display text for menubar
-- @param lang (string): Language code
-- @return (string): Display text
function StreamingBackend:getDisplayText(lang)
  if not self._startTime then
    return string.format("🎙️ 0s (%s)", lang)
  end

  local totalElapsed = os.difftime(os.time(), self._startTime)

  if self._chunkCount > 0 and self._currentChunkStartTime then
    local chunkElapsed = os.difftime(os.time(), self._currentChunkStartTime)
    return string.format("🎙️ Chunk %d (%ds/%ds) (%s)",
                        self._chunkCount + 1, chunkElapsed, totalElapsed, lang)
  else
    return string.format("🎙️ %ds (%s)", totalElapsed, lang)
  end
end

--- Get the name of this backend
-- @return (string): Backend name
function StreamingBackend:getName()
  return "streaming"
end

--- Shutdown the server
-- @return (boolean): true if shutdown successfully
function StreamingBackend:shutdown()
  if self.tcpSocket and not self.tcpSocket.test_mode then
    local shutdownCmd = {command = "shutdown"}
    pcall(function() self:_sendCommand(shutdownCmd) end)

    -- Give server time to shutdown
    if _G.hs and _G.hs.timer then
      _G.hs.timer.usleep(500000)
    else
      os.execute("sleep 0.5")
    end

    pcall(function() self.tcpSocket:disconnect() end)
    self.tcpSocket = nil
  end

  if self.serverProcess and not self.serverProcess.test_mode then
    if _G.hs and _G.hs.task and self.serverProcess.terminate then
      pcall(function() self.serverProcess:terminate() end)
    end
    self.serverProcess = nil
  end

  self._currentLang = nil  -- Clear operational state

  print("[StreamingBackend] ✓ Server shutdown complete")
  return true
end

return StreamingBackend
