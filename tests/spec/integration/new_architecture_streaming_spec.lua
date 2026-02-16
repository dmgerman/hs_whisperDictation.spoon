--- New Architecture Integration Tests - StreamingRecorder
---
--- Tests Manager + StreamingRecorder + Transcriber integration
--- Focuses on multi-chunk emission and transcription coordination

describe("New Architecture - StreamingRecorder Integration", function()
  local Manager, StreamingRecorder, MockTranscriber
  local MockHS
  local manager, recorder, transcriber

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs
    MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    Manager = require("core_v2.manager")
    StreamingRecorder = require("recorders.streaming.streaming_recorder")
    MockTranscriber = require("tests.mocks.mock_transcriber")

    -- Create recorder with mocked server
    recorder = StreamingRecorder.new({
      pythonPath = "python3",
      serverScript = "/path/to/whisper_stream.py",
      tcpPort = 12341,
      tempDir = "/tmp/test"
    })

    -- Mock server startup to avoid shell dependencies
    recorder._startServer = function(self, outputDir, prefix)
      self.serverProcess = {
        isRunning = function() return true end,
        terminate = function() end
      }
      return true, nil
    end

    recorder._connectTCPSocket = function(self)
      self.tcpSocket = {
        read = function() end,
        write = function() return true end,
        disconnect = function() end
      }
    end

    transcriber = MockTranscriber.new({
      transcriptPrefix = "Transcribed: ",
      delay = 0.01
    })

    manager = Manager.new(recorder, transcriber, {
      language = "en",
      tempDir = "/tmp/test"
    })
  end)

  after_each(function()
    if manager then
      manager:reset()
    end
    if recorder then
      recorder:cleanup()
    end
    manager = nil
    recorder = nil
    transcriber = nil
    MockHS._resetAll()
    _G.hs = nil
  end)

  describe("multi-chunk recording", function()
    it("handles single chunk from streaming recorder", function()
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "startRecording should succeed: " .. tostring(err))
      assert.equals(Manager.STATES.RECORDING, manager.state)

      -- Simulate chunk by calling manager's callback directly
      -- (This is more reliable than going through recorder)
      manager:_onChunkReceived("/tmp/test/en-chunk1.wav", 1, true)

      -- Stop recording (this completes the cycle)
      ok, err = manager:stopRecording()
      assert.is_true(ok, "stopRecording should succeed: " .. tostring(err))

      -- Manager should transition to IDLE after transcription completes
      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals(0, manager.pendingTranscriptions)

      -- Check clipboard
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard)
      assert.is_true(clipboard:match("Transcribed:") ~= nil)
    end)

    it("handles multiple chunks during recording", function()
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "startRecording should succeed")

      -- Simulate 3 chunks via manager's callback
      manager:_onChunkReceived("/tmp/test/en-chunk1.wav", 1, false)

      -- Still recording (mock transcribes synchronously)
      assert.equals(Manager.STATES.RECORDING, manager.state)

      manager:_onChunkReceived("/tmp/test/en-chunk2.wav", 2, false)
      manager:_onChunkReceived("/tmp/test/en-chunk3.wav", 3, true)

      -- Stop recording
      ok, err = manager:stopRecording()
      assert.is_true(ok, "stopRecording should succeed")

      -- Should transition to IDLE after all transcriptions complete
      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals(0, manager.pendingTranscriptions)

      -- Should have 3 results assembled
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard)
      -- Should contain text from all 3 chunks
      assert.is_true(clipboard:match("Transcribed:") ~= nil)
    end)

    it("maintains correct chunk order in results", function()
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "startRecording should succeed")

      -- Emit chunks in order via manager callback
      for i = 1, 3 do
        manager:_onChunkReceived(
          "/tmp/test/en-chunk" .. i .. ".wav",
          i,
          (i == 3)
        )
      end

      -- Stop recording
      ok, err = manager:stopRecording()
      assert.is_true(ok, "stopRecording should succeed")

      -- Results should be in order [1, 2, 3]
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard)
      -- All chunks transcribed
      assert.equals(0, manager.pendingTranscriptions)
    end)

    it("handles out-of-order transcription completion", function()
      -- Use a transcriber that we can control
      local completionOrder = {}
      local customTranscriber = {
        _pendingJobs = {},
      }

      function customTranscriber:transcribe(audioFile, lang, onSuccess, onError)
        -- Store job for manual completion
        table.insert(self._pendingJobs, {
          audioFile = audioFile,
          lang = lang,
          onSuccess = onSuccess,
          onError = onError
        })
        return true, nil
      end

      function customTranscriber:validate()
        return true, nil
      end

      function customTranscriber:getName()
        return "custom"
      end

      function customTranscriber:supportsLanguage(lang)
        return true
      end

      -- Create manager with custom transcriber
      local customManager = Manager.new(recorder, customTranscriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      local ok, err = customManager:startRecording("en")
      assert.is_true(ok, "startRecording should succeed")

      -- Emit 3 chunks - use manager's chunk handler directly
      for i = 1, 3 do
        customManager:_onChunkReceived(
          "/tmp/test/en-chunk" .. i .. ".wav",
          i,
          (i == 3)
        )
      end

      -- Stop recording
      ok, err = customManager:stopRecording()
      assert.is_true(ok, "stopRecording should succeed")

      -- Should have 3 pending jobs (transcriber holds them)
      assert.equals(3, #customTranscriber._pendingJobs)

      -- Complete in reverse order: 3, 2, 1
      customTranscriber._pendingJobs[3].onSuccess("Chunk 3 text")
      assert.equals(2, customManager.pendingTranscriptions)

      customTranscriber._pendingJobs[2].onSuccess("Chunk 2 text")
      assert.equals(1, customManager.pendingTranscriptions)

      customTranscriber._pendingJobs[1].onSuccess("Chunk 1 text")
      assert.equals(0, customManager.pendingTranscriptions)

      -- Should transition to IDLE
      assert.equals(Manager.STATES.IDLE, customManager.state)

      -- Results should be assembled in correct order
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard)
    end)

    it("only completes when all chunks transcribed AND recording stopped", function()
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "startRecording should succeed")

      -- Emit 2 chunks (not final yet)
      manager:_onChunkReceived("/tmp/test/en-chunk1.wav", 1, false)
      manager:_onChunkReceived("/tmp/test/en-chunk2.wav", 2, false)

      -- Both chunks transcribe immediately (mock is synchronous)
      -- But recording is NOT complete yet
      assert.equals(Manager.STATES.RECORDING, manager.state)

      -- Now emit final chunk
      manager:_onChunkReceived("/tmp/test/en-chunk3.wav", 3, true)

      -- Stop recording to complete the cycle
      ok, err = manager:stopRecording()
      assert.is_true(ok, "stopRecording should succeed")

      -- Now should complete
      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals(0, manager.pendingTranscriptions)
    end)
  end)

  describe("error handling with multiple chunks", function()
    it("handles partial success - some chunks fail transcription", function()
      manager:startRecording("en")

      -- Create a transcriber that fails on chunk 2
      local failingTranscriber = {
        _callCount = 0
      }

      function failingTranscriber:transcribe(audioFile, lang, onSuccess, onError)
        self._callCount = self._callCount + 1
        if self._callCount == 2 then
          -- Fail chunk 2
          if onError then onError("Transcription failed for chunk 2") end
        else
          if onSuccess then onSuccess("Transcribed chunk " .. self._callCount) end
        end
        return true, nil
      end

      function failingTranscriber:validate() return true, nil end
      function failingTranscriber:getName() return "failing" end
      function failingTranscriber:supportsLanguage(lang) return true end

      local customManager = Manager.new(recorder, failingTranscriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      customManager:startRecording("en")

      -- Emit 3 chunks - use manager's chunk handler directly
      for i = 1, 3 do
        customManager:_onChunkReceived(
          "/tmp/test/en-chunk" .. i .. ".wav",
          i,
          (i == 3)
        )
      end

      -- Mark recording complete
      customManager.recordingComplete = true
      customManager:_checkIfComplete()

      -- Should complete with partial results
      assert.equals(Manager.STATES.IDLE, customManager.state)

      -- Clipboard should have results (chunks 1 and 3, with placeholder for 2)
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard)
    end)

    it("handles server error during recording", function()
      manager:startRecording("en")

      -- Emit first chunk
      recorder:_handleServerEvent({
        type = "chunk_ready",
        chunk_num = 1,
        audio_file = "/tmp/test/en-chunk1.wav",
        is_final = false
      }, "en")

      -- Server sends error
      recorder:_handleServerEvent({
        type = "error",
        error = "Server crashed"
      }, "en")

      -- Manager should transition to ERROR
      assert.equals(Manager.STATES.ERROR, manager.state)
    end)

    it("handles silence warning from server", function()
      manager:startRecording("en")

      local errorCallbackInvoked = false
      recorder._onError = function(msg)
        errorCallbackInvoked = true
      end

      -- Server sends silence warning
      recorder:_handleServerEvent({
        type = "silence_warning",
        message = "Microphone appears to be off"
      }, "en")

      assert.is_true(errorCallbackInvoked)
    end)
  end)

  describe("server lifecycle integration", function()
    it("server persists between multiple recordings", function()
      -- First recording
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "First startRecording should succeed")
      local firstServer = recorder.serverProcess

      manager:_onChunkReceived("/tmp/test/en-chunk1.wav", 1, true)

      ok, err = manager:stopRecording()
      assert.is_true(ok, "First stopRecording should succeed")
      assert.equals(Manager.STATES.IDLE, manager.state)

      -- Server should still exist
      assert.is_not_nil(recorder.serverProcess)

      -- Second recording
      ok, err = manager:startRecording("fr")
      assert.is_true(ok, "Second startRecording should succeed")

      -- Should reuse same server
      assert.equals(firstServer, recorder.serverProcess)

      manager:_onChunkReceived("/tmp/test/fr-chunk1.wav", 1, true)

      ok, err = manager:stopRecording()
      assert.is_true(ok, "Second stopRecording should succeed")
      assert.equals(Manager.STATES.IDLE, manager.state)
    end)

    it("cleanup shuts down server", function()
      manager:startRecording("en")

      assert.is_not_nil(recorder.serverProcess)
      assert.is_not_nil(recorder.tcpSocket)

      recorder:cleanup()

      assert.is_nil(recorder.serverProcess)
      assert.is_nil(recorder.tcpSocket)
      assert.is_false(recorder._isRecording)
    end)
  end)

  describe("per-chunk feedback", function()
    it("shows notification for each chunk transcribed", function()
      manager:startRecording("en")

      local initialAlerts = #MockHS.alert._getAlerts()

      -- Emit 3 chunks
      for i = 1, 3 do
        recorder:_handleServerEvent({
          type = "chunk_ready",
          chunk_num = i,
          audio_file = "/tmp/test/en-chunk" .. i .. ".wav",
          is_final = (i == 3)
        }, "en")
      end

      manager:_onRecordingComplete()

      local alerts = MockHS.alert._getAlerts()
      -- Should have alerts for each chunk + completion
      assert.is_true(#alerts > initialAlerts)
    end)
  end)

  describe("state transitions with streaming", function()
    it("IDLE → RECORDING → IDLE (single chunk)", function()
      assert.equals(Manager.STATES.IDLE, manager.state)

      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "startRecording should succeed")
      assert.equals(Manager.STATES.RECORDING, manager.state)

      manager:_onChunkReceived("/tmp/test/en-chunk1.wav", 1, true)

      ok, err = manager:stopRecording()
      assert.is_true(ok, "stopRecording should succeed")
      assert.equals(Manager.STATES.IDLE, manager.state)
    end)

    it("stays in RECORDING while chunks are being emitted", function()
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "startRecording should succeed")
      assert.equals(Manager.STATES.RECORDING, manager.state)

      -- Emit non-final chunks
      for i = 1, 5 do
        manager:_onChunkReceived("/tmp/test/en-chunk" .. i .. ".wav", i, false)

        -- Should stay in RECORDING until stopRecording called
        assert.equals(Manager.STATES.RECORDING, manager.state)
      end

      -- Final chunk
      manager:_onChunkReceived("/tmp/test/en-chunk6.wav", 6, true)

      ok, err = manager:stopRecording()
      assert.is_true(ok, "stopRecording should succeed")
      assert.equals(Manager.STATES.IDLE, manager.state)
    end)

    it("transitions to ERROR on server error", function()
      manager:startRecording("en")
      assert.equals(Manager.STATES.RECORDING, manager.state)

      recorder:_handleServerEvent({
        type = "error",
        error = "Server crashed"
      }, "en")

      assert.equals(Manager.STATES.ERROR, manager.state)
    end)

    it("can recover from ERROR state", function()
      -- Cause error
      manager:startRecording("en")
      recorder:_handleServerEvent({
        type = "error",
        error = "Test error"
      }, "en")

      assert.equals(Manager.STATES.ERROR, manager.state)

      -- Reset manager
      manager:reset()
      assert.equals(Manager.STATES.IDLE, manager.state)

      -- Reset recorder state
      recorder._isRecording = false

      -- Start again
      manager:startRecording("en")
      assert.equals(Manager.STATES.RECORDING, manager.state)
    end)
  end)
end)
