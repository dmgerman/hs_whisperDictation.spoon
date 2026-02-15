--- Recording Backend System for WhisperDictation
---
--- Each backend implements:
---   validate() - Check if dependencies are available
---   startRecording(outputDir, filenamePrefix, lang, callback) - Start recording
---   stopRecording() - Stop recording
---   isRecording() - Check if currently recording
---
--- Callback receives events:
---   {type = "chunk_ready", chunkNum = N, audioFile = path, isFinal = bool}
---   {type = "recording_started"}
---   {type = "recording_stopped"}
---   {type = "error", error = message}
---   {type = "silence_warning", message = message}

local RecordingBackends = {}

-- === Sox Backend (Simple Recording) ===
RecordingBackends.sox = {
  name = "sox",
  displayName = "Sox (Simple Recording)",
  config = {
    cmd = "/opt/homebrew/bin/sox",
  },

  -- Internal state
  _task = nil,
  _callback = nil,
  _audioFile = nil,
  _stopping = false,

  validate = function(self)
    return hs.fs.attributes(self.config.cmd) ~= nil
  end,

  startRecording = function(self, outputDir, filenamePrefix, lang, callback)
    if self._task then
      return false, "Already recording"
    end

    self._callback = callback
    self._stopping = false

    -- Generate timestamped filename
    local timestamp = os.date("%Y%m%d-%H%M%S")
    self._audioFile = string.format("%s/%s-%s.wav", outputDir, filenamePrefix, timestamp)

    -- Create sox task
    self._task = hs.task.new(self.config.cmd, function(exitCode, stdOut, stdErr)
      local wasStopping = self._stopping
      self._task = nil

      -- Only report error if not intentionally stopped
      if exitCode ~= 0 and not wasStopping then
        if self._callback then
          self._callback({type = "error", error = "Sox failed: " .. (stdErr or "unknown error")})
        end
      end
    end, {"-q", "-d", self._audioFile})

    if not self._task then
      return false, "Failed to create sox task"
    end

    local ok, err = pcall(function() self._task:start() end)
    if not ok then
      self._task = nil
      return false, "Failed to start sox: " .. tostring(err)
    end

    if self._callback then
      self._callback({type = "recording_started"})
    end

    return true, nil
  end,

  stopRecording = function(self)
    if not self._task then
      return false, "Not recording"
    end

    -- Mark as intentionally stopping
    self._stopping = true

    -- Terminate sox and wait briefly for file to be written
    self._task:terminate()
    self._task = nil

    -- Give sox a moment to flush the file
    hs.timer.usleep(100000)  -- 100ms

    -- Check if file was created
    if not hs.fs.attributes(self._audioFile) then
      if self._callback then
        self._callback({type = "error", error = "Recording file was not created"})
      end
      self._audioFile = nil
      self._callback = nil
      self._stopping = false
      return false, "Recording file not created"
    end

    -- Send chunk_ready event with the single recording
    if self._callback then
      self._callback({
        type = "chunk_ready",
        chunkNum = 1,
        audioFile = self._audioFile,
        isFinal = true
      })
      self._callback({type = "recording_stopped"})
    end

    self._audioFile = nil
    self._callback = nil
    self._stopping = false

    return true, nil
  end,

  isRecording = function(self)
    return self._task ~= nil
  end,
}

