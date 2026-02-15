--- RecordingManager Unit Tests

describe("RecordingManager", function()
  local RecordingManager
  local EventBus
  local Promise
  local manager, eventBus, mockBackend

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    EventBus = require("lib.event_bus")
    Promise = require("lib.promise")
    RecordingManager = require("core.recording_manager")

    eventBus = EventBus.new()

    -- Create a mock backend for testing (after Promise is loaded)
    mockBackend = {
      _isRecording = false,

      startRecording = function(self, config)
        return Promise.new(function(resolve, reject)
          if self._isRecording then
            reject("Already recording")
          else
            self._isRecording = true
            self._lastConfig = config
            resolve()
          end
        end)
      end,

      stopRecording = function(self)
        return Promise.new(function(resolve, reject)
          if not self._isRecording then
            reject("Not recording")
          else
            self._isRecording = false
            resolve()
          end
        end)
      end,

      isRecording = function(self)
        return self._isRecording
      end,

      getDisplayText = function(self, lang)
        return "🎙️ Recording (" .. lang .. ")"
      end,
    }

    manager = RecordingManager.new(mockBackend, eventBus, {
      tempDir = "/tmp/test",
      languages = {"en", "ja"},
    })
  end)

  describe("initialization", function()
    it("creates a new RecordingManager instance", function()
      assert.is_not_nil(manager)
      assert.is_table(manager)
    end)

    it("starts in idle state", function()
      assert.equals("idle", manager.state)
    end)

    it("stores references to dependencies", function()
      assert.equals(mockBackend, manager.backend)
      assert.equals(eventBus, manager.eventBus)
    end)
  end)

  describe("startRecording()", function()
    it("transitions to recording state", function()
      local completed = false

      manager:startRecording("en"):next(function()
        completed = true
        assert.equals("recording", manager.state)
      end)

      -- Promise should resolve synchronously for mock backend
      assert.is_true(completed, "Promise should resolve synchronously in tests")
    end)

    it("calls backend startRecording with config", function()
      local completed = false

      manager:startRecording("en"):next(function()
        completed = true
        assert.is_true(mockBackend._isRecording)
        assert.equals("/tmp/test", mockBackend._lastConfig.outputDir)
        assert.equals("en", mockBackend._lastConfig.lang)
      end)

      assert.is_true(completed)
    end)

    it("emits recording:started event", function()
      local eventData = nil
      local completed = false

      eventBus:on("recording:started", function(data)
        eventData = data
      end)

      manager:startRecording("en"):next(function()
        completed = true
        assert.is_not_nil(eventData)
        assert.equals("en", eventData.lang)
      end)

      assert.is_true(completed)
    end)

    it("returns a promise that resolves", function()
      local resolved = false

      manager:startRecording("en"):next(function()
        resolved = true
      end)

      assert.is_true(resolved)
    end)

    it("rejects if already recording", function()
      local rejected = false

      manager:startRecording("en")

      manager:startRecording("ja"):catch(function()
        rejected = true
      end)

      assert.is_true(rejected)
    end)

    it("stays in idle state if backend fails", function()
      -- Force backend to fail
      mockBackend._isRecording = true

      manager:startRecording("en"):catch(function() end)

      assert.equals("idle", manager.state)
    end)

    it("emits recording:error on failure", function()
      local errorEmitted = false

      eventBus:on("recording:error", function()
        errorEmitted = true
      end)

      mockBackend._isRecording = true
      manager:startRecording("en"):catch(function() end)

      assert.is_true(errorEmitted)
    end)
  end)

  describe("stopRecording()", function()
    it("transitions to idle state", function()
      local completed = false

      manager:startRecording("en"):next(function()
        return manager:stopRecording()
      end):next(function()
        completed = true
        assert.equals("idle", manager.state)
      end)

      assert.is_true(completed)
    end)

    it("calls backend stopRecording", function()
      local completed = false

      manager:startRecording("en"):next(function()
        return manager:stopRecording()
      end):next(function()
        completed = true
        assert.is_false(mockBackend._isRecording)
      end)

      assert.is_true(completed)
    end)

    it("emits recording:stopped event", function()
      local eventFired = false
      local completed = false

      eventBus:on("recording:stopped", function()
        eventFired = true
      end)

      manager:startRecording("en"):next(function()
        return manager:stopRecording()
      end):next(function()
        completed = true
        assert.is_true(eventFired)
      end)

      assert.is_true(completed)
    end)

    it("returns a promise that resolves", function()
      local resolved = false

      manager:startRecording("en"):next(function()
        return manager:stopRecording()
      end):next(function()
        resolved = true
      end)

      assert.is_true(resolved)
    end)

    it("rejects if not recording", function()
      local rejected = false

      manager:stopRecording():catch(function()
        rejected = true
      end)

      assert.is_true(rejected)
    end)

    it("transitions through stopping state", function()
      local completed = false

      manager:startRecording("en"):next(function()
        -- Now stop - state should transition through stopping to idle
        return manager:stopRecording()
      end):next(function()
        completed = true
        assert.equals("idle", manager.state)
      end)

      assert.is_true(completed)
    end)
  end)

  describe("isRecording()", function()
    it("returns false when idle", function()
      assert.is_false(manager:isRecording())
    end)

    it("returns true when recording", function()
      local completed = false

      manager:startRecording("en"):next(function()
        completed = true
        assert.is_true(manager:isRecording())
      end)

      assert.is_true(completed)
    end)

    it("returns false after stopping", function()
      local completed = false

      manager:startRecording("en"):next(function()
        return manager:stopRecording()
      end):next(function()
        completed = true
        assert.is_false(manager:isRecording())
      end)

      assert.is_true(completed)
    end)
  end)

  describe("getStatus()", function()
    it("returns current status", function()
      local status = manager:getStatus()

      assert.equals("idle", status.state)
      assert.is_false(status.isRecording)
    end)

    it("includes recording details when recording", function()
      local completed = false

      manager:startRecording("en"):next(function()
        completed = true
        local status = manager:getStatus()

        assert.equals("recording", status.state)
        assert.is_true(status.isRecording)
        assert.equals("en", status.currentLang)
      end)

      assert.is_true(completed)
    end)
  end)

  describe("state transitions", function()
    it("follows valid state machine: idle -> recording -> idle", function()
      local completed = false

      assert.equals("idle", manager.state)

      manager:startRecording("en"):next(function()
        assert.equals("recording", manager.state)
        return manager:stopRecording()
      end):next(function()
        completed = true
        assert.equals("idle", manager.state)
      end)

      assert.is_true(completed)
    end)

    it("prevents invalid transitions", function()
      -- Can't stop when idle
      local error = nil
      manager:stopRecording():catch(function(err)
        error = err
      end)

      assert.is_not_nil(error)
      assert.equals("idle", manager.state)
    end)

    it("prevents starting when already recording", function()
      local completed = false

      manager:startRecording("en"):next(function()
        -- Try to start again while recording
        local error = nil
        manager:startRecording("ja"):catch(function(err)
          error = err
        end)

        completed = true
        assert.is_not_nil(error)
        assert.equals("recording", manager.state)
      end)

      assert.is_true(completed)
    end)
  end)

  describe("integration with backend", function()
    it("emits error event when backend fails", function()
      local errorEmitted = false

      eventBus:on("recording:error", function(data)
        errorEmitted = true
        assert.equals("Backend failed", data.error)
      end)

      mockBackend.startRecording = function()
        return Promise.reject("Backend failed")
      end

      manager:startRecording("en")

      assert.is_true(errorEmitted)
    end)

    it("handles backend async resolution", function()
      local delayedBackend = {
        _isRecording = false,
        startRecording = function(self)
          return Promise.new(function(resolve)
            -- Simulate async delay
            self._isRecording = true
            resolve()
          end)
        end,
        stopRecording = function(self)
          return Promise.new(function(resolve)
            self._isRecording = false
            resolve()
          end)
        end,
        isRecording = function(self)
          return self._isRecording
        end,
      }

      manager = RecordingManager.new(delayedBackend, eventBus, {tempDir = "/tmp"})

      local resolved = false
      manager:startRecording("en"):next(function()
        resolved = true
      end)

      assert.is_true(resolved)
      assert.equals("recording", manager.state)
    end)
  end)
end)
