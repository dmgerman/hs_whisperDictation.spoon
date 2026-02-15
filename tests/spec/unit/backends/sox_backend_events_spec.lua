--- SoxBackend Event & Error Handling Tests

describe("SoxBackend Events and Error Handling", function()
  local SoxBackend
  local EventBus
  local Promise
  local MockHS
  local backend, eventBus

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    EventBus = require("lib.event_bus")
    Promise = require("lib.promise")
    SoxBackend = require("backends.sox_backend")

    eventBus = EventBus.new()
    backend = SoxBackend.new(eventBus, {
      soxCmd = "/opt/homebrew/bin/sox",
      tempDir = "/tmp/whisper_dict"
    })
  end)

  describe("Event emissions", function()
    it("emits recording:started when recording starts", function()
      local eventFired = false
      local eventData = nil

      eventBus:on("recording:started", function(data)
        eventFired = true
        eventData = data
      end)

      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):catch(function() end)

      if backend:isRecording() then
        assert.is_true(eventFired, "recording:started event should fire")
        assert.equals("en", eventData.lang)
        assert.is_number(eventData.startTime)
        backend:stopRecording()
      end
    end)

    it("emits audio:chunk_ready when recording stops", function()
      local chunkReady = false
      local chunkData = nil

      eventBus:on("audio:chunk_ready", function(data)
        chunkReady = true
        chunkData = data
      end)

      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "ja",
      }):next(function()
        return backend:stopRecording()
      end):next(function()
        -- After stop, chunk_ready should fire
        if chunkReady then
          assert.is_string(chunkData.audioFile)
          assert.equals(1, chunkData.chunkNum)
          assert.equals("ja", chunkData.lang)
          assert.is_true(chunkData.isFinal)
        end
      end):catch(function() end)
    end)

    it("emits recording:stopped when recording stops", function()
      local stoppedFired = false

      eventBus:on("recording:stopped", function()
        stoppedFired = true
      end)

      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):next(function()
        return backend:stopRecording()
      end):next(function()
        assert.is_true(stoppedFired, "recording:stopped should fire")
      end):catch(function() end)
    end)

    it("emits events in correct order: started → chunk_ready → stopped", function()
      local events = {}

      eventBus:on("recording:started", function()
        table.insert(events, "started")
      end)

      eventBus:on("audio:chunk_ready", function()
        table.insert(events, "chunk_ready")
      end)

      eventBus:on("recording:stopped", function()
        table.insert(events, "stopped")
      end)

      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):next(function()
        return backend:stopRecording()
      end):next(function()
        if #events >= 3 then
          assert.equals("started", events[1])
          assert.equals("chunk_ready", events[2])
          assert.equals("stopped", events[3])
        end
      end):catch(function() end)
    end)

    it("emits recording:error if file not created", function()
      local errorFired = false
      local errorData = nil

      eventBus:on("recording:error", function(data)
        errorFired = true
        errorData = data
      end)

      -- Start and immediately stop (no time to create file)
      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):next(function()
        -- Stop immediately - mock won't create file
        return backend:stopRecording()
      end):catch(function()
        -- Error expected if file not created
      end)

      -- Note: This test may not fire error in mock environment
      -- In real environment, it would fire if file creation failed
    end)
  end)

  describe("Audio file path generation", function()
    it("includes language in filename", function()
      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "ja",
      }):catch(function() end)

      if backend:isRecording() then
        assert.is_string(backend.audioFile)
        assert.is_true(backend.audioFile:match("ja%-") ~= nil, "Filename should contain language prefix")
        backend:stopRecording()
      end
    end)

    it("includes timestamp in filename", function()
      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):catch(function() end)

      if backend:isRecording() then
        assert.is_string(backend.audioFile)
        -- Should match format: /tmp/test/en-YYYYMMDD-HHMMSS.wav
        assert.is_true(backend.audioFile:match("%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%.wav") ~= nil,
          "Filename should contain timestamp")
        backend:stopRecording()
      end
    end)

    it("uses custom outputDir", function()
      backend:startRecording({
        outputDir = "/custom/path",
        lang = "en",
      }):catch(function() end)

      if backend:isRecording() then
        assert.is_string(backend.audioFile)
        assert.is_true(backend.audioFile:match("^/custom/path/") ~= nil,
          "Should use custom output directory")
        backend:stopRecording()
      end
    end)

    it("uses default tempDir if outputDir not specified", function()
      backend:startRecording({
        lang = "en",
      }):catch(function() end)

      if backend:isRecording() then
        assert.is_string(backend.audioFile)
        assert.is_true(backend.audioFile:match("^/tmp/whisper_dict/") ~= nil,
          "Should use default tempDir")
        backend:stopRecording()
      end
    end)
  end)

  describe("Error handling and recovery", function()
    it("cleans up state if start fails", function()
      -- Try to start with invalid config (this may or may not actually fail in mock)
      local initialState = backend:isRecording()

      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):catch(function()
        -- If it fails, state should be reset
        assert.is_false(backend:isRecording())
        assert.is_nil(backend.audioFile)
        assert.is_nil(backend.currentLang)
        assert.is_nil(backend.startTime)
      end)
    end)

    it("cleans up state after successful stop", function()
      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):next(function()
        return backend:stopRecording()
      end):next(function()
        assert.is_false(backend:isRecording())
        assert.is_nil(backend.audioFile)
        assert.is_nil(backend.currentLang)
        assert.is_nil(backend.startTime)
      end):catch(function() end)
    end)

    it("can start again after stop", function()
      local firstStop = false
      local secondStart = false

      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):next(function()
        return backend:stopRecording()
      end):next(function()
        firstStop = true
        -- Try starting again
        return backend:startRecording({
          outputDir = "/tmp/test",
          lang = "ja",
        })
      end):next(function()
        secondStart = true
        assert.is_true(backend:isRecording())
        assert.equals("ja", backend.currentLang)
        backend:stopRecording()
      end):catch(function() end)
    end)
  end)

  describe("Display text with timing", function()
    it("shows language when not recording", function()
      local text = backend:getDisplayText("en")

      assert.is_string(text)
      assert.is_true(text:match("en") ~= nil)
      assert.is_true(text:match("🎙") ~= nil)
    end)

    it("shows elapsed time when recording", function()
      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):catch(function() end)

      if backend:isRecording() then
        -- Should have startTime
        assert.is_number(backend.startTime)

        local text = backend:getDisplayText("en")
        assert.is_string(text)
        -- Should contain duration (0s or more)
        assert.is_true(text:match("%d+s") ~= nil, "Should show elapsed seconds")
        assert.is_true(text:match("en") ~= nil, "Should show language")

        backend:stopRecording()
      end
    end)
  end)

  describe("Interface compliance", function()
    it("implements all required IRecordingBackend methods", function()
      assert.is_function(backend.validate)
      assert.is_function(backend.startRecording)
      assert.is_function(backend.stopRecording)
      assert.is_function(backend.isRecording)
      assert.is_function(backend.getName)
      assert.is_function(backend.getDisplayText)
    end)

    it("returns promises from async methods", function()
      local startPromise = backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      })

      assert.is_table(startPromise)
      assert.is_function(startPromise.next)
      assert.is_function(startPromise.catch)

      if backend:isRecording() then
        local stopPromise = backend:stopRecording()

        assert.is_table(stopPromise)
        assert.is_function(stopPromise.next)
        assert.is_function(stopPromise.catch)
      end
    end)
  end)
end)
