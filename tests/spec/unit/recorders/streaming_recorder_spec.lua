--- StreamingRecorder Unit Tests

describe("StreamingRecorder", function()
  local StreamingRecorder
  local MockHS
  local recorder

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs
    MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    StreamingRecorder = require("recorders.streaming.streaming_recorder")

    recorder = StreamingRecorder.new({
      pythonPath = "/usr/bin/python3",
      serverScript = "/path/to/whisper_stream.py",
      tcpPort = 12341,
      tempDir = "/tmp/whisper_dict"
    })
  end)

  after_each(function()
    if recorder then
      recorder:cleanup()
    end
    recorder = nil
    MockHS._resetAll()
    _G.hs = nil
  end)

  describe("initialization", function()
    it("creates a new StreamingRecorder instance", function()
      assert.is_not_nil(recorder)
      assert.is_table(recorder)
    end)

    it("starts in idle state", function()
      assert.is_false(recorder:isRecording())
    end)

    it("stores python path", function()
      assert.equals("/usr/bin/python3", recorder.pythonPath)
    end)

    it("stores server script path", function()
      assert.equals("/path/to/whisper_stream.py", recorder.serverScript)
    end)

    it("stores TCP port", function()
      assert.equals(12341, recorder.tcpPort)
    end)

    it("stores temp directory", function()
      assert.equals("/tmp/whisper_dict", recorder.tempDir)
    end)

    it("initializes with nil server process", function()
      assert.is_nil(recorder.serverProcess)
    end)

    it("initializes with nil TCP socket", function()
      assert.is_nil(recorder.tcpSocket)
    end)

    it("uses default python path if not provided", function()
      local defaultRecorder = StreamingRecorder.new({})
      assert.equals("python3", defaultRecorder.pythonPath)
    end)

    it("uses default TCP port if not provided", function()
      local defaultRecorder = StreamingRecorder.new({})
      assert.equals(12341, defaultRecorder.tcpPort)
    end)

    it("uses default temp dir if not provided", function()
      local defaultRecorder = StreamingRecorder.new({})
      assert.equals("/tmp/whisper_dict", defaultRecorder.tempDir)
    end)

    it("handles nil config", function()
      local defaultRecorder = StreamingRecorder.new(nil)
      assert.is_not_nil(defaultRecorder)
      assert.equals("python3", defaultRecorder.pythonPath)
    end)

    it("stores audio input device if provided", function()
      local customRecorder = StreamingRecorder.new({
        audioInputDevice = "BlackHole 2ch"
      })
      assert.equals("BlackHole 2ch", customRecorder.audioInputDevice)
    end)

    it("has nil audio input device by default", function()
      assert.is_nil(recorder.audioInputDevice)
    end)
  end)

  describe("validate()", function()
    it("returns option-style tuple (success, error)", function()
      local success, err = recorder:validate()
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      else
        assert.is_nil(err)
      end
    end)

    it("checks if python executable exists", function()
      -- Use a definitely non-existent Python path
      local testRecorder = StreamingRecorder.new({
        pythonPath = "/nonexistent/path/python3",
        serverScript = "/path/to/whisper_stream.py"
      })

      local success, err = testRecorder:validate()
      assert.is_boolean(success)
      -- Should fail because python doesn't exist
      if not success then
        assert.is_string(err)
        assert.is_true(err:match("Python") ~= nil or err:match("python") ~= nil)
      end
    end)

    it("checks if server script exists", function()
      -- Mock python exists but script doesn't
      MockHS.fs._registerFile("/usr/bin/python3", { mode = "file", size = 1024 })

      local success, err = recorder:validate()
      if not success then
        assert.is_string(err)
        assert.is_true(err:match("script") ~= nil or err:match("Server") ~= nil)
      end
    end)

    it("returns true if both python and script exist", function()
      MockHS.fs._registerFile("/usr/bin/python3", { mode = "file", size = 1024 })
      MockHS.fs._registerFile("/path/to/whisper_stream.py", { mode = "file", size = 1024 })

      local success, err = recorder:validate()
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("returns false if python not found", function()
      local customRecorder = StreamingRecorder.new({
        pythonPath = "/nonexistent/python3",
        serverScript = "/path/to/whisper_stream.py"
      })

      local success, err = customRecorder:validate()
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Python") ~= nil or err:match("python") ~= nil)
    end)

    it("returns false if server script not found", function()
      MockHS.fs._registerFile("/usr/bin/python3", { mode = "file", size = 1024 })

      local customRecorder = StreamingRecorder.new({
        pythonPath = "/usr/bin/python3",
        serverScript = "/nonexistent/script.py"
      })

      local success, err = customRecorder:validate()
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("script") ~= nil or err:match("Server") ~= nil)
    end)
  end)

  describe("getName()", function()
    it("returns 'streaming'", function()
      assert.equals("streaming", recorder:getName())
    end)
  end)

  describe("isRecording()", function()
    it("returns false initially", function()
      assert.is_false(recorder:isRecording())
    end)

    it("returns true after starting recording", function()
      -- Set flag directly to test
      recorder._isRecording = true
      assert.is_true(recorder:isRecording())
    end)

    it("returns false after stopping recording", function()
      recorder._isRecording = true
      recorder._isRecording = false
      assert.is_false(recorder:isRecording())
    end)
  end)

  describe("startRecording()", function()
    it("returns option-style tuple (success, error)", function()
      local config = {
        outputDir = "/tmp/test",
        lang = "en"
      }

      local success, err = recorder:startRecording(config, function() end, function() end)
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      else
        assert.is_nil(err)
      end
    end)

    it("returns false if already recording", function()
      recorder._isRecording = true

      local success, err = recorder:startRecording({}, function() end, function() end)
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Already") ~= nil or err:match("already") ~= nil)

      recorder._isRecording = false
    end)

    it("sets _isRecording flag on successful start", function()
      -- Mock server startup to simulate successful start
      recorder._startServer = function(self, outputDir, prefix)
        self.serverProcess = {
          isRunning = function() return true end,
          terminate = function() end
        }
        return true, nil
      end

      recorder._connectTCPSocket = function(self)
        self.tcpSocket = {
          read = function() end,
          write = function() return true end
        }
      end

      local config = {
        outputDir = "/tmp/test",
        lang = "en"
      }

      recorder:startRecording(config, function() end, function() end)
      assert.is_true(recorder._isRecording)
    end)

    it("stores callbacks for later use", function()
      -- Mock server startup
      recorder._startServer = function(self) self.serverProcess = {}; return true, nil end
      recorder._connectTCPSocket = function(self) self.tcpSocket = { read = function() end, write = function() return true end } end

      local chunkCallback = function() end
      local errorCallback = function() end

      recorder:startRecording({ outputDir = "/tmp", lang = "en" }, chunkCallback, errorCallback)

      assert.equals(chunkCallback, recorder._onChunk)
      assert.equals(errorCallback, recorder._onError)
    end)

    it("stores current language", function()
      -- Mock server startup
      recorder._startServer = function(self) self.serverProcess = {}; return true, nil end
      recorder._connectTCPSocket = function(self) self.tcpSocket = { read = function() end, write = function() return true end } end

      recorder:startRecording({ outputDir = "/tmp", lang = "en" }, function() end, function() end)

      assert.equals("en", recorder._currentLang)
    end)

    it("resets chunk count on start", function()
      recorder._chunkCount = 5

      -- Mock server startup
      recorder._startServer = function(self) self.serverProcess = {}; return true, nil end
      recorder._connectTCPSocket = function(self) self.tcpSocket = { read = function() end, write = function() return true end } end

      recorder:startRecording({ outputDir = "/tmp", lang = "en" }, function() end, function() end)

      assert.equals(0, recorder._chunkCount)
    end)
  end)

  describe("stopRecording()", function()
    it("returns option-style tuple (success, error)", function()
      local success, err = recorder:stopRecording(function() end, function() end)
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      else
        assert.is_nil(err)
      end
    end)

    it("returns false if not recording", function()
      local success, err = recorder:stopRecording(function() end, function() end)
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Not") ~= nil or err:match("not") ~= nil)
    end)

    it("clears _isRecording flag", function()
      recorder._isRecording = true
      recorder.tcpSocket = {
        test_mode = true,
        write = function() return true end
      }

      recorder:stopRecording(function() end, function() end)
      assert.is_false(recorder._isRecording)
    end)

    it("sends stop command to server", function()
      recorder._isRecording = true
      recorder.tcpSocket = {
        test_mode = true,
        write = function() return true end
      }

      local commandSent = false
      recorder._sendCommand = function(self, cmd)
        if cmd.command == "stop_recording" then
          commandSent = true
        end
        return true
      end

      recorder:stopRecording(function() end, function() end)
      assert.is_true(commandSent)
    end)
  end)

  describe("cleanup()", function()
    it("shuts down server if running", function()
      recorder.serverProcess = {
        test_mode = true,
        terminate = function() end
      }
      recorder.tcpSocket = {
        test_mode = true,
        write = function() return true end,
        disconnect = function() end
      }

      recorder:cleanup()

      assert.is_nil(recorder.serverProcess)
      assert.is_nil(recorder.tcpSocket)
    end)

    it("clears recording state", function()
      recorder._isRecording = true
      recorder._currentLang = "en"
      recorder._chunkCount = 5

      recorder:cleanup()

      assert.is_false(recorder._isRecording)
      assert.is_nil(recorder._currentLang)
      assert.equals(0, recorder._chunkCount)
    end)

    it("is safe to call when not recording", function()
      assert.has_no.errors(function()
        recorder:cleanup()
      end)
    end)

    it("is safe to call multiple times", function()
      recorder:cleanup()
      assert.has_no.errors(function()
        recorder:cleanup()
      end)
    end)
  end)

  describe("multi-chunk emission", function()
    it("increments chunk count for each chunk", function()
      assert.equals(0, recorder._chunkCount)

      recorder:_handleServerEvent({ type = "chunk_ready", chunk_num = 1, audio_file = "/tmp/1.wav", is_final = false }, "en")
      assert.equals(1, recorder._chunkCount)

      recorder:_handleServerEvent({ type = "chunk_ready", chunk_num = 2, audio_file = "/tmp/2.wav", is_final = false }, "en")
      assert.equals(2, recorder._chunkCount)

      recorder:_handleServerEvent({ type = "chunk_ready", chunk_num = 3, audio_file = "/tmp/3.wav", is_final = true }, "en")
      assert.equals(3, recorder._chunkCount)
    end)

    it("emits chunk via callback when chunk_ready event received", function()
      local chunksReceived = {}

      recorder._onChunk = function(audioFile, chunkNum, isFinal)
        table.insert(chunksReceived, { audioFile = audioFile, chunkNum = chunkNum, isFinal = isFinal })
      end

      recorder:_handleServerEvent({ type = "chunk_ready", chunk_num = 1, audio_file = "/tmp/chunk1.wav", is_final = false }, "en")
      recorder:_handleServerEvent({ type = "chunk_ready", chunk_num = 2, audio_file = "/tmp/chunk2.wav", is_final = true }, "en")

      assert.equals(2, #chunksReceived)
      assert.equals("/tmp/chunk1.wav", chunksReceived[1].audioFile)
      assert.equals(1, chunksReceived[1].chunkNum)
      assert.is_false(chunksReceived[1].isFinal)

      assert.equals("/tmp/chunk2.wav", chunksReceived[2].audioFile)
      assert.equals(2, chunksReceived[2].chunkNum)
      assert.is_true(chunksReceived[2].isFinal)
    end)

    it("handles final chunk correctly", function()
      local finalChunk = nil

      recorder._onChunk = function(audioFile, chunkNum, isFinal)
        if isFinal then
          finalChunk = { audioFile = audioFile, chunkNum = chunkNum, isFinal = isFinal }
        end
      end

      recorder:_handleServerEvent({ type = "chunk_ready", chunk_num = 1, audio_file = "/tmp/1.wav", is_final = false }, "en")
      assert.is_nil(finalChunk)

      recorder:_handleServerEvent({ type = "chunk_ready", chunk_num = 2, audio_file = "/tmp/2.wav", is_final = true }, "en")
      assert.is_not_nil(finalChunk)
      assert.equals(2, finalChunk.chunkNum)
      assert.is_true(finalChunk.isFinal)
    end)
  end)

  describe("error handling", function()
    it("calls onError when server sends error event", function()
      local errorMsg = nil

      recorder._onError = function(msg)
        errorMsg = msg
      end

      recorder:_handleServerEvent({ type = "error", error = "Server error occurred" }, "en")

      assert.is_not_nil(errorMsg)
      assert.equals("Server error occurred", errorMsg)
    end)

    it("handles server crash gracefully", function()
      recorder.serverProcess = { test_mode = true }
      recorder._isRecording = true

      -- Simulate server exit
      local exitCallback = nil
      MockHS.task._registerExitCallback(function(cb) exitCallback = cb end)

      assert.has_no.errors(function()
        if exitCallback then
          exitCallback(1, "", "Server crashed")
        end
      end)
    end)

    it("handles invalid JSON from server", function()
      local errorCalled = false

      recorder._onError = function(msg)
        errorCalled = true
      end

      -- Simulate invalid data
      assert.has_no.errors(function()
        recorder:_handleSocketData("invalid json{}", 1)
      end)
    end)

    it("handles silence warning event", function()
      local errorMsg = nil

      recorder._onError = function(msg)
        errorMsg = msg
      end

      recorder:_handleServerEvent({
        type = "silence_warning",
        message = "Microphone appears to be off"
      }, "en")

      assert.is_not_nil(errorMsg)
      assert.is_true(errorMsg:match("Microphone") ~= nil)
    end)
  end)

  describe("server lifecycle", function()
    it("starts server on first recording", function()
      -- Mock server startup by manually setting server process
      local mockServer = {
        isRunning = function() return true end,
        terminate = function() end
      }
      local mockSocket = {
        read = function() end,
        write = function() return true end,
        disconnect = function() end
      }

      -- Override _startServer to simulate successful startup
      recorder._startServer = function(self, outputDir, prefix)
        self.serverProcess = mockServer
        return true, nil
      end

      -- Override _connectTCPSocket to simulate connection
      recorder._connectTCPSocket = function(self)
        self.tcpSocket = mockSocket
      end

      assert.is_nil(recorder.serverProcess)

      local success = recorder:startRecording({ outputDir = "/tmp", lang = "en" }, function() end, function() end)

      assert.is_true(success)
      assert.is_not_nil(recorder.serverProcess)
      assert.is_true(recorder._isRecording)
    end)

    it("reuses server on subsequent recordings", function()
      -- Mock server already running
      local mockServer = {
        isRunning = function() return true end,
        terminate = function() end
      }
      local mockSocket = {
        read = function() end,
        write = function() return true end,
        disconnect = function() end
      }

      recorder.serverProcess = mockServer
      recorder.tcpSocket = mockSocket

      -- First recording
      local success1 = recorder:startRecording({ outputDir = "/tmp", lang = "en" }, function() end, function() end)
      assert.is_true(success1)
      local firstServer = recorder.serverProcess

      recorder:stopRecording(function() end, function() end)

      -- Second recording - server should still be running (not shutdown)
      local success2 = recorder:startRecording({ outputDir = "/tmp", lang = "fr" }, function() end, function() end)
      assert.is_true(success2)
      assert.equals(firstServer, recorder.serverProcess)  -- Same server instance
    end)

    it("cleanup shuts down server", function()
      recorder.serverProcess = { test_mode = true }
      recorder.tcpSocket = { test_mode = true }

      recorder:cleanup()

      assert.is_nil(recorder.serverProcess)
      assert.is_nil(recorder.tcpSocket)
    end)
  end)

  describe("audio input device", function()
    it("uses specified audio input device in sox command", function()
      local customRecorder = StreamingRecorder.new({
        audioInputDevice = "BlackHole 2ch",
        pythonPath = "/usr/bin/python3",
        serverScript = "/path/to/script.py"
      })

      assert.equals("BlackHole 2ch", customRecorder.audioInputDevice)
    end)

    it("passes audio input device to server script", function()
      MockHS.fs._registerFile("/usr/bin/python3", { mode = "file", size = 1024 })
      MockHS.fs._registerFile("/path/to/script.py", { mode = "file", size = 1024 })

      local customRecorder = StreamingRecorder.new({
        audioInputDevice = "BlackHole 2ch",
        pythonPath = "/usr/bin/python3",
        serverScript = "/path/to/script.py"
      })

      local taskArgs = nil
      MockHS.task._registerCreationCallback(function(cmd, callback, args)
        taskArgs = args
        return { start = function() end, terminate = function() end }
      end)

      customRecorder:startRecording({ outputDir = "/tmp", lang = "en" }, function() end, function() end)

      assert.is_not_nil(taskArgs)
      -- Check if audio device is in args (uses --audio-input, not --audio-device)
      local hasDeviceArg = false
      for i, arg in ipairs(taskArgs) do
        if arg == "--audio-input" and taskArgs[i + 1] == "BlackHole 2ch" then
          hasDeviceArg = true
          break
        end
      end
      assert.is_true(hasDeviceArg)
    end)
  end)
end)
