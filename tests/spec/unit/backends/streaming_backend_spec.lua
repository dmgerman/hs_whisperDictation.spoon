--- StreamingBackend Unit Tests

describe("StreamingBackend", function()
  local StreamingBackend
  local EventBus
  local Promise
  local backend, eventBus

  before_each(function()
    package.path = package.path .. ";./?.lua"

    EventBus = require("lib.event_bus")
    Promise = require("lib.promise")
    StreamingBackend = require("backends.streaming_backend")

    eventBus = EventBus.new()
    backend = StreamingBackend.new(eventBus, {
      pythonExecutable = "python3",
      serverScript = "whisper_stream.py",
      tcpPort = 12341,
    })
  end)

  describe("initialization", function()
    it("creates a new StreamingBackend instance", function()
      assert.is_not_nil(backend)
      assert.is_table(backend)
    end)

    it("starts in idle state", function()
      assert.is_false(backend:isRecording())
    end)

    it("stores reference to eventBus", function()
      assert.equals(eventBus, backend.eventBus)
    end)

    it("stores configuration", function()
      assert.equals("python3", backend.config.pythonExecutable)
      assert.equals("whisper_stream.py", backend.config.serverScript)
      assert.equals(12341, backend.config.tcpPort)
    end)
  end)

  describe("validate()", function()
    it("checks if Python is available", function()
      local success, err = backend:validate()

      -- In test environment, Python should be available
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      end
    end)

    it("checks if server script exists", function()
      local b = StreamingBackend.new(eventBus, {
        pythonExecutable = "python3",
        serverScript = "/nonexistent/script.py",
        tcpPort = 12341,
      })

      local success, err = b:validate()

      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Server script") ~= nil)
    end)
  end)

  describe("getName()", function()
    it("returns 'streaming'", function()
      assert.equals("streaming", backend:getName())
    end)
  end)

  describe("getDisplayText()", function()
    it("returns display text with language", function()
      local text = backend:getDisplayText("en")

      assert.is_string(text)
      assert.is_true(text:match("en") ~= nil)
    end)

    it("includes streaming indicator", function()
      local text = backend:getDisplayText("ja")

      assert.is_string(text)
      assert.is_true(text:match("🎙") ~= nil or text:match("Recording") ~= nil)
    end)
  end)

  describe("server lifecycle", function()
    it("tracks server process state", function()
      assert.is_nil(backend.serverProcess)
      assert.is_nil(backend.tcpSocket)
    end)

    it("provides isServerRunning check", function()
      -- Initially no server
      assert.is_false(backend:_isServerRunning())
    end)
  end)

  describe("event handling", function()
    it("handles chunk_ready events from server", function()
      local chunkEmitted = false
      local chunkData = nil

      eventBus:on("audio:chunk_ready", function(data)
        chunkEmitted = true
        chunkData = data
      end)

      -- Simulate receiving chunk_ready event from Python
      backend:_handleServerEvent({
        type = "chunk_ready",
        chunk_num = 1,
        audio_file = "/tmp/test_chunk_001.wav",
        is_final = false,
      }, "en")

      assert.is_true(chunkEmitted)
      assert.equals(1, chunkData.chunkNum)
      assert.equals("/tmp/test_chunk_001.wav", chunkData.audioFile)
      assert.equals("en", chunkData.lang)
    end)

    it("handles recording_started events from server", function()
      local startEmitted = false

      eventBus:on("streaming:server_started", function()
        startEmitted = true
      end)

      backend:_handleServerEvent({type = "recording_started"}, "en")

      assert.is_true(startEmitted)
    end)

    it("handles recording_stopped events from server", function()
      local stopEmitted = false

      eventBus:on("recording:stopped", function()
        stopEmitted = true
      end)

      backend:_handleServerEvent({type = "recording_stopped"}, "en")

      assert.is_true(stopEmitted)
    end)

    it("handles error events from server", function()
      local errorEmitted = false
      local errorMsg = nil

      eventBus:on("recording:error", function(data)
        errorEmitted = true
        errorMsg = data.error
      end)

      backend:_handleServerEvent({
        type = "error",
        error = "Test error",
      }, "en")

      assert.is_true(errorEmitted)
      assert.equals("Test error", errorMsg)
    end)
  end)

  describe("TCP communication", function()
    it("provides sendCommand method", function()
      -- Should not crash even without connection
      local success = backend:_sendCommand({command = "test"})
      assert.is_boolean(success)
    end)
  end)
end)
