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
    silenceThreshold = 5.0,      -- Seconds of silence to trigger chunk
    minChunkDuration = 10.0,     -- Minimum chunk length
    maxChunkDuration = 120.0,    -- Maximum chunk length
  },

  -- Internal state
  _task = nil,
  _callback = nil,
  _outputDir = nil,
  _stopping = false,

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

  startRecording = function(self, outputDir, filenamePrefix, lang, callback)
    if self._task then
      return false, "Already recording"
    end

    self._callback = callback
    self._outputDir = outputDir
    self._stopping = false

    -- Resolve Python path if not absolute
    local pythonPath = self.config.pythonCmd
    if not pythonPath:match("^/") then
      local findPython = io.popen("which " .. pythonPath .. " 2>/dev/null")
      if findPython then
        local found = findPython:read("*l")
        findPython:close()
        if found and found ~= "" then
          pythonPath = found
        else
          return false, "Python not found in PATH: " .. pythonPath
        end
      end
    end

    -- Build arguments (use stdbuf to force unbuffered output)
    -- stdbuf -o0 forces unbuffered stdout, -e0 forces unbuffered stderr
    local stdbufCmd = "/opt/homebrew/bin/stdbuf"
    local args = {
      "-o0",  -- Unbuffered stdout
      "-e0",  -- Unbuffered stderr
      pythonPath,
      "-u",  -- Python unbuffered mode
      self.config.scriptPath,
      "--output-dir", outputDir,
      "--filename-prefix", filenamePrefix,
      "--silence-threshold", tostring(self.config.silenceThreshold),
      "--min-chunk-duration", tostring(self.config.minChunkDuration),
      "--max-chunk-duration", tostring(self.config.maxChunkDuration),
    }

    -- Create task using stdbuf wrapper
    print(string.format("[DEBUG BACKEND] Creating task: %s %s", stdbufCmd, table.concat(args, " ")))
    self._task = hs.task.new(stdbufCmd, function(exitCode, stdOut, stdErr)
      print(string.format("[DEBUG BACKEND] Task exit callback: exitCode=%d, stopping=%s", exitCode, tostring(self._stopping)))
      if stdOut and #stdOut > 0 then
        print(string.format("[DEBUG BACKEND] Exit callback stdOut: %d bytes", #stdOut))
        -- Process any final events
        self:_handleOutput(stdOut)
      end
      if stdErr and #stdErr > 0 then
        print(string.format("[DEBUG BACKEND] Exit callback stdErr: %d bytes", #stdErr))
        print("[WhisperDictation] Python stderr: " .. stdErr)
      end

      local wasStopping = self._stopping
      self._task = nil
      self._stopping = false

      if exitCode ~= 0 and not wasStopping then
        -- Unexpected exit
        local errorMsg = "Python script exited unexpectedly"
        if stdErr and #stdErr > 0 then
          errorMsg = errorMsg .. ": " .. stdErr
        end
        if self._callback then
          self._callback({type = "error", error = errorMsg})
        end
      end

      -- Clear callback after processing all events
      self._callback = nil
    end, args)

    if not self._task then
      print("[DEBUG BACKEND] Failed to create task!")
      return false, "Failed to create Python task"
    end
    print("[DEBUG BACKEND] Task created successfully")

    -- Set up streaming callback for stdout (events)
    self._task:setStreamingCallback(function(task, stdOut, stdErr)
      if stdOut and #stdOut > 0 then
        print(string.format("[DEBUG BACKEND] Streaming stdout: %d bytes", #stdOut))
        self:_handleOutput(stdOut)
      end
      if stdErr and #stdErr > 0 then
        print(string.format("[DEBUG BACKEND] Streaming stderr: %d bytes", #stdErr))
        print("[WhisperDictation] Python stderr: " .. stdErr)
      end
    end)

    print("[DEBUG BACKEND] Starting task...")
    local ok, err = pcall(function() self._task:start() end)
    if not ok then
      print(string.format("[DEBUG BACKEND] Failed to start task: %s", tostring(err)))
      self._task = nil
      return false, "Failed to start Python script: " .. tostring(err)
    end
    print("[DEBUG BACKEND] Task started successfully")

    return true, nil
  end,

  stopRecording = function(self)
    if not self._task then
      return false, "Not recording"
    end

    self._stopping = true

    -- Send SIGINT to Python script (graceful shutdown)
    self._task:terminate()

    -- Python script should output final chunk and recording_stopped event
    -- Wait briefly for graceful shutdown
    local waited = 0
    while self._task and self._task:isRunning() and waited < 2000 do
      hs.timer.usleep(100000)  -- 100ms
      waited = waited + 100
    end

    -- Force kill if still running
    if self._task and self._task:isRunning() then
      self._task:terminate()
    end

    -- Don't clear callback here - let exit callback handle final events
    -- Just clear task reference
    self._task = nil
    self._outputDir = nil
    self._stopping = false

    return true, nil
  end,

  isRecording = function(self)
    return self._task ~= nil and self._task:isRunning()
  end,

  -- Parse JSON events from Python script stdout
  _handleOutput = function(self, output)
    print(string.format("[DEBUG HANDLEOUTPUT] Entry: %d bytes, callback=%s", #output, tostring(self._callback ~= nil)))

    local lineCount = 0
    -- Split by newlines (may receive multiple events)
    for line in output:gmatch("[^\r\n]+") do
      lineCount = lineCount + 1
      print(string.format("[DEBUG HANDLEOUTPUT] Line %d: %s", lineCount, line))

      local ok, event = pcall(hs.json.decode, line)
      print(string.format("[DEBUG HANDLEOUTPUT] JSON parse ok=%s", tostring(ok)))

      if ok and event and event.type then
        print(string.format("[DEBUG HANDLEOUTPUT] Event type: %s", event.type))
        if self._callback then
          print("[DEBUG HANDLEOUTPUT] Calling callback")
          self._callback(event)
        else
          print("[DEBUG HANDLEOUTPUT] No callback!")
        end
      else
        print("[WhisperDictation] Failed to parse Python output: " .. line)
      end
    end

    print(string.format("[DEBUG HANDLEOUTPUT] Processed %d lines", lineCount))
  end,
}

return RecordingBackends
