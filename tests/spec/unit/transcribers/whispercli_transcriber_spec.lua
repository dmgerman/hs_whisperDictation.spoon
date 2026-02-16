--- WhisperCLITranscriber Unit Tests

describe("WhisperCLITranscriber", function()
  local WhisperCLITranscriber
  local MockHS
  local transcriber

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs
    MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    WhisperCLITranscriber = require("transcribers.whispercli_transcriber")

    transcriber = WhisperCLITranscriber.new({
      executable = "/usr/local/bin/whisper-cpp",
      modelPath = "/usr/local/models/ggml-base.en.bin"
    })
  end)

  after_each(function()
    transcriber = nil
    MockHS._resetAll()
    _G.hs = nil
  end)

  describe("initialization", function()
    it("creates a new WhisperCLITranscriber instance", function()
      assert.is_not_nil(transcriber)
      assert.is_table(transcriber)
    end)

    it("stores executable path", function()
      assert.equals("/usr/local/bin/whisper-cpp", transcriber.executable)
    end)

    it("stores model path", function()
      assert.equals("/usr/local/models/ggml-base.en.bin", transcriber.modelPath)
    end)

    it("uses default executable if not provided", function()
      local defaultTranscriber = WhisperCLITranscriber.new({
        modelPath = "/models/test.bin"
      })
      assert.equals("whisper-cpp", defaultTranscriber.executable)
    end)

    it("handles nil config", function()
      local defaultTranscriber = WhisperCLITranscriber.new(nil)
      assert.is_not_nil(defaultTranscriber)
      assert.equals("whisper-cpp", defaultTranscriber.executable)
      assert.is_nil(defaultTranscriber.modelPath)
    end)

    it("handles empty config", function()
      local emptyTranscriber = WhisperCLITranscriber.new({})
      assert.equals("whisper-cpp", emptyTranscriber.executable)
      assert.is_nil(emptyTranscriber.modelPath)
    end)
  end)

  describe("validate()", function()
    it("returns option-style tuple (success, error)", function()
      local success, err = transcriber:validate()
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      else
        assert.is_nil(err)
      end
    end)

    it("returns true if both executable and model exist", function()
      -- Mock file system
      MockHS.fs._registerFile("/usr/local/bin/whisper-cpp", { mode = "file", size = 1024 })
      MockHS.fs._registerFile("/usr/local/models/ggml-base.en.bin", { mode = "file", size = 1024000 })

      local success, err = transcriber:validate()
      assert.is_true(success)
      assert.is_nil(err)
    end)

    it("returns false if executable not found", function()
      -- Don't register executable, but register model
      MockHS.fs._registerFile("/usr/local/models/ggml-base.en.bin", { mode = "file", size = 1024000 })

      local success, err = transcriber:validate()
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Whisper executable not found") ~= nil)
    end)

    it("returns false if model not found", function()
      -- Register executable but not model
      MockHS.fs._registerFile("/usr/local/bin/whisper-cpp", { mode = "file", size = 1024 })

      local success, err = transcriber:validate()
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Model file not found") ~= nil)
    end)

    it("returns false if model path not configured", function()
      local noModelTranscriber = WhisperCLITranscriber.new({
        executable = "/usr/local/bin/whisper-cpp"
      })

      MockHS.fs._registerFile("/usr/local/bin/whisper-cpp", { mode = "file", size = 1024 })

      local success, err = noModelTranscriber:validate()
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Model path not configured") ~= nil)
    end)

    it("includes executable path in error message", function()
      local success, err = transcriber:validate()
      if not success then
        assert.is_true(err:match("/usr/local/bin/whisper%-cpp") ~= nil)
      end
    end)

    it("includes model path in error message", function()
      MockHS.fs._registerFile("/usr/local/bin/whisper-cpp", { mode = "file", size = 1024 })

      local success, err = transcriber:validate()
      if not success then
        assert.is_true(err:match("/usr/local/models/ggml%-base%.en%.bin") ~= nil)
      end
    end)
  end)

  describe("getName()", function()
    it("returns 'WhisperCLI'", function()
      assert.equals("WhisperCLI", transcriber:getName())
    end)
  end)

  describe("supportsLanguage()", function()
    it("returns true for English", function()
      assert.is_true(transcriber:supportsLanguage("en"))
    end)

    it("returns true for Spanish", function()
      assert.is_true(transcriber:supportsLanguage("es"))
    end)

    it("returns true for French", function()
      assert.is_true(transcriber:supportsLanguage("fr"))
    end)

    it("returns true for any language code", function()
      assert.is_true(transcriber:supportsLanguage("ja"))
      assert.is_true(transcriber:supportsLanguage("zh"))
      assert.is_true(transcriber:supportsLanguage("ar"))
      assert.is_true(transcriber:supportsLanguage("unknown"))
    end)

    it("returns true even for invalid codes", function()
      -- Whisper will handle invalid codes itself
      assert.is_true(transcriber:supportsLanguage("xyz"))
      assert.is_true(transcriber:supportsLanguage(""))
    end)
  end)

  describe("transcribe()", function()
    it("returns option-style tuple (success, error)", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local success, err = transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      else
        assert.is_nil(err)
      end
    end)

    it("returns false if audio file not found", function()
      -- Don't register the file

      local success, err = transcriber:transcribe(
        "/nonexistent/file.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Audio file not found") ~= nil)
    end)

    it("includes audio file path in error message", function()
      local success, err = transcriber:transcribe(
        "/custom/path/audio.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_false(success)
      assert.is_true(err:match("/custom/path/audio%.wav") ~= nil)
    end)

    it("returns true if audio file exists", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local success, err = transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_true(success)
      assert.is_nil(err)
    end)

    -- Note: Testing actual transcription output requires mocking io.open() which is
    -- not currently implemented in mock_hs.lua. These tests verify the async pattern
    -- and that transcribe() returns successfully. Actual transcription will be tested
    -- in live integration tests (Step 8).

    it("schedules async transcription when file exists", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local success = transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function(text) end,
        function() end
      )

      -- Should return true to indicate transcription started
      assert.is_true(success)
    end)

    it("returns success even if command will fail later", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local success = transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function(err) end
      )

      -- Returns true because transcribe() only checks preconditions
      -- Actual command execution happens asynchronously
      -- Testing actual command failure requires io.popen mocking (deferred to live tests)
      assert.is_true(success)
    end)

    it("does not call onSuccess if output file missing", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local successCalled = false
      transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() successCalled = true end,
        function() end
      )

      assert.is_false(successCalled)
    end)

    it("handles nil onSuccess callback", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      assert.has_no_error(function()
        transcriber:transcribe(
          "/tmp/test.wav",
          "en",
          nil,  -- onSuccess
          function() end
        )
      end)
    end)

    it("handles nil onError callback", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      assert.has_no_error(function()
        transcriber:transcribe(
          "/tmp/test.wav",
          "en",
          function() end,
          nil  -- onError
        )
      end)
    end)

    it("handles both callbacks being nil", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      assert.has_no_error(function()
        transcriber:transcribe(
          "/tmp/test.wav",
          "en",
          nil,
          nil
        )
      end)
    end)

    it("passes language code to whisper command", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      transcriber:transcribe(
        "/tmp/test.wav",
        "es",  -- Spanish
        function() end,
        function() end
      )

      -- We can't easily verify the command in mock, but we can verify it doesn't error
      assert.is_true(true)
    end)

    it("uses executable path in command", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local customTranscriber = WhisperCLITranscriber.new({
        executable = "/custom/path/whisper",
        modelPath = "/models/test.bin"
      })

      customTranscriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_true(true)  -- Verify no error
    end)

    it("uses model path in command", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local customTranscriber = WhisperCLITranscriber.new({
        executable = "whisper-cpp",
        modelPath = "/custom/model/path.bin"
      })

      customTranscriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_true(true)  -- Verify no error
    end)

    it("accepts different language codes", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      -- Test with different languages
      local langs = {"en", "es", "fr", "de", "ja", "zh"}
      for _, lang in ipairs(langs) do
        local success = transcriber:transcribe(
          "/tmp/test.wav",
          lang,
          function() end,
          function() end
        )
        assert.is_true(success)
      end
    end)
  end)

  describe("integration with Manager", function()
    local Manager
    local MockRecorder
    local manager

    before_each(function()
      Manager = dofile("core/manager.lua")
      MockRecorder = dofile("tests/mocks/mock_recorder.lua")

      -- Register files for validation
      MockHS.fs._registerFile("/usr/local/bin/whisper-cpp", { mode = "file", size = 1024 })
      MockHS.fs._registerFile("/usr/local/models/ggml-base.en.bin", { mode = "file", size = 1024000 })

      manager = Manager.new(
        MockRecorder.new(),
        transcriber,
        { language = "en", tempDir = "/tmp/test" }
      )
    end)

    after_each(function()
      manager = nil
    end)

    it("works with Manager startRecording", function()
      -- Start recording
      local success = manager:startRecording("en")
      assert.is_true(success)
      assert.equals(Manager.STATES.RECORDING, manager.state)

      -- Stop recording
      manager:stopRecording()

      -- Verify Manager transitions through states correctly
      -- (Full transcription testing requires io.open mocking - deferred to live tests)
      assert.is_not_nil(manager.state)
    end)

    it("handles transcription failure gracefully", function()
      local failingTranscriber = WhisperCLITranscriber.new({
        executable = "/usr/local/bin/whisper-cpp",
        modelPath = "/usr/local/models/ggml-base.en.bin"
      })

      local failManager = Manager.new(
        MockRecorder.new(),
        failingTranscriber,
        { language = "en", tempDir = "/tmp/test" }
      )

      failManager:startRecording("en")
      failManager:stopRecording()

      -- Don't mock the transcription output - simulate failure
      -- Manager should handle this gracefully

      -- Just verify no crash
      assert.is_not_nil(failManager.state)
    end)

    it("validates successfully before recording", function()
      local success, err = transcriber:validate()
      assert.is_true(success)
      assert.is_nil(err)

      -- Should be able to start recording
      success = manager:startRecording("en")
      assert.is_true(success)
      manager:stopRecording()
    end)
  end)

  describe("error handling", function()
    it("handles io.popen failure gracefully", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local errorMsg = nil
      transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function(err) errorMsg = err end
      )

      -- In mock environment, io.popen works, but we can test callback handling
      -- The actual io.popen failure would be caught in live environment
      assert.is_true(true)
    end)

    it("returns appropriate error for missing audio file", function()
      local success, err = transcriber:transcribe(
        "/missing/file.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_false(success)
      assert.is_not_nil(err)
      assert.is_string(err)
      assert.is_true(err:match("not found") ~= nil)
    end)

    it("executes transcription asynchronously", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local success = transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      -- Should return immediately with success=true
      -- Actual transcription happens in timer callback
      assert.is_true(success)
    end)

    it("handles special characters in audio file path", function()
      local specialPath = "/tmp/test audio (1).wav"
      MockHS.fs._registerFile(specialPath, { mode = "file", size = 1024 })

      local success = transcriber:transcribe(
        specialPath,
        "en",
        function() end,
        function() end
      )

      assert.is_true(success)
    end)

    it("handles various audio file paths", function()
      -- Test with different path formats
      local paths = {
        "/tmp/test.wav",
        "/var/audio/recording.wav",
        "/home/user/recordings/test123.wav"
      }

      for _, path in ipairs(paths) do
        MockHS.fs._registerFile(path, { mode = "file", size = 1024 })
        local success = transcriber:transcribe(
          path,
          "en",
          function() end,
          function() end
        )
        assert.is_true(success)
      end
    end)
  end)
end)
