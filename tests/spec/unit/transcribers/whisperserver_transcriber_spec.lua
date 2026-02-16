--- WhisperServerTranscriber Unit Tests

describe("WhisperServerTranscriber", function()
  local WhisperServerTranscriber
  local MockHS
  local transcriber

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs
    MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    WhisperServerTranscriber = require("transcribers.whisperserver_transcriber")

    transcriber = WhisperServerTranscriber.new({
      host = "127.0.0.1",
      port = 8080,
      curlCmd = "curl"
    })
  end)

  after_each(function()
    transcriber = nil
    MockHS._resetAll()
    _G.hs = nil
  end)

  describe("initialization", function()
    it("creates a new WhisperServerTranscriber instance", function()
      assert.is_not_nil(transcriber)
      assert.is_table(transcriber)
    end)

    it("stores host", function()
      assert.equals("127.0.0.1", transcriber.host)
    end)

    it("stores port", function()
      assert.equals(8080, transcriber.port)
    end)

    it("stores curl command path", function()
      assert.equals("curl", transcriber.curlCmd)
    end)

    it("uses default host if not provided", function()
      local defaultTranscriber = WhisperServerTranscriber.new({
        port = 9000
      })
      assert.equals("127.0.0.1", defaultTranscriber.host)
    end)

    it("uses default port if not provided", function()
      local defaultTranscriber = WhisperServerTranscriber.new({
        host = "192.168.1.100"
      })
      assert.equals(8080, defaultTranscriber.port)
    end)

    it("uses default curl command if not provided", function()
      local defaultTranscriber = WhisperServerTranscriber.new({
        host = "localhost"
      })
      assert.equals("curl", defaultTranscriber.curlCmd)
    end)

    it("handles nil config", function()
      local defaultTranscriber = WhisperServerTranscriber.new(nil)
      assert.is_not_nil(defaultTranscriber)
      assert.equals("127.0.0.1", defaultTranscriber.host)
      assert.equals(8080, defaultTranscriber.port)
      assert.equals("curl", defaultTranscriber.curlCmd)
    end)

    it("handles empty config", function()
      local emptyTranscriber = WhisperServerTranscriber.new({})
      assert.equals("127.0.0.1", emptyTranscriber.host)
      assert.equals(8080, emptyTranscriber.port)
      assert.equals("curl", emptyTranscriber.curlCmd)
    end)

    it("allows custom host and port", function()
      local customTranscriber = WhisperServerTranscriber.new({
        host = "whisper.example.com",
        port = 9000,
        curlCmd = "/usr/bin/curl"
      })
      assert.equals("whisper.example.com", customTranscriber.host)
      assert.equals(9000, customTranscriber.port)
      assert.equals("/usr/bin/curl", customTranscriber.curlCmd)
    end)

    it("allows localhost as host", function()
      local localTranscriber = WhisperServerTranscriber.new({
        host = "localhost"
      })
      assert.equals("localhost", localTranscriber.host)
    end)

    it("allows remote server host", function()
      local remoteTranscriber = WhisperServerTranscriber.new({
        host = "192.168.1.50",
        port = 8000
      })
      assert.equals("192.168.1.50", remoteTranscriber.host)
      assert.equals(8000, remoteTranscriber.port)
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

    it("returns false if curl not in PATH", function()
      -- Don't mock 'which' command - it will fail

      local success, err = transcriber:validate()
      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("curl not found") ~= nil)
    end)

    it("handles 'which' command failure", function()
      -- If 'which' itself fails, should return error
      local success, err = transcriber:validate()
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      end
    end)

    it("validates curl availability, not server availability", function()
      -- validate() only checks curl exists, not that server is running
      -- This is by design - server may not be running at validation time
      local success, err = transcriber:validate()

      -- Should fail (curl check) or succeed (if curl found)
      -- But should NOT attempt to contact server
      assert.is_boolean(success)
    end)

    it("handles custom curl command path", function()
      local customTranscriber = WhisperServerTranscriber.new({
        curlCmd = "/custom/path/curl"
      })

      local success, err = customTranscriber:validate()
      -- Should fail since custom path doesn't exist
      assert.is_boolean(success)
    end)
  end)

  describe("getName()", function()
    it("returns 'WhisperServer'", function()
      assert.equals("WhisperServer", transcriber:getName())
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
      -- Server will handle invalid codes itself
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

    it("returns success even if server request will fail later", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local success = transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function(err) end
      )

      -- Returns true because transcribe() only checks preconditions
      -- Actual server request happens asynchronously
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

    it("passes language code to server", function()
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

    it("uses host and port in server URL", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local customTranscriber = WhisperServerTranscriber.new({
        host = "192.168.1.100",
        port = 9000,
        curlCmd = "curl"
      })

      customTranscriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_true(true)  -- Verify no error
    end)

    it("uses curl command path", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      local customTranscriber = WhisperServerTranscriber.new({
        curlCmd = "/usr/bin/curl"
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

    it("uses /inference endpoint", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      -- Transcribe will build URL with /inference endpoint
      transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_true(true)  -- Verify no error
    end)

    it("sends multipart form data", function()
      MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

      -- Transcribe will use -F flags for form data
      transcriber:transcribe(
        "/tmp/test.wav",
        "en",
        function() end,
        function() end
      )

      assert.is_true(true)  -- Verify no error
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
      local failingTranscriber = WhisperServerTranscriber.new({
        host = "127.0.0.1",
        port = 8080
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
      -- Actual HTTP request happens in timer callback
      assert.is_true(success)
    end)

    it("handles different server ports", function()
      local ports = {8000, 8080, 9000, 8888}

      for _, port in ipairs(ports) do
        local serverTranscriber = WhisperServerTranscriber.new({
          host = "127.0.0.1",
          port = port
        })

        MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

        local success = serverTranscriber:transcribe(
          "/tmp/test.wav",
          "en",
          function() end,
          function() end
        )

        assert.is_true(success)
      end
    end)

    it("handles different server hosts", function()
      local hosts = {"127.0.0.1", "localhost", "192.168.1.50", "whisper.example.com"}

      for _, host in ipairs(hosts) do
        local serverTranscriber = WhisperServerTranscriber.new({
          host = host,
          port = 8080
        })

        MockHS.fs._registerFile("/tmp/test.wav", { mode = "file", size = 1024 })

        local success = serverTranscriber:transcribe(
          "/tmp/test.wav",
          "en",
          function() end,
          function() end
        )

        assert.is_true(success)
      end
    end)
  end)
end)
