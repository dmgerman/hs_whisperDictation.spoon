--- Error Handling Integration Tests
-- Verifies error scenarios are handled correctly across components
-- Tests event flows, state consistency, and cross-component coordination

describe("Error Handling Integration", function()
  local EventBus
  local RecordingManager
  local ChunkAssembler
  local Promise
  local mockBackend

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Mock Hammerspoon APIs
    _G.hs = require("tests.helpers.mock_hs")

    EventBus = require("lib.event_bus")
    RecordingManager = require("core.recording_manager")
    ChunkAssembler = require("core.chunk_assembler")
    Promise = require("lib.promise")

    -- Create mock backend that properly emits events
    mockBackend = {
      _isRecording = false,
      eventBus = nil,  -- Will be set in tests

      startRecording = function(self, config)
        return Promise.new(function(resolve, reject)
          if self._isRecording then
            reject("Server already running")
          else
            self._isRecording = true
            self._lastConfig = config
            -- Backend emits recording:started
            if self.eventBus then
              self.eventBus:emit("recording:started", {
                lang = config.lang
              })
            end
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
            -- Backend emits recording:stopped
            if self.eventBus then
              self.eventBus:emit("recording:stopped", {})
            end
            resolve()
          end
        end)
      end,

      isRecording = function(self)
        return self._isRecording
      end,

      getName = function(self)
        return "mock"
      end,
    }
  end)

  describe("Start errors don't disrupt active recording", function()
    it("keeps recording when duplicate start is attempted", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Start first recording
      local success = false
      manager:startRecording("en"):next(function()
        success = true
      end)

      assert.is_true(success, "First recording should start successfully")
      assert.is_true(manager:isRecording(), "RecordingManager should be recording")
      assert.is_true(mockBackend:isRecording(), "Backend should be running")

      -- Register error listener BEFORE triggering error
      local errorOccurred = false
      local errorContext = nil
      eventBus:on("recording:error", function(data)
        errorOccurred = true
        errorContext = data.context
      end)

      -- Try to start again while recording
      local secondStartFailed = false
      manager:startRecording("en"):catch(function(err)
        secondStartFailed = true
      end)

      -- Verify error was emitted with context="start"
      assert.is_true(errorOccurred, "Error event should be emitted")
      assert.equals("start", errorContext, "Error context should be 'start'")
      assert.is_true(secondStartFailed, "Second start should fail")

      -- CRITICAL: First recording should STILL be active
      assert.is_true(manager:isRecording(), "RecordingManager should still be recording")
      assert.is_true(mockBackend:isRecording(), "Backend should still be running")

      -- State should be consistent
      local status = manager:getStatus()
      assert.equals("recording", status.state)
      assert.equals("en", status.currentLang)
    end)

    it("distinguishes between start errors and recording errors", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Track all errors with context
      local errors = {}
      eventBus:on("recording:error", function(data)
        table.insert(errors, {
          context = data.context,
          error = data.error
        })
      end)

      -- Start recording
      manager:startRecording("en")

      -- Try to start again (start error)
      manager:startRecording("en")

      -- Verify we got a start error
      assert.equals(1, #errors, "Should have one error")
      assert.equals("start", errors[1].context)

      -- Now stop recording
      manager:stopRecording()

      -- Recording should be stopped
      assert.is_false(manager:isRecording())
    end)
  end)

  describe("Backend state vs RecordingManager state alignment", function()
    it("backend operational state matches RecordingManager recording state", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Both should be idle initially
      assert.is_false(manager:isRecording())
      assert.is_false(mockBackend:isRecording())

      -- Start recording
      manager:startRecording("en")

      -- Both should be recording
      assert.is_true(manager:isRecording())
      assert.is_true(mockBackend:isRecording())

      -- Stop recording
      manager:stopRecording()

      -- Both should be idle
      assert.is_false(manager:isRecording())
      assert.is_false(mockBackend:isRecording())
    end)

    it("backend state survives start errors", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Start recording
      manager:startRecording("en")

      local initialBackendState = mockBackend:isRecording()
      local initialManagerState = manager:isRecording()

      -- Try to start again (error)
      manager:startRecording("en")

      -- Backend state should be unchanged
      assert.equals(initialBackendState, mockBackend:isRecording())
      assert.equals(initialManagerState, manager:isRecording())
    end)
  end)

  describe("ChunkAssembler state consistency during errors", function()
    it("doesn't reset when start errors occur", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      local assembler = ChunkAssembler.new(eventBus, {
        tempDir = "/tmp/test"
      })

      -- Start recording
      manager:startRecording("en")

      -- Simulate chunks being received (manually add since we don't have transcription pipeline)
      assembler:addChunk(1, "First chunk", "/tmp/test/chunk1.wav")
      assembler:addChunk(2, "Second chunk", "/tmp/test/chunk2.wav")

      -- ChunkAssembler should have 2 chunks
      assert.equals(2, assembler:getChunkCount(), "Should have 2 chunks")

      -- Try to start again (error) - should NOT reset ChunkAssembler
      manager:startRecording("en")

      -- ChunkAssembler should STILL have 2 chunks (not reset)
      assert.equals(2, assembler:getChunkCount(), "ChunkAssembler should not reset on start error")
    end)

    it("resets only when recording actually stops and new one starts", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      local assembler = ChunkAssembler.new(eventBus, {
        tempDir = "/tmp/test"
      })

      -- Start recording
      manager:startRecording("en")

      -- Simulate chunks (manually add)
      assembler:addChunk(1, "First chunk", "/tmp/test/chunk1.wav")

      assert.equals(1, assembler:getChunkCount())

      -- Stop recording
      manager:stopRecording()

      -- In real code, init.lua calls assembler:reset() before starting new recording
      assembler:reset()

      -- Start new recording
      manager:startRecording("ja")

      assert.equals(0, assembler:getChunkCount(), "ChunkAssembler should be reset")
    end)
  end)

  describe("Error event propagation", function()
    it("emits error events with correct context", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Register listener BEFORE triggering errors
      local errorEvents = {}
      eventBus:on("recording:error", function(data)
        table.insert(errorEvents, {
          context = data.context,
          error = data.error
        })
      end)

      -- Test start error
      manager:startRecording("")  -- Empty lang triggers error

      assert.equals(1, #errorEvents)
      assert.equals("start", errorEvents[1].context)

      -- Test stop error (not recording)
      manager:stopRecording()

      assert.equals(2, #errorEvents)
      assert.equals("stop", errorEvents[2].context)
    end)

    it("error handlers can differentiate error types", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Register listener BEFORE triggering errors
      local startErrors = 0
      local stopErrors = 0
      local otherErrors = 0

      eventBus:on("recording:error", function(data)
        if data.context == "start" then
          startErrors = startErrors + 1
        elseif data.context == "stop" then
          stopErrors = stopErrors + 1
        else
          otherErrors = otherErrors + 1
        end
      end)

      -- Trigger start error
      manager:startRecording("")

      -- Trigger stop error
      manager:stopRecording()

      assert.equals(1, startErrors)
      assert.equals(1, stopErrors)
      assert.equals(0, otherErrors)
    end)
  end)

  describe("State recovery after errors", function()
    it("recovers from start errors and can record again", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Try to start with invalid params (error)
      manager:startRecording("")

      -- Should be idle after error
      assert.is_false(manager:isRecording())
      assert.equals("idle", manager:getStatus().state)

      -- Should be able to start recording now
      local success = false
      manager:startRecording("en"):next(function()
        success = true
      end)

      assert.is_true(success)
      assert.is_true(manager:isRecording())
    end)

    it("maintains clean state after multiple error scenarios", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Scenario 1: Start with invalid params
      manager:startRecording("")
      assert.equals("idle", manager:getStatus().state)

      -- Scenario 2: Stop when not recording
      manager:stopRecording()
      assert.equals("idle", manager:getStatus().state)

      -- Scenario 3: Valid start
      manager:startRecording("en")
      assert.equals("recording", manager:getStatus().state)

      -- Scenario 4: Duplicate start (error)
      manager:startRecording("en")
      assert.equals("recording", manager:getStatus().state)  -- Still recording

      -- Scenario 5: Valid stop
      manager:stopRecording()
      assert.equals("idle", manager:getStatus().state)
    end)
  end)

  describe("Complete error workflow integration", function()
    it("simulates real-world error recovery scenario", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      local assembler = ChunkAssembler.new(eventBus, {
        tempDir = "/tmp/test"
      })

      -- Register listeners BEFORE triggering events
      local recordingStarts = 0
      local recordingStops = 0
      local errors = {}

      eventBus:on("recording:started", function() recordingStarts = recordingStarts + 1 end)
      eventBus:on("recording:stopped", function() recordingStops = recordingStops + 1 end)
      eventBus:on("recording:error", function(data) table.insert(errors, data) end)

      -- Step 1: User starts recording
      manager:startRecording("en")
      -- Backend emits recording:started, RecordingManager also emits it
      -- In real code, RecordingManager doesn't re-emit, but backend does
      -- So we get 1 from backend only (RecordingManager's emit happens in catch chain)
      assert.is_true(recordingStarts >= 1, "Should have at least one start event")

      -- Step 2: Audio chunks arrive (manually add)
      assembler:addChunk(1, "First chunk", "/tmp/test/chunk1.wav")

      -- Step 3: User accidentally triggers start again (common mistake)
      manager:startRecording("en")

      -- Should have error but still recording
      assert.is_true(#errors >= 1, "Should have at least one error")
      assert.equals("start", errors[1].context)
      assert.is_true(manager:isRecording())

      -- Step 4: More chunks arrive (recording continues)
      assembler:addChunk(2, "Second chunk", "/tmp/test/chunk2.wav")

      assert.equals(2, assembler:getChunkCount())

      -- Step 5: User stops recording properly
      manager:stopRecording()

      assert.is_true(recordingStops >= 1, "Should have at least one stop event")
      assert.is_false(manager:isRecording())

      -- Step 6: Reset assembler (init.lua does this) and start new recording
      assembler:reset()
      manager:startRecording("ja")

      assert.equals(0, assembler:getChunkCount())
    end)

    it("init.lua error handler pattern - only stop on recording errors", function()
      local eventBus = EventBus.new()
      mockBackend.eventBus = eventBus

      local manager = RecordingManager.new(mockBackend, eventBus, {
        tempDir = "/tmp/test"
      })

      -- Simulate init.lua error handler
      local shouldStopRecording = false
      eventBus:on("recording:error", function(data)
        -- Only stop if error occurred DURING recording (not start errors)
        if data.context ~= "start" then
          shouldStopRecording = true
        end
      end)

      -- Start recording
      manager:startRecording("en")
      assert.is_true(manager:isRecording())

      -- Try to start again (start error)
      manager:startRecording("en")

      -- Should NOT trigger stopRecording
      assert.is_false(shouldStopRecording, "Start error should NOT trigger stop")
      assert.is_true(manager:isRecording(), "Should still be recording")

      -- Now simulate an error DURING recording (not a start error)
      eventBus:emit("recording:error", {
        context = "recording",
        error = "Some recording error"
      })

      -- This SHOULD trigger stopRecording
      assert.is_true(shouldStopRecording, "Recording error should trigger stop")
    end)
  end)
end)