-- === Python Stream Backend (Continuous with Silero VAD) ===
RecordingBackends.pythonstream = {
  name = "pythonstream",
  displayName = "Python Stream (Silero VAD)",
  config = {
    pythonCmd = os.getenv("HOME") .. "/.config/dmg/python3.12/bin/python3",
    scriptPath = nil,  -- Set by spoon to full path
    host = "127.0.0.1",
    port = 12341,
    serverStartupTimeout = 5.0,  -- Seconds to wait for server ready
    silenceThreshold = 2.0,      -- Seconds of silence to trigger chunk
    minChunkDuration = 3.0,     -- Minimum chunk length
    maxChunkDuration = 600.0,    -- Maximum chunk length
  },

  -- Internal state
  _serverProcess = nil,  -- hs.task for persistent server
  _client = nil,         -- hs.socket TCP client
  _callback = nil,
  _outputDir = nil,
  _stopping = false,
  _serverReady = false,  -- Track if server is ready
  _isRecording = false,  -- Track if currently recording
  _serverStarting = false,  -- Track if server is currently starting

  validate = function(self)
    -- Check Python exists (use which for PATH lookup)
    local pythonPath = self.config.pythonCmd
    if not pythonPath:match("^/") then
      -- Not an absolute path, try to find it
      local findPython = io.popen("which " .. pythonPath  .. " 2>/dev/null")
      if findPython then
        local found = findPython:read("*l")
        findPython:close()
        if not found or found == "" then
          return false, "Python not found in PATH: " .. pythonPath
        end
      end
    elseif not hs.fs.attributes(pythonPath) then
      return false, "Python not found at " .. pythonPath
    end

    -- Check script exists
    if not self.config.scriptPath or not hs.fs.attributes(self.config.scriptPath) then
      return false, "Python script not found at " .. (self.config.scriptPath or "unknown")
    end

    -- Dependencies will be checked at runtime (avoids validation timeout issues)
    return true, nil
  end,

  _startServer = function(self, outputDir, filenamePrefix)
    -- Check if port is in use by another process
    local handle = io.popen(string.format("lsof -i :%d 2>/dev/null", self.config.port))
    local result = handle and handle:read("*a") or ""
    if handle then handle:close() end

    if result and #result > 0 then
      -- Port is in use - try to clean up zombies
      print(string.format("[DEBUG BACKEND] Port %d in use, attempting cleanup...", self.config.port))
      os.execute(string.format("lsof -ti:%d | xargs kill -9 2>/dev/null", self.config.port))
      hs.timer.usleep(500000)  -- 500ms for cleanup

      -- Check again if port is still in use
      handle = io.popen(string.format("lsof -i :%d 2>/dev/null", self.config.port))
      result = handle and handle:read("*a") or ""
      if handle then handle:close() end

      if result and #result > 0 then
        -- Port still in use after cleanup attempt
        local errorMsg = string.format(
          "Port %d is in use by another process. Change pythonstreamConfig.port or kill the process:\nlsof -ti:%d | xargs kill",
          self.config.port, self.config.port
        )
        print("[ERROR] " .. errorMsg)
        hs.alert.show("⚠️ Port " .. self.config.port .. " in use!\nSee console for details")
        return false, "Port " .. self.config.port .. " is already in use"
      end
    end

    local args = {
      self.config.scriptPath,
      "--tcp-port", tostring(self.config.port),
      "--output-dir", outputDir,
      "--filename-prefix", filenamePrefix,
      "--silence-threshold", tostring(self.config.silenceThreshold),
      "--min-chunk-duration", tostring(self.config.minChunkDuration),
      "--max-chunk-duration", tostring(self.config.maxChunkDuration),
    }

    -- Track server readiness
    local serverReady = false
    local serverError = nil

    -- Start server subprocess (just for lifecycle management)
    self._serverProcess = hs.task.new(self.config.pythonCmd,
      function(exitCode, stdOut, stdErr)
        -- Exit callback (cleanup only)
        print(string.format("[DEBUG BACKEND] Server process exited: exitCode=%d", exitCode))
        if stdErr and #stdErr > 0 then
          print("[WhisperDictation] Server stderr: " .. stdErr)
        end
      end,
      args)

    if not self._serverProcess then
      return false, "Failed to create server process"
    end

    -- Capture stderr to detect "listening" message
    self._serverProcess:setStreamingCallback(function(task, stdOut, stdErr)
      if stdErr and #stdErr > 0 then
        print("[DEBUG BACKEND] Server stderr: " .. stdErr)

        -- Check for listening message
        if stdErr:match('"status":%s*"listening"') then
          serverReady = true
        end

        -- Check for errors
        if stdErr:match('"status":%s*"error"') then
          local ok, errorData = pcall(hs.json.decode, stdErr)
          if ok and errorData and errorData.error then
            serverError = errorData.error
            -- Check for port conflict specifically
            if serverError:match("Address already in use") or serverError:match("Errno 48") then
              print(string.format("[ERROR] Port %d is in use by another process", self.config.port))
              hs.alert.show(string.format("⚠️ Port %d in use!\nChange pythonstreamConfig.port", self.config.port), 5)
            end
          else
            serverError = "Unknown server error"
          end
        end
      end
    end)

    local ok, err = pcall(function() self._serverProcess:start() end)
    if not ok then
      self._serverProcess = nil
      return false, "Failed to start server: " .. tostring(err)
    end

    -- Wait for server ready by checking if port is listening
    -- This is more reliable than parsing stderr since callbacks may be buffered
    local waited = 0
    local timeoutMs = self.config.serverStartupTimeout * 1000
    local portListening = false

    while not portListening and not serverError and waited < timeoutMs do
      -- Check if port is listening using lsof
      local handle = io.popen(string.format("lsof -i :%d 2>/dev/null", self.config.port))
      if handle then
        local result = handle:read("*a")
        handle:close()
        if result and #result > 0 then
          portListening = true
        end
      end

      if not portListening then
        hs.timer.usleep(100000)  -- 100ms
        waited = waited + 100
      end
    end

    if serverError then
      -- Server reported an error
      if self._serverProcess then
        self._serverProcess:terminate()
        self._serverProcess = nil
      end
      return false, serverError
    end

    if not portListening then
      -- Timeout - port never started listening
      if self._serverProcess then
        self._serverProcess:terminate()
        self._serverProcess = nil
      end
      return false, "Server startup timeout (port not listening)"
    end

    return true, nil
  end,

  startRecording = function(self, outputDir, filenamePrefix, lang, callback)
    if self._isRecording then
      return false, "Already recording"
    end

    self._callback = callback
    self._outputDir = outputDir
    self._stopping = false

    -- Ensure server is running
    if not self:isServerRunning() then
      local started, err = self:startServer(outputDir, filenamePrefix)
      if not started then
        return false, err
      end
    end

    -- Send start_recording command
    local startCmd = hs.json.encode({command = "start_recording"}) .. "\n"
    local ok = pcall(function() self._client:write(startCmd) end)
    if not ok then
      return false, "Failed to send start_recording command"
    end

    self._isRecording = true
    return true, nil
  end,

  stopRecording = function(self)
    if not self._isRecording then
      return false, "Not recording"
    end

    self._stopping = true
    print("[DEBUG BACKEND] Sending stop_recording command to server")

    -- Send stop_recording command (server stays running)
    local stopCmd = hs.json.encode({command = "stop_recording"}) .. "\n"
    local ok = pcall(function() self._client:write(stopCmd) end)
    if not ok then
      print("[DEBUG BACKEND] Failed to send stop_recording command")
      self._isRecording = false
      return false, "Failed to send stop command"
    end

    -- Server will send final events and recording_stopped
    -- Don't set _isRecording = false yet - wait for recording_stopped event

    return true, nil
  end,

  isRecording = function(self)
    return self._isRecording
  end,

  --- Check if server is running and ready.
  isServerRunning = function(self)
    return self._serverProcess ~= nil and self._serverProcess:isRunning() and self._client ~= nil
  end,

  --- Start persistent Python stream server.
  -- @param outputDir (string): Directory for audio files
  -- @param filenamePrefix (string): Prefix for audio filenames
  -- @return (boolean, string|nil): success, error message on failure
  startServer = function(self, outputDir, filenamePrefix)
    if self:isServerRunning() then
      return true, nil  -- Already running
    end

    if self._serverStarting then
      -- Server is currently starting, wait for it
      local waited = 0
      while self._serverStarting and waited < 10000 do
        hs.timer.usleep(100000)  -- 100ms
        waited = waited + 100
      end
      -- Check again if server is now running
      if self:isServerRunning() then
        return true, nil
      end
    end

    self._serverStarting = true

    -- Start server if not running
    local serverStarted, serverErr = self:_startServer(outputDir, filenamePrefix)
    if not serverStarted then
      self._serverStarting = false
      return false, "Failed to start server: " .. tostring(serverErr)
    end

    -- Connect TCP client if not connected
    if not self._client then
      self._client = hs.socket.new()
      self._client:setCallback(function(data, tag)
        self:_handleSocketData(data, tag)
      end)

      -- Connect with retry
      local maxRetries = 3
      local connected = false
      for attempt = 1, maxRetries do
        local ok, err = pcall(function()
          self._client:connect(self.config.host, self.config.port)
        end)
        if ok then
          connected = true
          break
        elseif attempt < maxRetries then
          hs.timer.usleep(1000000)  -- 1 second
        end
      end

      if not connected then
        if self._serverProcess then
          self._serverProcess:terminate()
          self._serverProcess = nil
        end
        self._client = nil
        return false, "Failed to connect to server"
      end

      -- Start reading from socket
      self._client:read("\n", 1)

      -- Wait briefly for socket to be ready (non-blocking)
      -- The server_ready event will arrive via socket callback
      hs.timer.usleep(100000)  -- 100ms for socket to establish
    end

    -- Server is listening and socket is connected
    -- The server_ready event will arrive asynchronously via callback
    self._serverStarting = false
    return true, nil
  end,

  --- Stop persistent Python stream server.
  stopServer = function(self)
    if self._client then
      -- Send shutdown command
      local shutdownCmd = hs.json.encode({command = "shutdown"}) .. "\n"
      pcall(function() self._client:write(shutdownCmd) end)
      hs.timer.usleep(500000)  -- Give it 500ms to shutdown gracefully

      pcall(function() self._client:disconnect() end)
      self._client = nil
    end

    if self._serverProcess then
      if self._serverProcess:isRunning() then
        self._serverProcess:terminate()
      end
      self._serverProcess = nil
    end

    self._serverReady = false
    self._isRecording = false
    self._serverStarting = false
    self._callback = nil
    self._outputDir = nil
    self._stopping = false
  end,

  -- Handle incoming socket data (newline-delimited JSON events)
  _handleSocketData = function(self, data, tag)
    if type(data) == "string" and data ~= "" then
      print(string.format("[DEBUG BACKEND] Socket data: %s", data))

      -- Parse JSON event
      local ok, event = pcall(hs.json.decode, data)
      if ok and event and event.type then
        print(string.format("[DEBUG BACKEND] Event type: %s", event.type))

        -- Handle server_ready event
        if event.type == "server_ready" then
          self._serverReady = true
          print("[DEBUG BACKEND] Server is ready")
        elseif event.type == "recording_stopped" then
          self._isRecording = false
          self._stopping = false
          print("[DEBUG BACKEND] Recording stopped, server still running")
        end

        -- Forward all events to callback
        if self._callback then
          self._callback(event)
        end
      else
        print("[WhisperDictation] Failed to parse event: " .. data)
      end

      -- CRITICAL: Queue next read to keep stream flowing
      if self._client then
        self._client:read("\n", 1)
      end
    elseif data == nil then
      -- Connection closed by server
      print("[DEBUG BACKEND] Server connection closed")
      self._serverReady = false
      self._isRecording = false
      if self._callback and not self._stopping then
        self._callback({
          type = "error",
          error = "Server disconnected unexpectedly"
        })
      end
      self._client = nil
    end
  end,
}

return RecordingBackends
