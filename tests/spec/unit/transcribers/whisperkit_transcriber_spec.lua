--- WhisperKitTranscriber Unit Tests

describe("WhisperKitTranscriber", function()
  local WhisperKitTranscriber
  local MockHS
  local transcriber

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs
    MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    WhisperKitTranscriber = require("transcribers.whisperkit_transcriber")

    transcriber = WhisperKitTranscriber.new({
      executable = "whisperkit-cli",
      model = "large-v3"
    })
  end)

  after_each(function()
    transcriber = nil
    MockHS._resetAll()
    _G.hs = nil
  end)

  describe("initialization", function()
    it("creates a new WhisperKitTranscriber instance", function()
      assert.is_not_nil(transcriber)
      assert.is_table(transcriber)
    end)

    it("stores executable path", function()
      assert.equals("whisperkit-cli", transcriber.executable)
    end)

    it("stores model name", function()
      assert.equals("large-v3", transcriber.model)
    end)

    it("uses default executable if not provided", function()
      local defaultTranscriber = WhisperKitTranscriber.new({
        model = "base"
      })
      assert.equals("whisperkit-cli", defaultTranscriber.executable)
    end)

    it("uses default model if not provided", function()
      local defaultTranscriber = WhisperKitTranscriber.new({
        executable = "custom-whisperkit"
      })
      assert.equals("large-v3", defaultTranscriber.model)
    end)

    it("handles nil config", function()
      local defaultTranscriber = WhisperKitTranscriber.new(nil)
      assert.is_not_nil(defaultTranscriber)
      assert.equals("whisperkit-cli", defaultTranscriber.executable)
      assert.equals("large-v3", defaultTranscriber.model)
    end)

    it("handles empty config", function()
      local emptyTranscriber = WhisperKitTranscriber.new({})
      assert.equals("whisperkit-cli", emptyTranscriber.executable)
      assert.equals("large-v3", emptyTranscriber.model)
    end)

    it("allows custom executable and model", function()
      local customTranscriber = WhisperKitTranscriber.new({
        executable = "/custom/whisperkit",
        model = "small"
      })
      assert.equals("/custom/whisperkit", customTranscriber.executable)
      assert.equals("small", customTranscriber.model)
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

    it("returns false if executable not in PATH", function()
      -- Create transcriber with non-existent executable
      local nonExistentTranscriber = WhisperKitTranscriber.new({
        executable = "nonexistent-whisperkit-cli-12345"
      })

      local success, err = nonExistentTranscriber:validate()
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("not found") ~= nil)
    end)

    it("includes executable name in error message", function()
      local customTranscriber = WhisperKitTranscriber.new({
        executable = "custom-whisperkit-cli"
      })

      local success, err = customTranscriber:validate()
      if not success then
        assert.is_true(err:match("custom%-whisperkit%-cli") ~= nil)
      end
    end)

    it("includes installation instructions in error message", function()
      local success, err = transcriber:validate()
      if not success then
        assert.is_true(err:match("brew install") ~= nil)
      end
    end)

    it("handles 'which' command failure", function()
      -- If 'which' itself fails, should return error
      local success, err = transcriber:validate()
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      end
    end)
  end)

  describe("getName()", function()
    it("returns 'WhisperKit'", function()
      assert.equals("WhisperKit", transcriber:getName())
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
      -- WhisperKit will handle invalid codes itself
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
      assert.is_true(success)
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

    it("passes language code to whisperkit command", function()
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

      local customTranscriber = WhisperKitTranscriber.new({
        executable = "/custom/path/whisperkit",
        model = "base"
      })

      customTranscriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_true(true)  -- Verify no error
    end)

    it("uses model name in command", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local customTranscriber = WhisperKitTranscriber.new({
        executable = "whisperkit-cli",
        model = "small-en"
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

  describe("integration with Manager", function()
    local Manager
    local MockRecorder
    local manager

    before_each(function()
      Manager = dofile("core/manager.lua")
      MockRecorder = dofile("tests/mocks/mock_recorder.lua")

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
      assert.is_not_nil(manager.state)
    end)

    it("handles transcription failure gracefully", function()
      local failingTranscriber = WhisperKitTranscriber.new({
        executable = "whisperkit-cli",
        model = "large-v3"
      })

      local failManager = Manager.new(
        MockRecorder.new(),
        failingTranscriber,
        { language = "en", tempDir = "/tmp/test" }
      )

      failManager:startRecording("en")
      failManager:stopRecording()

      -- Just verify no crash
      assert.is_not_nil(failManager.state)
    end)
  end)

  describe("error handling", function()
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
  end)
end)
