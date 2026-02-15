--- Tests for MockTranscriber
--- Verifies mock behavior, configuration, and async simulation

local mock_hs = require("tests.helpers.mock_hs")
_G.hs = mock_hs

local MockTranscriber = dofile("tests/mocks/mock_transcriber.lua")

describe("MockTranscriber", function()
  local transcriber

  after_each(function()
    if transcriber then
      transcriber:cleanup()
    end
  end)

  describe("initialization", function()
    it("should create with default configuration", function()
      transcriber = MockTranscriber.new()
      assert.is_not_nil(transcriber)
      assert.equal("Transcribed: ", transcriber.transcriptPrefix)
      assert.equal(0.1, transcriber.delay)
      assert.is_false(transcriber.shouldFail)
    end)

    it("should accept custom transcriptPrefix", function()
      transcriber = MockTranscriber.new({transcriptPrefix = "TEXT: "})
      assert.equal("TEXT: ", transcriber.transcriptPrefix)
    end)

    it("should accept custom delay", function()
      transcriber = MockTranscriber.new({delay = 0.5})
      assert.equal(0.5, transcriber.delay)
    end)

    it("should accept shouldFail flag", function()
      transcriber = MockTranscriber.new({shouldFail = true})
      assert.is_true(transcriber.shouldFail)
    end)

    it("should accept custom supported languages", function()
      transcriber = MockTranscriber.new({supportedLanguages = {"en", "es"}})
      assert.same({"en", "es"}, transcriber.supportedLanguages)
    end)
  end)

  describe("interface implementation", function()
    before_each(function()
      transcriber = MockTranscriber.new()
    end)

    it("should implement getName", function()
      assert.equal("MockTranscriber", transcriber:getName())
    end)

    it("should implement validate", function()
      local success, err = transcriber:validate()
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("should implement supportsLanguage", function()
      assert.is_true(transcriber:supportsLanguage("en"))
      assert.is_true(transcriber:supportsLanguage("es"))
      assert.is_false(transcriber:supportsLanguage("unknown"))
    end)
  end)

  describe("transcribe", function()
    before_each(function()
      transcriber = MockTranscriber.new({delay = 0.01})
    end)

    it("should return success when started", function()
      local success, err = transcriber:transcribe(
        "/tmp/audio.wav",
        "en",
        function() end,
        function() end
      )
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("should fail synchronously when shouldFail=true and failureMode=sync", function()
      transcriber = MockTranscriber.new({shouldFail = true, failureMode = "sync"})
      local success, err = transcriber:transcribe(
        "/tmp/audio.wav",
        "en",
        function() end,
        function() end
      )
      assert.is_false(success)
      assert.matches("Transcription failed", err)
    end)

    it("should invoke onSuccess callback with transcribed text", function()
      local resultText = nil

      transcriber:transcribe(
        "/tmp/test-audio.wav",
        "en",
        function(text)
          resultText = text
        end,
        function() end
      )

      -- Wait for async transcription
      local startTime = os.time()
      while not resultText and (os.time() - startTime) < 2 do
        -- Wait
      end

      assert.is_not_nil(resultText)
      assert.matches("Transcribed: ", resultText)
      assert.matches("test%-audio.wav", resultText)
    end)

    it("should include filename in transcription", function()
      local resultText = nil

      transcriber:transcribe(
        "/tmp/dir/chunk-5.wav",
        "en",
        function(text)
          resultText = text
        end,
        function() end
      )

      -- Wait for result
      local startTime = os.time()
      while not resultText and (os.time() - startTime) < 2 do
        -- Wait
      end

      assert.matches("chunk%-5.wav", resultText)
    end)

    it("should use custom transcriptPrefix", function()
      transcriber = MockTranscriber.new({
        transcriptPrefix = "RESULT: ",
        delay = 0.01
      })
      local resultText = nil

      transcriber:transcribe(
        "/tmp/audio.wav",
        "en",
        function(text)
          resultText = text
        end,
        function() end
      )

      -- Wait for result
      local startTime = os.time()
      while not resultText and (os.time() - startTime) < 2 do
        -- Wait
      end

      assert.matches("^RESULT: ", resultText)
    end)

    it("should invoke onError when shouldFail=true and failureMode=async", function()
      transcriber = MockTranscriber.new({
        shouldFail = true,
        failureMode = "async",
        delay = 0.01
      })
      local errorCalled = false
      local errorMsg = nil

      transcriber:transcribe(
        "/tmp/audio.wav",
        "en",
        function() end,
        function(msg)
          errorCalled = true
          errorMsg = msg
        end
      )

      -- Wait for async error
      local startTime = os.time()
      while not errorCalled and (os.time() - startTime) < 2 do
        -- Wait
      end

      assert.is_true(errorCalled)
      assert.matches("Transcription failed", errorMsg)
    end)
  end)

  describe("language support", function()
    before_each(function()
      transcriber = MockTranscriber.new({
        supportedLanguages = {"en", "es", "fr"}
      })
    end)

    it("should support configured languages", function()
      assert.is_true(transcriber:supportsLanguage("en"))
      assert.is_true(transcriber:supportsLanguage("es"))
      assert.is_true(transcriber:supportsLanguage("fr"))
    end)

    it("should not support unconfigured languages", function()
      assert.is_false(transcriber:supportsLanguage("de"))
      assert.is_false(transcriber:supportsLanguage("ja"))
      assert.is_false(transcriber:supportsLanguage("unknown"))
    end)
  end)

  describe("validation", function()
    it("should validate successfully by default", function()
      transcriber = MockTranscriber.new()
      local success, err = transcriber:validate()
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("should fail validation when configured", function()
      transcriber = MockTranscriber.new({
        shouldFail = true,
        failureMode = "validate"
      })
      local success, err = transcriber:validate()
      assert.is_false(success)
      assert.matches("Validation failed", err)
    end)
  end)

  describe("cleanup", function()
    it("should not error when called", function()
      transcriber = MockTranscriber.new({delay = 1.0})
      transcriber:transcribe("/tmp/audio.wav", "en", function() end, function() end)

      -- Should not throw error
      assert.has_no.errors(function()
        transcriber:cleanup()
      end)
    end)

    it("should clear timers array", function()
      transcriber = MockTranscriber.new({delay = 0.5})
      transcriber:transcribe("/tmp/audio.wav", "en", function() end, function() end)

      assert.is_true(#transcriber._timers > 0)
      transcriber:cleanup()
      assert.equal(0, #transcriber._timers)
    end)

    it("should stop timers from running", function()
      transcriber = MockTranscriber.new()
      transcriber:transcribe("/tmp/audio.wav", "en", function() end, function() end)

      -- All timers should be running before cleanup
      for _, timer in ipairs(transcriber._timers) do
        assert.is_true(timer:running())
      end

      transcriber:cleanup()

      -- All timers should be stopped after cleanup
      for _, timer in ipairs(transcriber._timers) do
        assert.is_false(timer:running())
      end
    end)
  end)
end)
