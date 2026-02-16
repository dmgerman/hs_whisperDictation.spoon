--- Tests for Manager - Core state machine
---
--- Covers state transitions, recording lifecycle, transcription orchestration,
--- error handling, and result assembly

-- Load test infrastructure
local mock_hs = require("tests.helpers.mock_hs")

-- Mock Hammerspoon before loading modules
_G.hs = mock_hs

local Manager = dofile("core/manager.lua")
local MockRecorder = dofile("tests/mocks/mock_recorder.lua")
local MockTranscriber = dofile("tests/mocks/mock_transcriber.lua")

describe("Manager", function()
  local manager, recorder, transcriber, config

  before_each(function()
    -- Reset mocks
    mock_hs._resetAll()

    config = {
      language = "en",
      tempDir = "/tmp/whisper_test",
    }
    recorder = MockRecorder.new({chunkCount = 1})
    transcriber = MockTranscriber.new()
    manager = Manager.new(recorder, transcriber, config)
  end)

  after_each(function()
    if recorder then recorder:cleanup() end
    if transcriber then transcriber:cleanup() end
  end)

  describe("Initialization", function()
    it("should start in IDLE state", function()
      assert.equals(Manager.STATES.IDLE, manager.state)
    end)

    it("should have zero pending transcriptions", function()
      assert.equals(0, manager.pendingTranscriptions)
    end)

    it("should have empty results array", function()
      assert.is_table(manager.results)
      assert.equals(0, #manager.results)
    end)

    it("should have recordingComplete set to false", function()
      assert.is_false(manager.recordingComplete)
    end)

    it("should have no current language", function()
      assert.is_nil(manager.currentLanguage)
    end)

    it("should store recorder reference", function()
      assert.equals(recorder, manager.recorder)
    end)

    it("should store transcriber reference", function()
      assert.equals(transcriber, manager.transcriber)
    end)

    it("should store config reference", function()
      assert.equals(config, manager.config)
    end)
  end)

  describe("State Transitions", function()
    describe("Valid transitions", function()
      it("should allow IDLE -> RECORDING", function()
        local ok, err = manager:transitionTo(Manager.STATES.RECORDING, "test")
        assert.is_true(ok)
        assert.is_nil(err)
        assert.equals(Manager.STATES.RECORDING, manager.state)
      end)

      it("should allow IDLE -> ERROR", function()
        local ok, err = manager:transitionTo(Manager.STATES.ERROR, "test")
        assert.is_true(ok)
        assert.is_nil(err)
        assert.equals(Manager.STATES.ERROR, manager.state)
      end)

      it("should allow RECORDING -> TRANSCRIBING", function()
        manager.state = Manager.STATES.RECORDING
        local ok, err = manager:transitionTo(Manager.STATES.TRANSCRIBING, "test")
        assert.is_true(ok)
        assert.is_nil(err)
        assert.equals(Manager.STATES.TRANSCRIBING, manager.state)
      end)

      it("should allow RECORDING -> ERROR", function()
        manager.state = Manager.STATES.RECORDING
        local ok, err = manager:transitionTo(Manager.STATES.ERROR, "test")
        assert.is_true(ok)
        assert.is_nil(err)
        assert.equals(Manager.STATES.ERROR, manager.state)
      end)

      it("should allow TRANSCRIBING -> IDLE", function()
        manager.state = Manager.STATES.TRANSCRIBING
        local ok, err = manager:transitionTo(Manager.STATES.IDLE, "test")
        assert.is_true(ok)
        assert.is_nil(err)
        assert.equals(Manager.STATES.IDLE, manager.state)
      end)

      it("should allow TRANSCRIBING -> ERROR", function()
        manager.state = Manager.STATES.TRANSCRIBING
        local ok, err = manager:transitionTo(Manager.STATES.ERROR, "test")
        assert.is_true(ok)
        assert.is_nil(err)
        assert.equals(Manager.STATES.ERROR, manager.state)
      end)

      it("should allow ERROR -> IDLE", function()
        manager.state = Manager.STATES.ERROR
        local ok, err = manager:transitionTo(Manager.STATES.IDLE, "test")
        assert.is_true(ok)
        assert.is_nil(err)
        assert.equals(Manager.STATES.IDLE, manager.state)
      end)
    end)

    describe("Invalid transitions", function()
      it("should reject IDLE -> TRANSCRIBING", function()
        local ok, err = manager:transitionTo(Manager.STATES.TRANSCRIBING, "test")
        assert.is_false(ok)
        assert.is_string(err)
        assert.equals(Manager.STATES.IDLE, manager.state)
      end)

      it("should reject RECORDING -> IDLE", function()
        manager.state = Manager.STATES.RECORDING
        local ok, err = manager:transitionTo(Manager.STATES.IDLE, "test")
        assert.is_false(ok)
        assert.is_string(err)
        assert.equals(Manager.STATES.RECORDING, manager.state)
      end)

      it("should reject RECORDING -> RECORDING", function()
        manager.state = Manager.STATES.RECORDING
        local ok, err = manager:transitionTo(Manager.STATES.RECORDING, "test")
        assert.is_false(ok)
        assert.is_string(err)
        assert.equals(Manager.STATES.RECORDING, manager.state)
      end)

      it("should reject TRANSCRIBING -> RECORDING", function()
        manager.state = Manager.STATES.TRANSCRIBING
        local ok, err = manager:transitionTo(Manager.STATES.RECORDING, "test")
        assert.is_false(ok)
        assert.is_string(err)
        assert.equals(Manager.STATES.TRANSCRIBING, manager.state)
      end)

      it("should reject ERROR -> RECORDING", function()
        manager.state = Manager.STATES.ERROR
        local ok, err = manager:transitionTo(Manager.STATES.RECORDING, "test")
        assert.is_false(ok)
        assert.is_string(err)
        assert.equals(Manager.STATES.ERROR, manager.state)
      end)

      it("should reject ERROR -> TRANSCRIBING", function()
        manager.state = Manager.STATES.ERROR
        local ok, err = manager:transitionTo(Manager.STATES.TRANSCRIBING, "test")
        assert.is_false(ok)
        assert.is_string(err)
        assert.equals(Manager.STATES.ERROR, manager.state)
      end)
    end)

    describe("State entry handlers", function()
      it("should reset tracking when entering IDLE", function()
        manager.pendingTranscriptions = 5
        manager.results = {[1] = "test"}
        manager.recordingComplete = true
        manager.currentLanguage = "es"

        manager.state = Manager.STATES.ERROR
        manager:transitionTo(Manager.STATES.IDLE, "test")

        assert.equals(0, manager.pendingTranscriptions)
        assert.equals(0, #manager.results)
        assert.is_false(manager.recordingComplete)
        assert.is_nil(manager.currentLanguage)
      end)
    end)
  end)

  describe("startRecording", function()
    it("should transition from IDLE to RECORDING", function()
      manager:startRecording("en")
      assert.equals(Manager.STATES.RECORDING, manager.state)
    end)

    it("should store the language", function()
      manager:startRecording("es")
      assert.equals("es", manager.currentLanguage)
    end)

    it("should call recorder:startRecording", function()
      local called = false
      local originalStart = recorder.startRecording
      recorder.startRecording = function(self, config, onChunk, onError)
        called = true
        return true, nil
      end

      manager:startRecording("en")
      assert.is_true(called)

      recorder.startRecording = originalStart
    end)

    it("should pass config to recorder", function()
      local passedConfig = nil
      local originalStart = recorder.startRecording
      recorder.startRecording = function(self, config, onChunk, onError)
        passedConfig = config
        return true, nil
      end

      manager:startRecording("fr")
      assert.is_table(passedConfig)
      assert.equals("/tmp/whisper_test", passedConfig.outputDir)
      assert.equals("fr", passedConfig.lang)

      recorder.startRecording = originalStart
    end)

    it("should return success when recorder starts", function()
      local ok, err = manager:startRecording("en")
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("should reject if not in IDLE state", function()
      manager.state = Manager.STATES.RECORDING
      local ok, err = manager:startRecording("en")
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("should auto-reset from ERROR state", function()
      manager.state = Manager.STATES.ERROR
      local ok, err = manager:startRecording("en")
      assert.is_true(ok)
      assert.equals(Manager.STATES.RECORDING, manager.state)
    end)

    it("should reject invalid language (nil)", function()
      local ok, err = manager:startRecording(nil)
      assert.is_false(ok)
      assert.is_string(err)
      assert.equals(Manager.STATES.ERROR, manager.state)
    end)

    it("should reject invalid language (non-string)", function()
      local ok, err = manager:startRecording(123)
      assert.is_false(ok)
      assert.is_string(err)
      assert.equals(Manager.STATES.ERROR, manager.state)
    end)

    it("should transition to ERROR if recorder fails", function()
      recorder = MockRecorder.new({shouldFail = true, failureMode = "sync"})
      manager = Manager.new(recorder, transcriber, config)

      local ok, err = manager:startRecording("en")
      assert.is_false(ok)
      assert.is_string(err)
      assert.equals(Manager.STATES.ERROR, manager.state)
    end)
  end)

  describe("stopRecording", function()
    before_each(function()
      manager:startRecording("en")
    end)

    it("should transition from RECORDING to TRANSCRIBING or IDLE", function()
      manager:stopRecording()

      -- With MockRecorder/MockTranscriber, chunks emit and transcribe synchronously
      -- during startRecording(), so by the time stopRecording() is called,
      -- all transcriptions are already complete. The _checkIfComplete() call
      -- immediately transitions to IDLE.
      -- This is correct behavior for StreamingRecorder pattern.
      assert.equals(Manager.STATES.IDLE, manager.state)

      -- recordingComplete is reset to false when entering IDLE state
      assert.is_false(manager.recordingComplete)
    end)

    it("should set recordingComplete to true", function()
      -- Capture recordingComplete during the workflow
      local wasSetToTrue = false
      local originalStop = recorder.stopRecording
      recorder.stopRecording = function(self, onComplete, onError)
        wasSetToTrue = manager.recordingComplete
        return originalStop(self, onComplete, onError)
      end

      manager:stopRecording()
      assert.is_true(wasSetToTrue)

      recorder.stopRecording = originalStop
    end)

    it("should call recorder:stopRecording", function()
      local called = false
      local originalStop = recorder.stopRecording
      recorder.stopRecording = function(self, onComplete, onError)
        called = true
        return true, nil
      end

      manager:stopRecording()
      assert.is_true(called)

      recorder.stopRecording = originalStop
    end)

    it("should return success when recorder stops", function()
      local ok, err = manager:stopRecording()
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("should reject if not in RECORDING state", function()
      manager.state = Manager.STATES.IDLE
      local ok, err = manager:stopRecording()
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("should transition to ERROR if recorder stop fails", function()
      local originalStop = recorder.stopRecording
      recorder.stopRecording = function(self, onComplete, onError)
        return false, "Stop failed"
      end

      local ok, err = manager:stopRecording()
      assert.is_false(ok)
      assert.is_string(err)
      assert.equals(Manager.STATES.ERROR, manager.state)

      recorder.stopRecording = originalStop
    end)
  end)

  describe("reset", function()
    it("should transition from ERROR to IDLE", function()
      manager.state = Manager.STATES.ERROR
      local ok, err = manager:reset()
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(Manager.STATES.IDLE, manager.state)
    end)

    it("should reject if not in ERROR state", function()
      manager.state = Manager.STATES.IDLE
      local ok, err = manager:reset()
      assert.is_false(ok)
      assert.is_string(err)
    end)
  end)

  describe("getState", function()
    it("should return current state", function()
      assert.equals(Manager.STATES.IDLE, manager:getState())
      manager.state = Manager.STATES.RECORDING
      assert.equals(Manager.STATES.RECORDING, manager:getState())
    end)
  end)

  describe("Single chunk transcription (SoxRecorder pattern)", function()
    it("should handle complete workflow", function()
      -- Start recording
      manager:startRecording("en")
      assert.equals(Manager.STATES.RECORDING, manager.state)

      -- Stop recording (triggers chunk emission)
      manager:stopRecording()

      -- With MockRecorder/MockTranscriber, chunks emit and transcribe synchronously
      -- so completion happens immediately, transitioning to IDLE
      assert.equals(Manager.STATES.IDLE, manager.state)
      -- recordingComplete is reset to false when entering IDLE
      assert.is_false(manager.recordingComplete)
    end)

    it("should store transcription result", function()
      manager:startRecording("en")
      manager:stopRecording()

      -- Results are copied to clipboard then cleared when transitioning to IDLE
      local clipboardContent = hs.pasteboard.getContents()
      assert.is_string(clipboardContent)
      assert.is_not_nil(clipboardContent:match("Transcribed:"))
    end)

    it("should copy result to clipboard", function()
      manager:startRecording("en")
      manager:stopRecording()

      local clipboardContent = hs.pasteboard.getContents()
      assert.is_string(clipboardContent)
      assert.is_not_nil(clipboardContent:match("Transcribed:"))
    end)
  end)

  describe("Multiple chunk transcription (StreamingRecorder pattern)", function()
    before_each(function()
      recorder = MockRecorder.new({chunkCount = 3})
      manager = Manager.new(recorder, transcriber, config)
    end)

    it("should handle all chunks", function()
      manager:startRecording("en")
      manager:stopRecording()

      -- State should be TRANSCRIBING (completion via callbacks)
      -- Don't check state - verify clipboard instead
      local clipboardContent = hs.pasteboard.getContents()
      assert.is_string(clipboardContent)

      -- Should have multiple chunks (separated by \n\n)
      local chunks = {}
      for chunk in clipboardContent:gmatch("[^\n]+") do
        if chunk ~= "" then
          table.insert(chunks, chunk)
        end
      end
      assert.is_true(#chunks >= 3)
    end)

    it("should store chunks in correct order", function()
      manager:startRecording("en")
      manager:stopRecording()

      local clipboardContent = hs.pasteboard.getContents()
      assert.is_string(clipboardContent)

      -- Verify chunks appear in order (chunk-1, chunk-2, chunk-3)
      local pos1 = clipboardContent:find("chunk%-1")
      local pos2 = clipboardContent:find("chunk%-2")
      local pos3 = clipboardContent:find("chunk%-3")

      assert.is_not_nil(pos1)
      assert.is_not_nil(pos2)
      assert.is_not_nil(pos3)
      assert.is_true(pos1 < pos2)
      assert.is_true(pos2 < pos3)
    end)

    it("should assemble chunks with double newline separator", function()
      manager:startRecording("en")
      manager:stopRecording()

      local clipboardContent = hs.pasteboard.getContents()
      assert.is_not_nil(clipboardContent:match("\n\n"))
    end)

    it("should track pending transcriptions", function()
      manager:startRecording("en")

      -- In mock environment, timers execute immediately, so we need to check during callback
      local pendingDuringTranscription = nil
      local originalTranscribe = transcriber.transcribe
      transcriber.transcribe = function(self, audioFile, lang, onSuccess, onError)
        -- Capture pending count before transcription completes
        pendingDuringTranscription = manager.pendingTranscriptions
        return originalTranscribe(self, audioFile, lang, onSuccess, onError)
      end

      -- Inject chunk manually to test tracking
      manager:_onChunkReceived("/tmp/test.wav", 1, false)

      -- Should have been 1 during transcription start
      assert.equals(1, pendingDuringTranscription)

      -- Should be 0 after transcription completes (mock timer executes immediately)
      assert.equals(0, manager.pendingTranscriptions)

      transcriber.transcribe = originalTranscribe
    end)
  end)

  describe("Out-of-order completion", function()
    it("should handle chunk 2 completing before chunk 1", function()
      -- Manually orchestrate out-of-order completion
      manager.state = Manager.STATES.TRANSCRIBING
      manager.recordingComplete = true
      manager.currentLanguage = "en"

      -- Receive both chunks
      manager.pendingTranscriptions = 2
      manager.results = {}

      -- Chunk 2 completes first
      manager:_onTranscriptionSuccess(2, "second chunk")
      assert.equals(1, manager.pendingTranscriptions)
      assert.equals(Manager.STATES.TRANSCRIBING, manager.state)

      -- Chunk 1 completes second
      manager:_onTranscriptionSuccess(1, "first chunk")
      assert.equals(0, manager.pendingTranscriptions)
      assert.equals(Manager.STATES.IDLE, manager.state)

      -- Should assemble in correct order
      local clipboardContent = hs.pasteboard.getContents()
      assert.is_true(clipboardContent:match("first chunk") < clipboardContent:match("second chunk"))
    end)
  end)

  describe("Error handling", function()
    describe("Recorder errors", function()
      it("should handle recorder start failure", function()
        recorder = MockRecorder.new({shouldFail = true, failureMode = "sync"})
        manager = Manager.new(recorder, transcriber, config)

        local ok, err = manager:startRecording("en")
        assert.is_false(ok)
        assert.equals(Manager.STATES.ERROR, manager.state)
      end)

      it("should handle recorder async failure", function()
        recorder = MockRecorder.new({shouldFail = true, failureMode = "async"})
        manager = Manager.new(recorder, transcriber, config)

        manager:startRecording("en")
        -- Async failure triggers error callback
        assert.equals(Manager.STATES.ERROR, manager.state)
      end)
    end)

    describe("Transcription errors", function()
      before_each(function()
        transcriber = MockTranscriber.new({shouldFail = true, failureMode = "async"})
        manager = Manager.new(recorder, transcriber, config)
      end)

      it("should store error placeholder for failed chunk", function()
        manager:startRecording("en")
        manager:stopRecording()

        -- Results are copied to clipboard before being cleared
        local clipboardContent = hs.pasteboard.getContents()
        assert.is_string(clipboardContent)
        assert.is_not_nil(clipboardContent:match("%[chunk 1: error"))
      end)

      it("should still complete workflow despite transcription failure", function()
        manager:startRecording("en")
        manager:stopRecording()

        assert.equals(Manager.STATES.IDLE, manager.state)
      end)

      it("should include error placeholder in final result", function()
        manager:startRecording("en")
        manager:stopRecording()

        local clipboardContent = hs.pasteboard.getContents()
        assert.is_not_nil(clipboardContent:match("%[chunk 1: error"))
      end)
    end)
  end)

  describe("Graceful degradation", function()
    it("should handle partial transcription failures", function()
      recorder = MockRecorder.new({chunkCount = 3})
      transcriber = MockTranscriber.new()
      manager = Manager.new(recorder, transcriber, config)

      manager:startRecording("en")

      -- Manually fail chunk 2
      manager.state = Manager.STATES.TRANSCRIBING
      manager.recordingComplete = true
      manager.pendingTranscriptions = 3

      manager:_onTranscriptionSuccess(1, "chunk one")
      manager:_onTranscriptionError(2, "transcription failed")
      manager:_onTranscriptionSuccess(3, "chunk three")

      assert.equals(Manager.STATES.IDLE, manager.state)

      local clipboardContent = hs.pasteboard.getContents()
      assert.is_not_nil(clipboardContent:match("chunk one"))
      assert.is_not_nil(clipboardContent:match("%[chunk 2: error"))
      assert.is_not_nil(clipboardContent:match("chunk three"))
    end)
  end)

  describe("Result assembly", function()
    it("should concatenate results in order", function()
      manager.results = {
        [1] = "first",
        [2] = "second",
        [3] = "third",
      }

      local result = manager:_assembleResults()
      assert.equals("first\n\nsecond\n\nthird", result)
    end)

    it("should handle gaps with missing placeholder", function()
      manager.results = {
        [1] = "first",
        [3] = "third",
      }

      local result = manager:_assembleResults()
      assert.is_not_nil(result:match("%[chunk 2: missing%]"))
    end)

    it("should handle empty results", function()
      manager.results = {}
      local result = manager:_assembleResults()
      assert.equals("", result)
    end)

    it("should handle single result", function()
      manager.results = {[1] = "only"}
      local result = manager:_assembleResults()
      assert.equals("only", result)
    end)

    it("should handle non-sequential chunk numbers", function()
      manager.results = {
        [1] = "first",
        [5] = "fifth",
      }

      local result = manager:_assembleResults()
      assert.is_not_nil(result:match("first"))
      assert.is_not_nil(result:match("fifth"))
      assert.is_not_nil(result:match("%[chunk 2: missing%]"))
    end)
  end)
end)
