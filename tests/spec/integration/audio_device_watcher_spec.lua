-- tests/spec/integration/audio_device_watcher_spec.lua
-- Tests for the system-default-input watcher that restarts the streaming
-- Python server when the user changes microphone.

local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS

describe("audio device watcher", function()
  local spoonPath = os.getenv("PWD") .. "/"
  local obj

  local function makeMockRecorder()
    local r = {
      cleanupCalls = 0,
      warmupCalls = 0,
    }
    function r:getName() return "streaming" end
    function r:cleanup() self.cleanupCalls = self.cleanupCalls + 1 end
    function r:warmup() self.warmupCalls = self.warmupCalls + 1; return true, nil end
    return r
  end

  local function startSpoonWithStreaming()
    MockHS.fs._registerFile("/opt/homebrew/bin/python3", { mode = "file", size = 1000 })
    MockHS.fs._registerFile(spoonPath .. "recorders/streaming/whisper_stream.py", { mode = "file", size = 5000 })
    MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })
    obj.config.recorder = "streaming"
    return obj:start()
  end

  before_each(function()
    MockHS._resetAll()
    obj = dofile(spoonPath .. "init.lua")
    obj.logger.enableConsole = false
  end)

  after_each(function()
    pcall(function() obj:stop() end)
  end)

  describe("registration", function()
    it("starts the watcher when recorder is streaming", function()
      startSpoonWithStreaming()
      assert.is_true(obj.audioDeviceWatcherActive)
      assert.is_true(MockHS.audiodevice.watcher._isRunning())
    end)

    it("does not start the watcher when recorder is sox", function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })
      obj.config.recorder = "sox"
      obj:start()
      assert.is_false(obj.audioDeviceWatcherActive)
      assert.is_false(MockHS.audiodevice.watcher._isRunning())
    end)

    it("stops the watcher in stop()", function()
      startSpoonWithStreaming()
      obj:stop()
      assert.is_false(obj.audioDeviceWatcherActive)
      assert.is_false(MockHS.audiodevice.watcher._isRunning())
    end)
  end)

  describe("event filtering", function()
    it("ignores events that are not 'dIn '", function()
      startSpoonWithStreaming()
      local mock = makeMockRecorder()
      obj.recorder = mock

      MockHS.audiodevice.watcher._trigger("dOut")
      MockHS.audiodevice.watcher._trigger("dev#")
      MockHS.audiodevice.watcher._trigger("nul ")

      assert.equals(0, mock.cleanupCalls)
      assert.equals(0, mock.warmupCalls)
    end)
  end)

  describe("restart while idle", function()
    it("calls cleanup + warmup on 'dIn ' when manager is IDLE", function()
      startSpoonWithStreaming()
      local mock = makeMockRecorder()
      obj.recorder = mock

      -- Manager exists after start(); state defaults to IDLE
      assert.equals("IDLE", obj.manager.state)

      MockHS.audiodevice.watcher._trigger("dIn ")

      assert.equals(1, mock.cleanupCalls)
      assert.equals(1, mock.warmupCalls)
      assert.is_false(obj.audioDeviceRestartPending)
    end)
  end)

  describe("restart while busy", function()
    it("defers when manager is RECORDING", function()
      startSpoonWithStreaming()
      local mock = makeMockRecorder()
      obj.recorder = mock
      obj.manager.state = "RECORDING"

      MockHS.audiodevice.watcher._trigger("dIn ")

      assert.equals(0, mock.cleanupCalls)
      assert.equals(0, mock.warmupCalls)
      assert.is_true(obj.audioDeviceRestartPending)
    end)

    it("defers when manager is TRANSCRIBING", function()
      startSpoonWithStreaming()
      local mock = makeMockRecorder()
      obj.recorder = mock
      obj.manager.state = "TRANSCRIBING"

      MockHS.audiodevice.watcher._trigger("dIn ")

      assert.equals(0, mock.cleanupCalls)
      assert.is_true(obj.audioDeviceRestartPending)
    end)

    it("fires the deferred restart on transition to IDLE", function()
      startSpoonWithStreaming()
      local mock = makeMockRecorder()
      obj.recorder = mock
      obj.manager.state = "RECORDING"

      MockHS.audiodevice.watcher._trigger("dIn ")
      assert.is_true(obj.audioDeviceRestartPending)

      -- Simulate manager transition through TRANSCRIBING -> IDLE
      obj.manager.state = "IDLE"
      obj.manager.onStateChanged("IDLE", "TRANSCRIBING", {})

      assert.equals(1, mock.cleanupCalls)
      assert.equals(1, mock.warmupCalls)
      assert.is_false(obj.audioDeviceRestartPending)
    end)

    it("does nothing on IDLE transition when no restart is pending", function()
      startSpoonWithStreaming()
      local mock = makeMockRecorder()
      obj.recorder = mock

      obj.manager.onStateChanged("IDLE", "TRANSCRIBING", {})

      assert.equals(0, mock.cleanupCalls)
      assert.equals(0, mock.warmupCalls)
    end)
  end)
end)
