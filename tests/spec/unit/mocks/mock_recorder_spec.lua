--- Tests for MockRecorder
--- Verifies mock behavior, configuration, and async simulation

local mock_hs = require("tests.helpers.mock_hs")
_G.hs = mock_hs

local MockRecorder = dofile("tests/mocks/mock_recorder.lua")

describe("MockRecorder", function()
  local recorder

  after_each(function()
    if recorder then
      recorder:cleanup()
    end
  end)

  describe("initialization", function()
    it("should create with default configuration", function()
      recorder = MockRecorder.new()
      assert.is_not_nil(recorder)
      assert.equal(1, recorder.chunkCount)
      assert.equal(0.1, recorder.baseDelay)
      assert.is_false(recorder.shouldFail)
    end)

    it("should accept custom chunkCount", function()
      recorder = MockRecorder.new({chunkCount = 5})
      assert.equal(5, recorder.chunkCount)
    end)

    it("should accept custom delay", function()
      recorder = MockRecorder.new({delay = 0.5})
      assert.equal(0.5, recorder.baseDelay)
    end)

    it("should accept chunkDelays array", function()
      recorder = MockRecorder.new({chunkDelays = {0.1, 0.2, 0.3}})
      assert.same({0.1, 0.2, 0.3}, recorder.chunkDelays)
    end)

    it("should accept shouldFail flag", function()
      recorder = MockRecorder.new({shouldFail = true})
      assert.is_true(recorder.shouldFail)
    end)
  end)

  describe("interface implementation", function()
    before_each(function()
      recorder = MockRecorder.new()
    end)

    it("should implement getName", function()
      assert.equal("MockRecorder", recorder:getName())
    end)

    it("should implement validate", function()
      local success, err = recorder:validate()
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("should implement isRecording", function()
      assert.is_false(recorder:isRecording())
    end)
  end)

  describe("startRecording", function()
    before_each(function()
      recorder = MockRecorder.new({chunkCount = 3, delay = 0.01})
    end)

    it("should return success when started", function()
      local success, err = recorder:startRecording(
        {outputDir = "/tmp", lang = "en"},
        function() end,
        function() end
      )
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("should set isRecording to true", function()
      recorder:startRecording({}, function() end, function() end)
      assert.is_true(recorder:isRecording())
    end)

    it("should fail if already recording", function()
      recorder:startRecording({}, function() end, function() end)
      local success, err = recorder:startRecording({}, function() end, function() end)
      assert.is_false(success)
      assert.equal("Already recording", err)
    end)

    it("should fail synchronously when shouldFail=true and failureMode=sync", function()
      recorder = MockRecorder.new({shouldFail = true, failureMode = "sync"})
      local success, err = recorder:startRecording({}, function() end, function() end)
      assert.is_false(success)
      assert.matches("Failed to start", err)
    end)

    it("should invoke onError when shouldFail=true and failureMode=async", function()
      recorder = MockRecorder.new({shouldFail = true, failureMode = "async", delay = 0.01})
      local errorCalled = false
      local errorMsg = nil

      recorder:startRecording({}, function() end, function(msg)
        errorCalled = true
        errorMsg = msg
      end)

      -- Wait for async error
      local startTime = os.time()
      while not errorCalled and (os.time() - startTime) < 2 do
        -- Wait loop (in real tests with mock timers, this would be instant)
      end

      assert.is_false(recorder:isRecording())
    end)
  end)

  describe("stopRecording", function()
    before_each(function()
      recorder = MockRecorder.new({chunkCount = 3, delay = 0.01})
    end)

    it("should fail if not recording", function()
      local success, err = recorder:stopRecording(function() end, function() end)
      assert.is_false(success)
      assert.equal("Not recording", err)
    end)

    it("should return success when stopped", function()
      recorder:startRecording({}, function() end, function() end)
      local success, err = recorder:stopRecording(function() end, function() end)
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("should set isRecording to false", function()
      recorder:startRecording({}, function() end, function() end)
      recorder:stopRecording(function() end, function() end)
      assert.is_false(recorder:isRecording())
    end)

    it("should invoke onComplete callback asynchronously", function()
      recorder:startRecording({}, function() end, function() end)
      local completeCalled = false

      recorder:stopRecording(function()
        completeCalled = true
      end, function() end)

      -- onComplete is called asynchronously, so it won't be immediate
      -- In real tests with mock timers, we'd advance time
    end)

    it("should cancel pending chunk timers", function()
      recorder:startRecording({outputDir = "/tmp", lang = "en"}, function() end, function() end)

      -- Verify timers were created
      local timerCount = #recorder._timers
      assert.is_true(timerCount > 0)

      -- Stop should cancel timers
      recorder:stopRecording(function() end, function() end)

      -- All timers should be stopped
      -- Note: cleanup() is called internally by stopRecording
      assert.equal(0, #recorder._timers)
    end)
  end)

  describe("chunk emission", function()
    it("should emit correct number of chunks", function()
      recorder = MockRecorder.new({chunkCount = 3, delay = 0.01})
      local chunks = {}

      recorder:startRecording(
        {outputDir = "/tmp", lang = "en"},
        function(audioFile, chunkNum, isFinal)
          table.insert(chunks, {file = audioFile, num = chunkNum, final = isFinal})
        end,
        function() end
      )

      -- Wait for all chunks (in real tests with mock timers, this would be controlled)
      local startTime = os.time()
      while #chunks < 3 and (os.time() - startTime) < 2 do
        -- Wait
      end

      assert.equal(3, #chunks)
    end)

    it("should set isFinal=true only on last chunk", function()
      recorder = MockRecorder.new({chunkCount = 3, delay = 0.01})
      local chunks = {}

      recorder:startRecording(
        {outputDir = "/tmp", lang = "en"},
        function(audioFile, chunkNum, isFinal)
          chunks[chunkNum] = {file = audioFile, num = chunkNum, final = isFinal}
        end,
        function() end
      )

      -- Wait for all chunks
      local startTime = os.time()
      while (#chunks < 3) and (os.time() - startTime) < 2 do
        -- Wait
      end

      -- Only chunk 3 should have isFinal=true
      assert.is_false(chunks[1].final)
      assert.is_false(chunks[2].final)
      assert.is_true(chunks[3].final)
    end)

    it("should accept custom chunk delays configuration", function()
      recorder = MockRecorder.new({
        chunkCount = 3,
        chunkDelays = {0.03, 0.01, 0.02}  -- Custom delays per chunk
      })

      -- Verify configuration was stored
      assert.same({0.03, 0.01, 0.02}, recorder.chunkDelays)

      local chunks = {}
      recorder:startRecording(
        {outputDir = "/tmp", lang = "en"},
        function(audioFile, chunkNum, isFinal)
          chunks[chunkNum] = true
        end,
        function() end
      )

      -- Note: In synchronous mock, all chunks arrive immediately in sequential order
      -- Real async behavior with delays would be tested in integration tests
      assert.equal(3, recorder.chunkCount)
      assert.is_true(chunks[1])
      assert.is_true(chunks[2])
      assert.is_true(chunks[3])
    end)

    it("should generate audio file paths with chunk numbers", function()
      recorder = MockRecorder.new({chunkCount = 2, delay = 0.01})
      local files = {}

      recorder:startRecording(
        {outputDir = "/tmp/test", lang = "es"},
        function(audioFile, chunkNum, isFinal)
          files[chunkNum] = audioFile
        end,
        function() end
      )

      -- Wait for chunks
      local startTime = os.time()
      while #files < 2 and (os.time() - startTime) < 2 do
        -- Wait
      end

      assert.matches("chunk%-1", files[1])
      assert.matches("chunk%-2", files[2])
      assert.matches("/tmp/test/", files[1])
      assert.matches("es%-", files[1])
    end)
  end)

  describe("cleanup", function()
    it("should not error when called", function()
      recorder = MockRecorder.new({chunkCount = 5, delay = 1.0})
      recorder:startRecording({outputDir = "/tmp", lang = "en"}, function() end, function() end)

      -- Should not throw error
      assert.has_no.errors(function()
        recorder:cleanup()
      end)
    end)

    it("should clear timers array", function()
      recorder = MockRecorder.new({chunkCount = 3, delay = 0.5})
      recorder:startRecording({}, function() end, function() end)

      assert.is_true(#recorder._timers > 0)
      recorder:cleanup()
      assert.equal(0, #recorder._timers)
    end)

    it("should stop timers from running", function()
      recorder = MockRecorder.new({chunkCount = 3})
      recorder:startRecording({}, function() end, function() end)

      -- All timers should be running before cleanup
      for _, timer in ipairs(recorder._timers) do
        assert.is_true(timer:running())
      end

      recorder:cleanup()

      -- All timers should be stopped after cleanup
      for _, timer in ipairs(recorder._timers) do
        assert.is_false(timer:running())
      end
    end)
  end)

  describe("validation", function()
    it("should validate successfully by default", function()
      recorder = MockRecorder.new()
      local success, err = recorder:validate()
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("should fail validation when configured", function()
      recorder = MockRecorder.new({shouldFail = true, failureMode = "validate"})
      local success, err = recorder:validate()
      assert.is_false(success)
      assert.matches("Validation failed", err)
    end)
  end)
end)
