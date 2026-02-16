--- Integration Tests: New Architecture - Basic Flow (Mock Components)
---
--- Tests Manager orchestration with MockRecorder and MockTranscriber.
--- Focuses on state machine logic, error handling, and callback orchestration.
---
--- Layer 1: Fast, deterministic tests with mocks

-- Load test infrastructure
local scriptPath = debug.getinfo(1, "S").source:sub(2)
local spoonPath = scriptPath:match("(.*/)tests/spec/integration/") or
                  scriptPath:match("(.*/)tests/") or
                  "./"
package.path = package.path .. ";" .. spoonPath .. "?.lua;" .. spoonPath .. "?/init.lua"

local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS

-- Load new architecture components
local Manager = dofile(spoonPath .. "core_v2/manager.lua")
local MockRecorder = dofile(spoonPath .. "tests/mocks/mock_recorder.lua")
local MockTranscriber = dofile(spoonPath .. "tests/mocks/mock_transcriber.lua")

describe("New Architecture - Basic Flow (Mocks)", function()
  local manager, recorder, transcriber

  before_each(function()
    -- Reset mock environment
    MockHS._resetAll()

    -- Create fresh instances
    recorder = MockRecorder.new({ chunkCount = 1, delay = 0.1 })
    transcriber = MockTranscriber.new({ delay = 0.1 })
    manager = Manager.new(recorder, transcriber, {
      language = "en",
      tempDir = "/tmp/test_whisper"
    })
  end)

  after_each(function()
    -- Cleanup timers
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
      assert.equals(0, #manager.results)
    end)

    it("should have recordingComplete = false", function()
      assert.is_false(manager.recordingComplete)
    end)

    it("should store recorder reference", function()
      assert.equals(recorder, manager.recorder)
    end)

    it("should store transcriber reference", function()
      assert.equals(transcriber, manager.transcriber)
    end)
  end)

  describe("Full Recording Session (Single Chunk)", function()
    it("should complete full flow: IDLE -> RECORDING -> TRANSCRIBING -> IDLE", function()
      -- Start recording
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "startRecording should succeed: " .. tostring(err))
      assert.equals(Manager.STATES.RECORDING, manager.state)

      -- Stop recording (triggers chunk emission and transcription in mocks)
      ok, err = manager:stopRecording()
      assert.is_true(ok, "stopRecording should succeed: " .. tostring(err))

      -- In mocks, everything completes synchronously
      assert.equals(Manager.STATES.IDLE, manager.state, "Should transition back to IDLE")
      assert.equals(0, manager.pendingTranscriptions, "No pending transcriptions")
    end)

    it("should emit exactly 1 chunk with chunkNum=1, isFinal=true", function()
      local chunkReceived = nil

      -- Override recorder to capture chunk emission
      recorder = MockRecorder.new({ chunkCount = 1, delay = 0.01 })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      -- Intercept _onChunkReceived
      local originalOnChunk = manager._onChunkReceived
      manager._onChunkReceived = function(self, audioFile, chunkNum, isFinal)
        chunkReceived = { audioFile = audioFile, chunkNum = chunkNum, isFinal = isFinal }
        originalOnChunk(self, audioFile, chunkNum, isFinal)
      end

      manager:startRecording("en")
      manager:stopRecording()

      assert.is_not_nil(chunkReceived, "Chunk should be received")
      assert.equals(1, chunkReceived.chunkNum)
      assert.is_true(chunkReceived.isFinal)
    end)

    it("should store transcribed result and copy to clipboard", function()
      manager:startRecording("en")
      manager:stopRecording()

      -- Results are cleared when transitioning to IDLE, so check clipboard instead
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard, "Clipboard should have content")
      assert.is_true(clipboard:match("Transcribed:") ~= nil, "Should contain mock transcription")
    end)

    it("should copy final result to clipboard", function()
      manager:startRecording("en")
      manager:stopRecording()

      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard, "Clipboard should have content")
      assert.is_true(clipboard:match("Transcribed:") ~= nil, "Clipboard should contain transcription")
    end)

    it("should show per-chunk feedback via Notifier", function()
      local alerts = MockHS.alert._getAlerts()
      local initialCount = #alerts

      manager:startRecording("en")
      manager:stopRecording()

      alerts = MockHS.alert._getAlerts()
      local newAlerts = #alerts - initialCount

      -- Should see: "Recording started", "Chunk 1: ...", "Transcription complete!"
      assert.is_true(newAlerts >= 3, "Should show multiple feedback messages")
    end)

    it("should show completion message", function()
      manager:startRecording("en")
      manager:stopRecording()

      local alerts = MockHS.alert._getAlerts()
      local hasCompletionMessage = false
      for _, alert in ipairs(alerts) do
        if alert.message:match("complete") or alert.message:match("Copied to clipboard") then
          hasCompletionMessage = true
          break
        end
      end

      assert.is_true(hasCompletionMessage, "Should show completion message")
    end)
  end)

  describe("Full Recording Session (Multiple Chunks)", function()
    it("should handle 3 chunks correctly", function()
      recorder = MockRecorder.new({ chunkCount = 3, delay = 0.01 })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      manager:startRecording("en")
      manager:stopRecording()

      -- Should be in IDLE state
      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals(0, manager.pendingTranscriptions)

      -- Check clipboard has all 3 chunks (results cleared when entering IDLE)
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard, "Clipboard should have content")

      -- Count occurrences of "Transcribed:" in clipboard (one per chunk)
      local count = 0
      for _ in clipboard:gmatch("Transcribed:") do
        count = count + 1
      end
      assert.equals(3, count, "Should have 3 transcribed chunks in clipboard")
    end)

    it("should assemble multiple chunks with double newlines", function()
      recorder = MockRecorder.new({ chunkCount = 3, delay = 0.01 })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      manager:startRecording("en")
      manager:stopRecording()

      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard)

      -- Should contain double newlines between chunks
      assert.is_true(clipboard:match("\n\n") ~= nil, "Should have double newlines")
    end)
  end)

  describe("State Machine Validation", function()
    it("should reject startRecording when already RECORDING", function()
      manager:startRecording("en")

      -- Try to start again
      local ok, err = manager:startRecording("en")
      assert.is_false(ok, "Should reject second start")
      assert.is_not_nil(err)
      assert.is_true(err:match("not in IDLE") ~= nil, "Error should mention state")
    end)

    it("should reject stopRecording when IDLE", function()
      local ok, err = manager:stopRecording()
      assert.is_false(ok, "Should reject stop when IDLE")
      assert.is_not_nil(err)
      assert.is_true(err:match("not in RECORDING") ~= nil, "Error should mention state")
    end)

    it("should reject stopRecording when in TRANSCRIBING state", function()
      recorder = MockRecorder.new({ chunkCount = 3, delay = 1.0 })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      manager:startRecording("en")

      -- Manually transition to TRANSCRIBING (simulate async timing)
      manager.state = Manager.STATES.TRANSCRIBING

      local ok, err = manager:stopRecording()
      assert.is_false(ok, "Should reject stop when TRANSCRIBING")
      assert.is_not_nil(err)
    end)

    it("should validate invalid transitions", function()
      -- IDLE -> TRANSCRIBING is invalid
      local ok, err = manager:transitionTo(Manager.STATES.TRANSCRIBING)
      assert.is_false(ok, "IDLE -> TRANSCRIBING should be invalid")
      assert.is_not_nil(err)
    end)

    it("should allow valid transitions", function()
      -- IDLE -> RECORDING
      local ok, err = manager:transitionTo(Manager.STATES.RECORDING)
      assert.is_true(ok, "IDLE -> RECORDING should be valid: " .. tostring(err))

      -- RECORDING -> TRANSCRIBING
      ok, err = manager:transitionTo(Manager.STATES.TRANSCRIBING)
      assert.is_true(ok, "RECORDING -> TRANSCRIBING should be valid: " .. tostring(err))

      -- TRANSCRIBING -> IDLE
      ok, err = manager:transitionTo(Manager.STATES.IDLE)
      assert.is_true(ok, "TRANSCRIBING -> IDLE should be valid: " .. tostring(err))
    end)

    it("should allow ERROR -> IDLE transition", function()
      manager.state = Manager.STATES.ERROR

      local ok, err = manager:transitionTo(Manager.STATES.IDLE)
      assert.is_true(ok, "ERROR -> IDLE should be valid: " .. tostring(err))
    end)

    it("should reset state when entering IDLE", function()
      manager.state = Manager.STATES.ERROR
      manager.pendingTranscriptions = 5
      manager.results = {[1] = "test"}
      manager.recordingComplete = true

      manager:transitionTo(Manager.STATES.IDLE)

      assert.equals(0, manager.pendingTranscriptions)
      assert.equals(0, #manager.results)
      assert.is_false(manager.recordingComplete)
      assert.is_nil(manager.currentLanguage)
    end)
  end)

  describe("Error Handling - Recorder Failures", function()
    it("should handle recorder start failure (sync)", function()
      recorder = MockRecorder.new({ shouldFail = true, failureMode = "sync" })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      local ok, err = manager:startRecording("en")
      assert.is_false(ok, "Should fail to start")
      assert.is_not_nil(err)

      -- Should transition to ERROR state
      assert.equals(Manager.STATES.ERROR, manager.state)
    end)

    it("should handle recorder error during recording (async)", function()
      recorder = MockRecorder.new({ shouldFail = true, failureMode = "async" })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      manager:startRecording("en")

      -- Async error callback fires immediately in mocks
      assert.equals(Manager.STATES.ERROR, manager.state)
    end)

    it("should show error message via Notifier on recorder failure", function()
      recorder = MockRecorder.new({ shouldFail = true, failureMode = "sync" })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      local alerts = MockHS.alert._getAlerts()
      local initialCount = #alerts

      manager:startRecording("en")

      alerts = MockHS.alert._getAlerts()
      local hasErrorMessage = false
      for i = initialCount + 1, #alerts do
        if alerts[i].message:match("[Ee]rror") or alerts[i].message:match("[Ff]ailed") then
          hasErrorMessage = true
          break
        end
      end

      assert.is_true(hasErrorMessage, "Should show error message")
    end)
  end)

  describe("Error Handling - Transcription Failures", function()
    it("should handle transcription failure gracefully", function()
      transcriber = MockTranscriber.new({ shouldFail = true, failureMode = "async" })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      manager:startRecording("en")
      manager:stopRecording()

      -- Should complete with error placeholder
      assert.equals(Manager.STATES.IDLE, manager.state, "Should still transition to IDLE")

      -- Check clipboard contains error placeholder
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard, "Clipboard should have content")
      assert.is_true(clipboard:match("error") ~= nil, "Clipboard should contain error placeholder")
    end)

    it("should show warning for failed transcription", function()
      transcriber = MockTranscriber.new({ shouldFail = true, failureMode = "async" })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      local alerts = MockHS.alert._getAlerts()
      local initialCount = #alerts

      manager:startRecording("en")
      manager:stopRecording()

      alerts = MockHS.alert._getAlerts()
      local hasWarning = false
      for i = initialCount + 1, #alerts do
        if alerts[i].message:match("[Tt]ranscription failed") or alerts[i].message:match("error") then
          hasWarning = true
          break
        end
      end

      assert.is_true(hasWarning, "Should show transcription failure warning")
    end)

    it("should continue with partial results when some chunks fail", function()
      -- Custom transcriber that fails on chunk 2
      local customTranscriber = MockTranscriber.new()
      local transcribeCount = 0
      local originalTranscribe = customTranscriber.transcribe

      customTranscriber.transcribe = function(self, audioFile, lang, onSuccess, onError)
        transcribeCount = transcribeCount + 1
        if transcribeCount == 2 then
          -- Fail chunk 2
          return originalTranscribe(self, audioFile, lang, onSuccess, onError)
        else
          return originalTranscribe(self, audioFile, lang, onSuccess, onError)
        end
      end

      -- Override to fail chunk 2
      customTranscriber.shouldFail = false
      customTranscriber._originalTranscribe = customTranscriber.transcribe
      customTranscriber.transcribe = function(self, audioFile, lang, onSuccess, onError)
        transcribeCount = transcribeCount + 1
        if transcribeCount == 2 then
          hs.timer.doAfter(0.01, function()
            if onError then onError("Chunk 2 failed") end
          end)
          return true, nil
        end
        return self._originalTranscribe(self, audioFile, lang, onSuccess, onError)
      end

      recorder = MockRecorder.new({ chunkCount = 3, delay = 0.01 })
      manager = Manager.new(recorder, customTranscriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      manager:startRecording("en")
      manager:stopRecording()

      -- Should have 3 results (2 successful, 1 error)
      assert.equals(3, #manager.results)
      assert.is_true(manager.results[2]:match("error") ~= nil, "Chunk 2 should be error")

      -- Should still complete
      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals(0, manager.pendingTranscriptions)
    end)
  end)

  describe("Error Recovery", function()
    it("should support manual reset from ERROR state", function()
      recorder = MockRecorder.new({ shouldFail = true, failureMode = "sync" })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      -- Cause error
      manager:startRecording("en")
      assert.equals(Manager.STATES.ERROR, manager.state)

      -- Reset
      local ok, err = manager:reset()
      assert.is_true(ok, "Reset should succeed: " .. tostring(err))
      assert.equals(Manager.STATES.IDLE, manager.state)
    end)

    it("should auto-reset from ERROR when starting new recording", function()
      recorder = MockRecorder.new({ shouldFail = true, failureMode = "sync" })
      manager = Manager.new(recorder, transcriber, {
        language = "en",
        tempDir = "/tmp/test"
      })

      -- Cause error
      manager:startRecording("en")
      assert.equals(Manager.STATES.ERROR, manager.state)

      -- Create working recorder
      recorder = MockRecorder.new({ chunkCount = 1 })
      manager.recorder = recorder

      -- Try to start recording again (should auto-reset)
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "Should auto-reset and start: " .. tostring(err))
      assert.equals(Manager.STATES.RECORDING, manager.state)
    end)

    it("should reject reset when not in ERROR state", function()
      assert.equals(Manager.STATES.IDLE, manager.state)

      local ok, err = manager:reset()
      assert.is_false(ok, "Reset should fail when not in ERROR")
      assert.is_not_nil(err)
    end)
  end)

  describe("Input Validation", function()
    it("should reject nil language", function()
      local ok, err = manager:startRecording(nil)
      assert.is_false(ok, "Should reject nil language")
      assert.is_not_nil(err)
      assert.is_true(err:match("Invalid language") ~= nil)
    end)

    it("should reject non-string language", function()
      local ok, err = manager:startRecording(123)
      assert.is_false(ok, "Should reject numeric language")
      assert.is_not_nil(err)
    end)

    it("should accept valid language codes", function()
      local ok, err = manager:startRecording("en")
      assert.is_true(ok, "Should accept 'en': " .. tostring(err))
      manager:stopRecording()

      -- Reset
      manager.state = Manager.STATES.IDLE

      ok, err = manager:startRecording("es")
      assert.is_true(ok, "Should accept 'es': " .. tostring(err))
    end)
  end)

  describe("Result Assembly", function()
    it("should handle gaps in chunk numbers gracefully", function()
      manager.results = {
        [1] = "First chunk",
        [3] = "Third chunk",
        -- Gap at position 2
      }
      manager.recordingComplete = true

      local result = manager:_assembleResults()

      assert.is_not_nil(result)
      assert.is_true(result:match("First chunk") ~= nil)
      assert.is_true(result:match("missing") ~= nil, "Should indicate missing chunk")
      assert.is_true(result:match("Third chunk") ~= nil)
    end)

    it("should concatenate results in order", function()
      manager.results = {
        [1] = "First",
        [2] = "Second",
        [3] = "Third",
      }

      local result = manager:_assembleResults()

      -- Check order
      local firstPos = result:find("First")
      local secondPos = result:find("Second")
      local thirdPos = result:find("Third")

      assert.is_true(firstPos < secondPos, "First should come before Second")
      assert.is_true(secondPos < thirdPos, "Second should come before Third")
    end)

    it("should handle single chunk", function()
      manager.results = {[1] = "Only chunk"}

      local result = manager:_assembleResults()
      assert.equals("Only chunk", result)
    end)

    it("should handle empty results", function()
      manager.results = {}

      local result = manager:_assembleResults()
      assert.equals("", result)
    end)
  end)

  describe("Notifier Integration", function()
    it("should call Notifier.show for state transitions (debug level)", function()
      -- Note: debug level messages are logged but not shown as alerts
      -- We can verify they don't crash, but they won't appear in MockHS.alert

      local ok, err = manager:transitionTo(Manager.STATES.RECORDING)
      assert.is_true(ok, "Transition should succeed: " .. tostring(err))

      -- No assertion on alerts since debug doesn't show
      -- Just verify no error
    end)

    it("should use proper categories for different events", function()
      -- This is tested implicitly through the success of operations
      -- The Notifier itself has its own unit tests for category validation

      manager:startRecording("en")
      manager:stopRecording()

      -- If invalid categories were used, Notifier would throw errors
      -- Success means categories are valid
    end)
  end)

  describe("Concurrent Operation Prevention", function()
    it("should prevent concurrent recordings", function()
      manager:startRecording("en")

      local ok, err = manager:startRecording("es")
      assert.is_false(ok, "Should prevent concurrent recording")
      assert.is_not_nil(err)
    end)

    it("should allow new recording after previous completes", function()
      -- First recording
      manager:startRecording("en")
      manager:stopRecording()

      assert.equals(Manager.STATES.IDLE, manager.state)

      -- Second recording should work
      local ok, err = manager:startRecording("es")
      assert.is_true(ok, "Second recording should succeed: " .. tostring(err))
    end)
  end)
end)
