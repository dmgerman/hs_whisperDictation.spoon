--- Streaming Backend Error Handling Tests

local mock_hs = require("tests.helpers.mock_hs")

describe("StreamingBackend error handling", function()
  local StreamingBackend
  local EventBus
  local backend
  local eventBus

  before_each(function()
    _G.hs = mock_hs
    StreamingBackend = require("backends.streaming_backend")
    EventBus = require("lib.event_bus")

    eventBus = EventBus.new()
    backend = StreamingBackend.new(eventBus, {
      tcpPort = 12345,
      serverScript = "/tmp/test.py",
      pythonExecutable = "python3",
    })
  end)

  after_each(function()
    mock_hs._resetAll()
    _G.hs = nil
  end)

  describe("invalid JSON handling", function()
    it("should show alert for invalid JSON", function()
      -- Simulate receiving invalid JSON
      backend:_handleSocketData("{not valid json", 1)

      -- Check alert was shown
      local alerts = _G.hs.alert._getAlerts()
      assert.equals(1, #alerts)
      assert.is_true(alerts[1].message:match("Invalid server message") ~= nil)
    end)

    it("should emit recording:error for invalid JSON", function()
      local errorEmitted = false
      eventBus:on("recording:error", function(data)
        errorEmitted = true
        assert.is_not_nil(data.error)
      end)

      backend:_handleSocketData("invalid", 1)

      assert.is_true(errorEmitted)
    end)

    it("should show alert for missing event type", function()
      -- JSON is valid but missing type field
      backend:_handleSocketData('{"foo":"bar"}', 1)

      local alerts = _G.hs.alert._getAlerts()
      assert.equals(1, #alerts)
      assert.is_true(alerts[1].message:match("Invalid server message") ~= nil)
    end)
  end)

  describe("unknown event type handling", function()
    it("should show alert for unknown event type", function()
      -- Valid JSON but unknown event type
      backend:_handleServerEvent({type = "unknown_event_xyz"}, "en")

      local alerts = _G.hs.alert._getAlerts()
      assert.equals(1, #alerts)
      assert.is_true(alerts[1].message:match("Unknown server event type") ~= nil)
      assert.is_true(alerts[1].message:match("unknown_event_xyz") ~= nil)
    end)

    it("should emit recording:error for unknown event type", function()
      local errorData = nil
      eventBus:on("recording:error", function(data)
        errorData = data
      end)

      backend:_handleServerEvent({type = "weird_event"}, "en")

      assert.is_not_nil(errorData)
      assert.is_not_nil(errorData.error)
      assert.is_true(errorData.error:match("weird_event") ~= nil)
    end)
  end)

  describe("silence warning handling", function()
    it("should show alert for silence_warning event", function()
      backend:_handleServerEvent({
        type = "silence_warning",
        message = "Microphone off - stopping recording"
      }, "en")

      local alerts = _G.hs.alert._getAlerts()
      assert.equals(1, #alerts)
      assert.is_true(alerts[1].message:match("Microphone off") ~= nil)
    end)

    it("should emit recording:error for silence_warning", function()
      local errorData = nil
      eventBus:on("recording:error", function(data)
        errorData = data
      end)

      backend:_handleServerEvent({
        type = "silence_warning",
        message = "Microphone appears to be off"
      }, "en")

      assert.is_not_nil(errorData)
      assert.is_not_nil(errorData.error)
      assert.is_true(errorData.error:match("Microphone") ~= nil)
    end)

    it("should reset state when recording_stopped follows silence_warning", function()
      -- Simulate recording in progress
      backend._isRecording = true

      -- First: silence_warning event (shows error)
      backend:_handleServerEvent({
        type = "silence_warning",
        message = "Microphone off"
      }, "en")

      -- State is still recording (waiting for recording_stopped)
      assert.is_true(backend._isRecording)

      -- Then: recording_stopped event (from Python's _finalize_recording)
      backend:_handleServerEvent({
        type = "recording_stopped"
      }, "en")

      -- NOW state should be reset (single place for state management)
      assert.is_false(backend._isRecording)
    end)
  end)

  describe("known event types", function()
    it("should NOT show alert for valid events", function()
      backend:_handleServerEvent({type = "server_ready"}, "en")
      backend:_handleServerEvent({type = "recording_started"}, "en")
      backend:_handleServerEvent({type = "recording_stopped"}, "en")

      -- Should not show any alerts for valid events
      local alerts = _G.hs.alert._getAlerts()
      assert.equals(0, #alerts)
    end)
  end)
end)
