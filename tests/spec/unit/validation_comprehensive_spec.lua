--- Comprehensive Validation Tests - Catch Silent Failures

describe("Comprehensive Validation Tests", function()
  local Promise
  local EventBus
  local RecordingManager
  local TranscriptionManager

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon
    _G.hs = require("tests.helpers.mock_hs")

    Promise = require("lib.promise")
    EventBus = require("lib.event_bus")
    RecordingManager = require("core.recording_manager")
    TranscriptionManager = require("core.transcription_manager")
  end)

  describe("Promise return values", function()
    it("RecordingManager.startRecording ALWAYS returns a promise", function()
      local eventBus = EventBus.new()
      local mockBackend = {
        startRecording = function() return Promise.reject("test error") end,
        stopRecording = function() return Promise.resolve() end,
        isRecording = function() return false end,
        getName = function() return "mock" end,
      }

      local mgr = RecordingManager.new(mockBackend, eventBus, {})
      local result = mgr:startRecording("en")

      assert.is_not_nil(result, "Should return a value")
      assert.is_table(result, "Should return a table (promise)")
      assert.is_function(result.next, "Should have .next() method")
      assert.is_function(result.catch, "Should have .catch() method")
    end)

    it("RecordingManager.stopRecording ALWAYS returns a promise", function()
      local eventBus = EventBus.new()
      local mockBackend = {
        startRecording = function() return Promise.resolve() end,
        stopRecording = function() return Promise.resolve() end,
        isRecording = function() return true end,
        getName = function() return "mock" end,
      }

      local mgr = RecordingManager.new(mockBackend, eventBus, {})
      mgr:startRecording("en")

      local result = mgr:stopRecording()

      assert.is_not_nil(result, "Should return a value")
      assert.is_table(result, "Should return a table (promise)")
    end)

    it("TranscriptionManager.transcribe ALWAYS returns a promise", function()
      local eventBus = EventBus.new()
      local mockMethod = {
        transcribe = function() return Promise.resolve("test") end,
        getName = function() return "mock" end,
      }

      local mgr = TranscriptionManager.new(mockMethod, eventBus, {})
      local result = mgr:transcribe("/tmp/test.wav", "en")

      assert.is_not_nil(result, "Should return a value")
      assert.is_table(result, "Should return a table (promise)")
    end)
  end)

  describe("Nil parameter handling", function()
    it("RecordingManager.startRecording rejects on nil language", function()
      local eventBus = EventBus.new()
      local mockBackend = {
        startRecording = function() return Promise.resolve() end,
        stopRecording = function() return Promise.resolve() end,
        isRecording = function() return false end,
        getName = function() return "mock" end,
      }

      local mgr = RecordingManager.new(mockBackend, eventBus, {})
      local rejected = false

      mgr:startRecording(nil):catch(function()
        rejected = true
      end)

      assert.is_true(rejected, "Should reject on nil language")
    end)

    it("TranscriptionManager.transcribe rejects on nil audioFile", function()
      local eventBus = EventBus.new()
      local mockMethod = {
        transcribe = function() return Promise.resolve("test") end,
        getName = function() return "mock" end,
      }

      local mgr = TranscriptionManager.new(mockMethod, eventBus, {})
      local rejected = false

      mgr:transcribe(nil, "en"):catch(function()
        rejected = true
      end)

      assert.is_true(rejected, "Should reject on nil audioFile")
    end)
  end)

  describe("Event emission validation", function()
    it("RecordingManager emits valid event names only", function()
      local eventBus = EventBus.new(true)  -- strict mode
      local warnings = {}
      local old_print = _G.print
      _G.print = function(msg)
        if msg:match("INVALID EVENT") then
          table.insert(warnings, msg)
        end
      end

      local mockBackend = {
        startRecording = function() return Promise.resolve() end,
        stopRecording = function() return Promise.resolve() end,
        isRecording = function() return false end,
        getName = function() return "mock" end,
      }

      local mgr = RecordingManager.new(mockBackend, eventBus, {})
      mgr:startRecording("en")

      _G.print = old_print

      assert.equals(0, #warnings, "Should not emit any invalid events")
    end)

    it("TranscriptionManager emits valid event names only", function()
      local eventBus = EventBus.new(true)  -- strict mode
      local warnings = {}
      local old_print = _G.print
      _G.print = function(msg)
        if msg:match("INVALID EVENT") then
          table.insert(warnings, msg)
        end
      end

      local mockMethod = {
        transcribe = function() return Promise.resolve("test") end,
        getName = function() return "mock" end,
      }

      local mgr = TranscriptionManager.new(mockMethod, eventBus, {})
      mgr:transcribe("/tmp/test.wav", "en")

      _G.print = old_print

      assert.equals(0, #warnings, "Should not emit any invalid events")
    end)
  end)

  describe("Error message quality", function()
    it("RecordingManager errors include context", function()
      local eventBus = EventBus.new()
      local mockBackend = {
        startRecording = function() return Promise.reject("backend failed") end,
        stopRecording = function() return Promise.resolve() end,
        isRecording = function() return false end,
        getName = function() return "mock" end,
      }

      local mgr = RecordingManager.new(mockBackend, eventBus, {})
      local errorMsg = nil

      mgr:startRecording("en"):catch(function(err)
        errorMsg = err
      end)

      assert.is_not_nil(errorMsg, "Should have error message")
      assert.is_string(errorMsg, "Error should be a string")
      -- Should include context about what failed
    end)

    it("TranscriptionManager errors include file path", function()
      local eventBus = EventBus.new()
      local errorEmitted = nil

      eventBus:on("transcription:error", function(data)
        errorEmitted = data
      end)

      local mockMethod = {
        transcribe = function() return Promise.reject("transcription failed") end,
        getName = function() return "mock" end,
      }

      local mgr = TranscriptionManager.new(mockMethod, eventBus, {})
      mgr:transcribe("/tmp/important.wav", "en"):catch(function() end)

      assert.is_not_nil(errorEmitted, "Should emit error event")
      assert.is_not_nil(errorEmitted.audioFile, "Error should include audioFile path")
      assert.equals("/tmp/important.wav", errorEmitted.audioFile)
    end)
  end)

  describe("State consistency", function()
    it("RecordingManager state is consistent after error", function()
      local eventBus = EventBus.new()
      local mockBackend = {
        startRecording = function() return Promise.reject("fail") end,
        stopRecording = function() return Promise.resolve() end,
        isRecording = function() return false end,
        getName = function() return "mock" end,
      }

      local mgr = RecordingManager.new(mockBackend, eventBus, {})

      mgr:startRecording("en"):catch(function() end)

      -- State should be idle, not stuck in recording
      assert.equals("idle", mgr.state)
      assert.is_false(mgr:isRecording())
    end)

    it("TranscriptionManager pending count is accurate", function()
      local eventBus = EventBus.new()
      local resolvers = {}
      local mockMethod = {
        transcribe = function()
          return Promise.new(function(resolve)
            table.insert(resolvers, resolve)
          end)
        end,
        getName = function() return "mock" end,
      }

      local mgr = TranscriptionManager.new(mockMethod, eventBus, {})

      mgr:transcribe("/tmp/test1.wav", "en")
      mgr:transcribe("/tmp/test2.wav", "en")

      assert.equals(2, mgr:getPendingCount(), "Should have 2 pending")

      -- Complete one
      resolvers[1]("done")

      assert.equals(1, mgr:getPendingCount(), "Should have 1 pending")
    end)
  end)
end)
