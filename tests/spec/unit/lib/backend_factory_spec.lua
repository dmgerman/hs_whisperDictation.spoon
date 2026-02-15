--- BackendFactory Unit Tests
-- Tests backend instantiation from string configuration

describe("BackendFactory", function()
  local BackendFactory
  local EventBus
  local eventBus

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs
    local MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    EventBus = require("lib.event_bus")
    BackendFactory = require("lib.backend_factory")

    eventBus = EventBus.new()
  end)

  describe("create()", function()
    it("creates SoxBackend from 'sox' string", function()
      local backend, err = BackendFactory.create("sox", eventBus, {
        soxCmd = "/opt/homebrew/bin/sox",
        tempDir = "/tmp/test",
      }, "./")

      assert.is_nil(err)
      assert.is_not_nil(backend)
      assert.equals("sox", backend:getName())
    end)

    it("creates StreamingBackend from 'pythonstream' string", function()
      local backend, err = BackendFactory.create("pythonstream", eventBus, {
        pythonExecutable = "python3",
        serverScript = "./whisper_stream.py",
        tcpPort = 12341,
        silenceThreshold = 2.0,
        minChunkDuration = 3.0,
        maxChunkDuration = 600.0,
      }, "./")

      assert.is_nil(err)
      assert.is_not_nil(backend)
      assert.equals("streaming", backend:getName())  -- StreamingBackend returns "streaming"
    end)

    it("returns error for unknown backend", function()
      local backend, err = BackendFactory.create("unknown", eventBus, {}, "./")

      assert.is_nil(backend)
      assert.is_not_nil(err)
      assert.is_true(err:match("Unknown backend") ~= nil)
    end)

    it("passes eventBus to backend", function()
      local backend = BackendFactory.create("sox", eventBus, {}, "./")

      assert.equals(eventBus, backend.eventBus)
    end)

    it("applies default config for sox", function()
      local backend = BackendFactory.create("sox", eventBus, {}, "./")

      assert.is_string(backend.soxCmd)
      assert.is_string(backend.tempDir)
    end)

    it("applies custom config for sox", function()
      local backend = BackendFactory.create("sox", eventBus, {
        soxCmd = "/custom/sox",
        tempDir = "/custom/temp",
      }, "./")

      assert.equals("/custom/sox", backend.soxCmd)
      assert.equals("/custom/temp", backend.tempDir)
    end)

    it("applies default config for pythonstream", function()
      local backend = BackendFactory.create("pythonstream", eventBus, {}, "./")

      assert.is_string(backend.config.pythonExecutable)
      assert.is_number(backend.config.tcpPort)
      assert.is_number(backend.config.silenceThreshold)
      assert.is_number(backend.config.minChunkDuration)
      assert.is_number(backend.config.maxChunkDuration)
    end)

    it("applies custom config for pythonstream", function()
      local backend = BackendFactory.create("pythonstream", eventBus, {
        pythonExecutable = "/custom/python",
        tcpPort = 9999,
        silenceThreshold = 1.5,
        minChunkDuration = 2.0,
        maxChunkDuration = 300.0,
      }, "./")

      assert.equals("/custom/python", backend.config.pythonExecutable)
      assert.equals(9999, backend.config.tcpPort)
      assert.equals(1.5, backend.config.silenceThreshold)
      assert.equals(2.0, backend.config.minChunkDuration)
      assert.equals(300.0, backend.config.maxChunkDuration)
    end)
  end)

  describe("IRecordingBackend interface", function()
    local function testBackendInterface(backendName, config)
      local backend = BackendFactory.create(backendName, eventBus, config, "./")

      it(backendName .. " implements validate()", function()
        assert.is_function(backend.validate)
        local success, err = backend:validate()
        assert.is_boolean(success)
      end)

      it(backendName .. " implements startRecording()", function()
        assert.is_function(backend.startRecording)
      end)

      it(backendName .. " implements stopRecording()", function()
        assert.is_function(backend.stopRecording)
      end)

      it(backendName .. " implements isRecording()", function()
        assert.is_function(backend.isRecording)
        assert.is_boolean(backend:isRecording())
      end)

      it(backendName .. " implements getName()", function()
        assert.is_function(backend.getName)
        assert.is_string(backend:getName())
      end)

      it(backendName .. " implements getDisplayText()", function()
        assert.is_function(backend.getDisplayText)
        local text = backend:getDisplayText("en")
        assert.is_string(text)
      end)
    end

    testBackendInterface("sox", {})
    testBackendInterface("pythonstream", {})
  end)
end)
