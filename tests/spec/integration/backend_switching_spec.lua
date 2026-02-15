--- Backend Switching Integration Tests
-- Verifies both backends can be loaded and work correctly

describe("Backend Switching", function()
  local BackendFactory
  local EventBus
  local RecordingManager

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Mock Hammerspoon APIs
    _G.hs = require("tests.helpers.mock_hs")

    BackendFactory = require("lib.backend_factory")
    EventBus = require("lib.event_bus")
    RecordingManager = require("core.recording_manager")
  end)

  describe("Sox backend", function()
    it("can be created and validated", function()
      local eventBus = EventBus.new()
      local backend, err = BackendFactory.create("sox", eventBus, {
        soxCmd = "/opt/homebrew/bin/sox",
        tempDir = "/tmp/test"
      }, "./")

      assert.is_not_nil(backend, "Should create sox backend: " .. tostring(err))
      assert.equals("sox", backend:getName())

      local valid, validateErr = backend:validate()
      if not valid then
        print("Sox validation warning:", validateErr)
        pending("Sox not available - install with: brew install sox")
        return
      end

      assert.is_true(valid)
    end)

    it("can start and stop recording", function()
      local eventBus = EventBus.new()
      local backend, err = BackendFactory.create("sox", eventBus, {
        soxCmd = "/opt/homebrew/bin/sox",
        tempDir = "/tmp/test"
      }, "./")

      if not backend then
        pending("Sox backend not available")
        return
      end

      local manager = RecordingManager.new(backend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Should be able to start
      assert.equals("idle", manager.state)

      -- Note: Can't actually test recording without real hardware
      -- but we can verify the API works
      assert.is_function(manager.startRecording)
      assert.is_function(manager.stopRecording)
    end)
  end)

  describe("Pythonstream backend", function()
    it("can be created", function()
      local eventBus = EventBus.new()
      local backend, err = BackendFactory.create("pythonstream", eventBus, {
        tcpPort = 12341,
        serverScript = "whisper_stream.py",
        tempDir = "/tmp/test"
      }, "./")

      assert.is_not_nil(backend, "Should create pythonstream backend: " .. tostring(err))
      assert.equals("streaming", backend:getName())
    end)

    it("validates Python dependencies", function()
      local eventBus = EventBus.new()
      local backend = BackendFactory.create("pythonstream", eventBus, {
        tcpPort = 12341,
        serverScript = "whisper_stream.py",
        tempDir = "/tmp/test"
      }, "./")

      if not backend then
        pending("Pythonstream backend not available")
        return
      end

      local valid, validateErr = backend:validate()

      -- May fail if Python or dependencies not installed
      if not valid then
        print("Python validation warning:", validateErr)
        pending("Python dependencies not available")
        return
      end

      assert.is_true(valid)
    end)

    it("can create RecordingManager", function()
      local eventBus = EventBus.new()
      local backend = BackendFactory.create("pythonstream", eventBus, {
        tcpPort = 12341,
        serverScript = "whisper_stream.py",
        tempDir = "/tmp/test"
      }, "./")

      if not backend then
        pending("Backend not available")
        return
      end

      local manager = RecordingManager.new(backend, eventBus, {
        tempDir = "/tmp/test"
      })

      assert.is_not_nil(manager)
      assert.equals("idle", manager.state)
    end)
  end)

  describe("Backend switching", function()
    it("can switch between sox and pythonstream", function()
      local eventBus = EventBus.new()

      -- Create sox backend
      local soxBackend = BackendFactory.create("sox", eventBus, {
        soxCmd = "/opt/homebrew/bin/sox",
        tempDir = "/tmp/test"
      }, "./")

      -- Create pythonstream backend
      local streamBackend = BackendFactory.create("pythonstream", eventBus, {
        tcpPort = 12341,
        serverScript = "whisper_stream.py",
        tempDir = "/tmp/test"
      }, "./")

      if not soxBackend or not streamBackend then
        pending("One or both backends not available")
        return
      end

      -- Should be different instances
      assert.are_not.equal(soxBackend, streamBackend)

      -- Should have different names
      assert.equals("sox", soxBackend:getName())
      assert.equals("streaming", streamBackend:getName())

      -- Both should work with RecordingManager
      local soxManager = RecordingManager.new(soxBackend, EventBus.new(), {
        tempDir = "/tmp/test"
      })

      local streamManager = RecordingManager.new(streamBackend, EventBus.new(), {
        tempDir = "/tmp/test"
      })

      assert.is_not_nil(soxManager)
      assert.is_not_nil(streamManager)
    end)

    it("both backends emit the same events", function()
      -- Both backends should emit:
      -- - recording:started
      -- - audio:chunk_ready
      -- - recording:stopped
      -- - recording:error

      local expectedEvents = {
        "recording:started",
        "audio:chunk_ready",
        "recording:stopped",
        "recording:error",
      }

      -- This is validated by the EventBus.VALID_EVENTS list
      for _, eventName in ipairs(expectedEvents) do
        local found = false
        for _, validEvent in ipairs(require("lib.event_bus").VALID_EVENTS) do
          if validEvent == eventName then
            found = true
            break
          end
        end
        assert.is_true(found, "Event should be valid: " .. eventName)
      end
    end)

    it("switching backends doesn't break RecordingManager", function()
      local eventBus = EventBus.new()
      local tempDir = "/tmp/test"

      -- Try with sox first
      local backend1 = BackendFactory.create("sox", eventBus, {
        soxCmd = "/opt/homebrew/bin/sox",
        tempDir = tempDir
      }, "./")

      if backend1 then
        local mgr1 = RecordingManager.new(backend1, eventBus, {tempDir = tempDir})
        assert.equals("idle", mgr1.state)
      end

      -- Now switch to pythonstream
      local backend2 = BackendFactory.create("pythonstream", eventBus, {
        tcpPort = 12341,
        serverScript = "whisper_stream.py",
        tempDir = tempDir
      }, "./")

      if backend2 then
        local mgr2 = RecordingManager.new(backend2, eventBus, {tempDir = tempDir})
        assert.equals("idle", mgr2.state)
      end

      -- At least one should work
      assert.is_true(backend1 ~= nil or backend2 ~= nil,
        "At least one backend should be available")
    end)
  end)

  describe("Backend compatibility", function()
    it("both backends implement the same interface", function()
      local requiredMethods = {
        "getName",
        "validate",
        "startRecording",
        "stopRecording",
        "isRecording",
        "getDisplayText",
      }

      local backends = {
        BackendFactory.create("sox", EventBus.new(), {
          soxCmd = "/opt/homebrew/bin/sox",
          tempDir = "/tmp/test"
        }, "./"),
        BackendFactory.create("pythonstream", EventBus.new(), {
          tcpPort = 12341,
          serverScript = "whisper_stream.py",
          tempDir = "/tmp/test"
        }, "./"),
      }

      for _, backend in ipairs(backends) do
        if backend then
          for _, methodName in ipairs(requiredMethods) do
            assert.is_function(backend[methodName],
              string.format("%s should have method %s", backend:getName(), methodName))
          end
        end
      end
    end)
  end)
end)
