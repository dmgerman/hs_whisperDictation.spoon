--- StreamingRecorder - Python streaming server recorder with Silero VAD
---
--- Records audio with voice activity detection, emits multiple chunks during recording.
--- Callback-based architecture (no Promises or EventBus).
---
--- @module StreamingRecorder

-- Get the spoon directory path from this file's location
local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)"):gsub("recorders/streaming/", "")
local IRecorder = dofile(spoonPath .. "recorders/i_recorder.lua")

local StreamingRecorder = setmetatable({}, {__index = IRecorder})
StreamingRecorder.__index = StreamingRecorder

--- Create a new StreamingRecorder instance
---
--- @param config table Configuration
---   - pythonPath: Path to Python executable (default: "python3")
---   - serverScript: Path to whisper_stream.py (required)
---   - tcpPort: TCP port for server communication (default: 12341)
---   - tempDir: Directory for audio files (default: "/tmp/whisper_dict")
---   - audioInputDevice: Audio input device name (default: nil = system default)
---   - silenceThreshold: Silence duration for chunk boundary (default: 2.0)
---   - minChunkDuration: Minimum chunk duration (default: 3.0)
---   - maxChunkDuration: Maximum chunk duration (default: 600.0)
--- @return table StreamingRecorder instance
function StreamingRecorder.new(config)
  config = config or {}
  local self = setmetatable({}, StreamingRecorder)

  self.pythonPath = config.pythonPath or "python3"
  self.serverScript = config.serverScript
  self.tcpPort = config.tcpPort or 12341
  self.tempDir = config.tempDir or "/tmp/whisper_dict"
  self.audioInputDevice = config.audioInputDevice  -- nil = default device

  -- VAD configuration
  self.silenceThreshold = config.silenceThreshold or 2.0
  self.minChunkDuration = config.minChunkDuration or 3.0
  self.maxChunkDuration = config.maxChunkDuration or 600.0
  self.perfectSilenceDuration = config.perfectSilenceDuration or 0  -- 0 = disabled (default), 2.0 for testing

  -- Operational state
  self.serverProcess = nil  -- hs.task object for Python server
  self.tcpSocket = nil  -- hs.socket object for communication
  self._isRecording = false  -- Explicit recording flag
  self._serverStarting = false  -- Server startup in progress
  self._chunkCount = 0  -- Number of chunks received
  self._currentLang = nil  -- Current language for chunk routing
  self._onChunk = nil  -- Stored callback for chunks
  self._onError = nil  -- Stored error callback
  self._onComplete = nil  -- Stored completion callback
  self._completionTimer = nil  -- Timeout timer for completion
  self._recordingComplete = false  -- Track if recording has stopped

  return self
end

--- Validate recorder is available
---
--- @return boolean success True if recorder is ready
--- @return string|nil error Error message if validation failed
function StreamingRecorder:validate()
  -- Check Python exists
  local pythonPath = self.pythonPath
  if not pythonPath:match("^/") then
    -- Relative path, try to find it
    local handle = io.popen("which " .. pythonPath .. " 2>/dev/null")
    if handle then
      local found = handle:read("*l")
      handle:close()
      if not found or found == "" then
        return false, "Python not found in PATH: " .. pythonPath
      end
    end
  else
    local attrs = hs.fs.attributes(pythonPath)
    if not attrs then
      return false, "Python not found at " .. pythonPath
    end
  end

  -- Check script exists
  if not self.serverScript then
    return false, "Server script not specified"
  end

  local attrs = hs.fs.attributes(self.serverScript)
  if not attrs then
    return false, "Server script not found at " .. self.serverScript
  end

  return true, nil
end

--- Resolve Python executable to full path
---
--- @private
--- @return string Full path to Python executable
function StreamingRecorder:_resolvePythonPath()
  local pythonPath = self.pythonPath
  if not pythonPath:match("^/") then
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

--- Check if server is running
---
--- @private
--- @return boolean True if server is running
function StreamingRecorder:_isServerRunning()
  return self.serverProcess ~= nil
    and self.serverProcess:isRunning()
    and self.tcpSocket ~= nil
