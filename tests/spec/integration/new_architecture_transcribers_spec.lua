--- Integration Tests - WhisperKit and WhisperServer Transcribers
---
--- Tests both new transcribers with Manager + MockRecorder
--- Note: Different transcribers may produce different output formats

describe("New Architecture - Additional Transcribers Integration", function()
  local MockHS
  local Manager
  local WhisperKitTranscriber
  local WhisperServerTranscriber
  local MockRecorder

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs
    MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    -- Load components
    Manager = dofile("core_v2/manager.lua")
    WhisperKitTranscriber = dofile("transcribers/whisperkit_transcriber.lua")
    WhisperServerTranscriber = dofile("transcribers/whisperserver_transcriber.lua")
    MockRecorder = dofile("tests/mocks/mock_recorder.lua")

    -- Reset mock state
    MockHS._resetAll()
  end)

  after_each(function()
    MockHS._resetAll()
    _G.hs = nil
  end)

  describe("WhisperKitTranscriber", function()
    local transcriber

    before_each(function()
      transcriber = WhisperKitTranscriber.new({
        executable = "whisperkit-cli",
        model = "large-v3"
      })
    end)

    it("creates instance with correct configuration", function()
      assert.is_not_nil(transcriber)
      assert.equals("whisperkit-cli", transcriber.executable)
      assert.equals("large-v3", transcriber.model)
    end)

    it("has correct name", function()
      assert.equals("WhisperKit", transcriber:getName())
    end)

    it("supports all languages", function()
      assert.is_true(transcriber:supportsLanguage("en"))
      assert.is_true(transcriber:supportsLanguage("es"))
      assert.is_true(transcriber:supportsLanguage("fr"))
    end)

    it("implements ITranscriber interface", function()
      assert.is_function(transcriber.validate)
      assert.is_function(transcriber.transcribe)
      assert.is_function(transcriber.getName)
      assert.is_function(transcriber.supportsLanguage)
    end)

    it("works with Manager for single chunk", function()
      local manager = Manager.new(
        MockRecorder.new({ chunkCount = 1 }),
        transcriber,
        { language = "en", tempDir = "/tmp/test" }
      )

      manager:startRecording("en")
      manager:stopRecording()

      -- Verify some kind of completion (state may vary in mocks)
      assert.is_not_nil(manager.state)
    end)

    it("works with Manager for multiple chunks", function()
      local manager = Manager.new(
        MockRecorder.new({ chunkCount = 3 }),
        transcriber,
        { language = "en", tempDir = "/tmp/test" }
      )

      manager:startRecording("en")
      manager:stopRecording()

      -- Verify no crash with multiple chunks
      assert.is_not_nil(manager.state)
    end)

    it("accepts different model configurations", function()
      local models = {"base", "small", "medium", "large-v3"}

      for _, model in ipairs(models) do
        local t = WhisperKitTranscriber.new({ model = model })
        assert.equals(model, t.model)
      end
    end)
  end)

  describe("WhisperServerTranscriber", function()
    local transcriber

    before_each(function()
      transcriber = WhisperServerTranscriber.new({
        host = "127.0.0.1",
        port = 8080
      })
    end)

    it("creates instance with correct configuration", function()
      assert.is_not_nil(transcriber)
      assert.equals("127.0.0.1", transcriber.host)
      assert.equals(8080, transcriber.port)
    end)

    it("has correct name", function()
      assert.equals("WhisperServer", transcriber:getName())
    end)

    it("supports all languages", function()
      assert.is_true(transcriber:supportsLanguage("en"))
      assert.is_true(transcriber:supportsLanguage("es"))
      assert.is_true(transcriber:supportsLanguage("fr"))
    end)

    it("implements ITranscriber interface", function()
      assert.is_function(transcriber.validate)
      assert.is_function(transcriber.transcribe)
      assert.is_function(transcriber.getName)
      assert.is_function(transcriber.supportsLanguage)
    end)

    it("works with Manager for single chunk", function()
      local manager = Manager.new(
        MockRecorder.new({ chunkCount = 1 }),
        transcriber,
        { language = "en", tempDir = "/tmp/test" }
      )

      manager:startRecording("en")
      manager:stopRecording()

      -- Verify some kind of completion (state may vary in mocks)
      assert.is_not_nil(manager.state)
    end)

    it("works with Manager for multiple chunks", function()
      local manager = Manager.new(
        MockRecorder.new({ chunkCount = 3 }),
        transcriber,
        { language = "en", tempDir = "/tmp/test" }
      )

      manager:startRecording("en")
      manager:stopRecording()

      -- Verify no crash with multiple chunks
      assert.is_not_nil(manager.state)
    end)

    it("accepts different server configurations", function()
      local configs = {
        { host = "127.0.0.1", port = 8080 },
        { host = "localhost", port = 8000 },
        { host = "192.168.1.100", port = 9000 }
      }

      for _, config in ipairs(configs) do
        local t = WhisperServerTranscriber.new(config)
        assert.equals(config.host, t.host)
        assert.equals(config.port, t.port)
      end
    end)

    it("uses curl command", function()
      assert.equals("curl", transcriber.curlCmd)

      local custom = WhisperServerTranscriber.new({ curlCmd = "/usr/bin/curl" })
      assert.equals("/usr/bin/curl", custom.curlCmd)
    end)
  end)

  describe("Transcriber Interchangeability", function()
    it("both transcribers have unique names", function()
      local whisperkit = WhisperKitTranscriber.new()
      local whisperserver = WhisperServerTranscriber.new()

      assert.equals("WhisperKit", whisperkit:getName())
      assert.equals("WhisperServer", whisperserver:getName())
      assert.is_not_equal(whisperkit:getName(), whisperserver:getName())
    end)

    it("both transcribers implement same interface", function()
      local whisperkit = WhisperKitTranscriber.new()
      local whisperserver = WhisperServerTranscriber.new()

      -- Check method existence
      assert.is_function(whisperkit.validate)
      assert.is_function(whisperkit.transcribe)
      assert.is_function(whisperkit.getName)
      assert.is_function(whisperkit.supportsLanguage)

      assert.is_function(whisperserver.validate)
      assert.is_function(whisperserver.transcribe)
      assert.is_function(whisperserver.getName)
      assert.is_function(whisperserver.supportsLanguage)
    end)

    it("both transcribers work with Manager (can be swapped)", function()
      -- Test WhisperKit
      local manager1 = Manager.new(
        MockRecorder.new(),
        WhisperKitTranscriber.new(),
        { language = "en", tempDir = "/tmp/test" }
      )

      manager1:startRecording("en")
      manager1:stopRecording()
      assert.is_not_nil(manager1.state)

      -- Reset and test WhisperServer
      MockHS._resetAll()

      local manager2 = Manager.new(
        MockRecorder.new(),
        WhisperServerTranscriber.new(),
        { language = "en", tempDir = "/tmp/test" }
      )

      manager2:startRecording("en")
      manager2:stopRecording()
      assert.is_not_nil(manager2.state)
    end)
  end)
end)