end

--- Start the Python server
---
--- @private
--- @param outputDir string Directory for audio files
--- @param filenamePrefix string Prefix for audio filenames
--- @return boolean success True if server started
--- @return string|nil error Error message if failed
function StreamingRecorder:_startServer(outputDir, filenamePrefix)
  -- Check if port is in use and clean up if needed
  local handle = io.popen(string.format("lsof -i :%d 2>/dev/null", self.tcpPort))
  local result = handle and handle:read("*a") or ""
  if handle then handle:close() end

  if result and #result > 0 then
    print(string.format("[StreamingRecorder] Port %d in use, cleaning up...", self.tcpPort))
    os.execute(string.format("lsof -ti:%d | xargs kill -9 2>/dev/null", self.tcpPort))
    hs.timer.usleep(500000)  -- 500ms
  end

  -- Build server arguments
  local args = {
    self.serverScript,
    "--tcp-port", tostring(self.tcpPort),
    "--output-dir", outputDir,
    "--filename-prefix", filenamePrefix,
    "--silence-threshold", tostring(self.silenceThreshold),
    "--min-chunk-duration", tostring(self.minChunkDuration),
    "--max-chunk-duration", tostring(self.maxChunkDuration),
    "--perfect-silence-duration", tostring(self.perfectSilenceDuration),
  }

  -- Add audio device if specified
  if self.audioInputDevice then
    table.insert(args, "--audio-input")
    table.insert(args, self.audioInputDevice)
  end

  local serverReady = false
  local serverError = nil
  local self_ref = self

  -- Resolve Python path to full path
  local pythonPath = self:_resolvePythonPath()

  -- Start server subprocess
  self.serverProcess = hs.task.new(
    pythonPath,
    function(exitCode, stdOut, stdErr)
      -- Server exit callback
      print(string.format("[StreamingRecorder] Server exited: exitCode=%d", exitCode))
      if exitCode ~= 0 and self_ref._onError then
        self_ref._onError("Server crashed with exit code " .. exitCode)
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
      print("[StreamingRecorder] Server: " .. stdErr)

      -- Check for listening message
      if stdErr:match('"status":%s*"listening"') then
        serverReady = true
      end

      -- Check for errors
      if stdErr:match('"status":%s*"error"') then
        local ok, errorData = pcall(hs.json.decode, stdErr)
        if ok and errorData and errorData.error then
          serverError = errorData.error
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
  local timeoutMs = 5000  -- 5 seconds
  local portListening = false

  while not portListening and not serverError and waited < timeoutMs do
    handle = io.popen(string.format("lsof -i :%d 2>/dev/null", self.tcpPort))
    if handle then
      result = handle:read("*a")
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

  print("[StreamingRecorder] ✓ Server is listening on port " .. self.tcpPort)
  return true, nil
end

--- Connect TCP socket to server
---
--- @private
function StreamingRecorder:_connectTCPSocket()
  local self_ref = self
  local socket = hs.socket.new()

  socket:setCallback(function(data, tag)
    self_ref:_handleSocketData(data, tag)
  end)

  -- Connect to server
  local connected = socket:connect("127.0.0.1", self.tcpPort)
  if connected then
    self.tcpSocket = socket
    -- Start reading
    self.tcpSocket:read("\n", 1)
  else
    if self._onError then
      self._onError("Failed to connect to server on port " .. self.tcpPort)
    end
  end
end

--- Handle data from TCP socket
---
--- @private
--- @param data string Data received from socket
--- @param tag number Socket tag
function StreamingRecorder:_handleSocketData(data, tag)
  if not data or data == "" then
    return
  end

  -- Parse JSON event
  local ok, event = pcall(hs.json.decode, data)
  if not ok or not event or not event.type then
    if self._onError then
      self._onError("Invalid message from server: " .. tostring(data))
    end
    return
  end

  self:_handleServerEvent(event, self._currentLang)

  -- Continue reading
  if self.tcpSocket then
    self.tcpSocket:read("\n", 1)
  end
end

--- Handle event from server
---
--- @private
--- @param event table Event object from server
--- @param lang string Current language
function StreamingRecorder:_handleServerEvent(event, lang)
  local eventType = event.type

  if eventType == "server_ready" then
    print("[StreamingRecorder] ✓ Server ready")

  elseif eventType == "recording_started" then
    print("[StreamingRecorder] Recording started")

  elseif eventType == "chunk_ready" then
    self._chunkCount = self._chunkCount + 1

    print(string.format("[StreamingRecorder] Chunk %d ready: %s", event.chunk_num, event.audio_file))

    -- Emit chunk immediately via callback
    if self._onChunk then
      self._onChunk(event.audio_file, event.chunk_num, event.is_final)
    end

    -- If this is the final chunk AND recording has stopped, trigger completion
    if event.is_final and self._recordingComplete then
      self:_triggerCompletion()
    end

  elseif eventType == "recording_stopped" then
    print("[StreamingRecorder] Recording stopped by server")
    self._isRecording = false

    -- If recording was stopped (stopRecording called) and no final chunk received yet,
    -- trigger completion now (handles zero-chunk case)
    if self._recordingComplete and self._onComplete then
      self:_triggerCompletion()
    end

  elseif eventType == "error" then
    print("[StreamingRecorder] Server error: " .. tostring(event.error))
    if self._onError then
      self._onError(event.error)
    end

  elseif eventType == "silence_warning" then
    local message = event.message or "Microphone appears to be off"
    print("[StreamingRecorder] Silence warning: " .. message)
    if self._onError then
      self._onError(message)
    end

  elseif eventType == "complete_file" then
    -- Complete recording file saved (for auditing/debugging)
    print("[StreamingRecorder] Complete file saved: " .. tostring(event.file_path))

  else
    print("[StreamingRecorder] Unknown event type: " .. tostring(eventType))
  end
end

--- Send command to server via TCP
---
--- @private
--- @param command table Command object
--- @return boolean True if sent successfully
function StreamingRecorder:_sendCommand(command)
  if not self.tcpSocket then
    if self._onError then
      self._onError("Cannot send command: no TCP connection")
    end
    return false
  end

  -- Encode and send
  local ok, json = pcall(hs.json.encode, command)
  if not ok then
    if self._onError then
      self._onError("Failed to encode command as JSON")
    end
    return false
  end

  local sent = self.tcpSocket:write(json .. "\n")
  if not sent then
    if self._onError then
      self._onError("Failed to send command to server")
    end
    return false
  end

  return true
end

--- Ensure server is running, start if needed
---
--- @private
--- @param outputDir string Directory for audio files
--- @param filenamePrefix string Prefix for audio filenames
--- @return boolean success True if server is running
--- @return string|nil error Error message if failed
function StreamingRecorder:_ensureServerRunning(outputDir, filenamePrefix)
  if self:_isServerRunning() then
    return true, nil
  end

  if self._serverStarting then
    -- Server is starting, wait
    local waited = 0
    while self._serverStarting and waited < 10000 do
      hs.timer.usleep(100000)
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
    hs.timer.usleep(100000)  -- 100ms
  end

  self._serverStarting = false
  print("[StreamingRecorder] ✓ Server started and connected")
  return true, nil
end

--- Start recording audio
---
--- @param config table Configuration {outputDir, lang}
---   - outputDir: Directory for audio files (required)
---   - lang: Language code for filename prefix (required)
--- @param onChunk function Callback when chunk ready: onChunk(audioFile, chunkNum, isFinal)
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if recording started successfully
--- @return string|nil error Error message if failed to start
function StreamingRecorder:startRecording(config, onChunk, onError)
  if self._isRecording then
    return false, "Already recording"
  end

  -- Clear any pending completion callbacks from previous recording
  if self._completionTimer then
    self._completionTimer:stop()
    self._completionTimer = nil
  end
  self._onComplete = nil
  self._recordingComplete = false

  local lang = config.lang
  self._currentLang = lang
  self._chunkCount = 0
  self._onChunk = onChunk
  self._onError = onError

  print("[StreamingRecorder] startRecording called with lang=" .. lang)

  -- Ensure server is running
  local started, err = self:_ensureServerRunning(config.outputDir or self.tempDir, lang)
  if not started then
    if onError then
      onError("Server startup failed: " .. (err or "Unknown error"))
    end
    return false, err or "Failed to start server"
  end

  -- Send start_recording command
  local success = self:_sendCommand({command = "start_recording"})
  if not success then
    if onError then
      onError("Failed to send start command")
    end
    return false, "Failed to send start_recording command"
  end

  -- Set recording flag after successful start
  self._isRecording = true

  print("[StreamingRecorder] ✓ Recording started")
  return true, nil
end

--- Stop recording audio
---
--- @param onComplete function Callback when stop completes: onComplete()
--- @param onError function Callback for errors: onError(errorMessage)
--- @return boolean success True if stop initiated successfully
--- @return string|nil error Error message if failed to stop
function StreamingRecorder:stopRecording(onComplete, onError)
  if not self._isRecording then
    return false, "Not recording"
  end

  -- Send stop_recording command
  local success = self:_sendCommand({command = "stop_recording"})
  if not success then
    if onError then
      onError("Failed to send stop command")
    end
    return false, "Failed to send stop command"
  end

  -- Clear recording flag immediately
  self._isRecording = false
  self._recordingComplete = true

  -- Store completion callback - will be called when:
  -- 1. Final chunk (is_final=true) arrives, OR
  -- 2. recording_stopped event arrives (handles zero-chunk case), OR
  -- 3. Timeout expires (fallback)
  self._onComplete = onComplete

  print("[StreamingRecorder] ✓ Stop command sent")

  -- Set timeout fallback in case server events never arrive
  -- This prevents hanging if server crashes or connection is lost
  if hs and hs.timer then
    self._completionTimer = hs.timer.doAfter(10, function()
      print("[StreamingRecorder] ⚠️ Completion timeout - server events did not arrive")
      self:_triggerCompletion()
    end)
  end

  return true, nil
end

--- Trigger completion callback (called when recording is truly complete)
---
--- @private
function StreamingRecorder:_triggerCompletion()
  -- Cancel timeout timer if it exists
  if self._completionTimer then
    self._completionTimer:stop()
    self._completionTimer = nil
  end

  -- Call completion callback if set
  local callback = self._onComplete
  if callback then
    self._onComplete = nil  -- Clear before calling to prevent double-call
    callback()
  end
end

--- Shutdown the server and cleanup resources
---
--- Called by init.lua when spoon is unloaded/reloaded
---
--- @return boolean True if cleanup successful
function StreamingRecorder:cleanup()
  print("[StreamingRecorder] Cleaning up...")

  -- Send shutdown command to server
  if self.tcpSocket then
    local shutdownCmd = {command = "shutdown"}
    pcall(function() self:_sendCommand(shutdownCmd) end)

    -- Give server time to shutdown
    hs.timer.usleep(500000)

    pcall(function() self.tcpSocket:disconnect() end)
    self.tcpSocket = nil
  end

  -- Terminate server process
  if self.serverProcess then
    pcall(function() self.serverProcess:terminate() end)
    self.serverProcess = nil
  end

  -- Clear completion timer
  if self._completionTimer then
    self._completionTimer:stop()
    self._completionTimer = nil
  end

  -- Clear state
  self._isRecording = false
  self._recordingComplete = false
  self._currentLang = nil
  self._chunkCount = 0
  self._onChunk = nil
  self._onError = nil
  self._onComplete = nil

  print("[StreamingRecorder] ✓ Cleanup complete")
  return true
end

--- Check if currently recording
---
--- @return boolean recording True if recording
function StreamingRecorder:isRecording()
  return self._isRecording
end

--- Get recorder name
---
--- @return string name Recorder name
function StreamingRecorder:getName()
  return "streaming"
end

return StreamingRecorder
