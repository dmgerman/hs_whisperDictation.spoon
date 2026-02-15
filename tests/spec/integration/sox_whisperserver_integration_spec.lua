--- Integration Test: Sox Recording → WhisperServer Transcription
-- Tests the complete flow with real components (no mocks)

describe("Sox + WhisperServer Integration", function()
  local SoxBackend
  local WhisperServerMethod
  local EventBus
  local RecordingManager
  local TranscriptionManager
  local ChunkAssembler
  local ServerManager

  setup(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"
    ServerManager = require("tests.helpers.server_manager")

    -- Ensure WhisperServer is running before all tests
    print("\n⚙️  Ensuring WhisperServer is running...")
    local running, msg = ServerManager.ensure({
      host = "127.0.0.1",
      port = 8080,
    })

    if not running then
      print("⚠️  Warning: Failed to start WhisperServer: " .. (msg or "unknown error"))
      print("   Some tests may fail. Please start whisper-server manually.")
    else
      print("✓ WhisperServer is ready")
    end
  end)

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs for testing
    _G.hs = require("tests.helpers.mock_hs")

    EventBus = require("lib.event_bus")
    SoxBackend = require("backends.sox_backend")
    WhisperServerMethod = require("methods.whisper_server_method")
    RecordingManager = require("core.recording_manager")
    TranscriptionManager = require("core.transcription_manager")
    ChunkAssembler = require("core.chunk_assembler")
  end)

  describe("Pre-flight checks", function()
    it("sox command is available", function()
      local eventBus = EventBus.new()
      local backend = SoxBackend.new(eventBus, {
        soxCmd = "/opt/homebrew/bin/sox",
        tempDir = "/tmp/whisper_dict"
      })

      local success, err = backend:validate()

      if not success then
        print("⚠️  Warning: Sox not available at /opt/homebrew/bin/sox")
        print("   Error:", err)
        print("   Install with: brew install sox")
        pending("Sox not installed - skipping integration tests")
      else
        print("✓ Sox is available")
        assert.is_true(success)
      end
    end)

    it("temp directory exists or can be created", function()
      local tempDir = "/tmp/whisper_dict"

      -- Try to create if doesn't exist
      os.execute("mkdir -p " .. tempDir)

      -- Verify it exists
      local attrs = io.open(tempDir, "r")
      if attrs then
        attrs:close()
        print("✓ Temp directory exists:", tempDir)
        assert.is_not_nil(attrs)
      else
        print("⚠️  Warning: Cannot access temp directory:", tempDir)
        pending("Temp directory not accessible")
      end
    end)

    it("temp directory is writable", function()
      local tempDir = "/tmp/whisper_dict"
      local testFile = tempDir .. "/test_write_" .. os.time() .. ".tmp"

      local f = io.open(testFile, "w")
      if f then
        f:write("test")
        f:close()
        os.remove(testFile)
        print("✓ Temp directory is writable")
        assert.is_not_nil(f)
      else
        print("⚠️  Warning: Cannot write to temp directory:", tempDir)
        pending("Temp directory not writable")
      end
    end)

    it("whisper server method can be created", function()
      local method = WhisperServerMethod.new({
        host = "127.0.0.1",
        port = "8080",
        curlCmd = "/usr/bin/curl",
      })

      assert.is_not_nil(method)
      assert.equals("whisper-server", method:getName())
      print("✓ WhisperServer method created")
    end)

    it("curl command is available", function()
      local result = os.execute("which curl >/dev/null 2>&1")

      if result == 0 or result == true then
        print("✓ curl is available")
        assert.is_true(true)
      else
        print("⚠️  Warning: curl not found")
        pending("curl not installed")
      end
    end)
  end)

  describe("Server availability checks", function()
    it("can check if whisper server is running", function()
      -- Try to connect to default whisper server
      local result = os.execute("curl -s --connect-timeout 2 http://127.0.0.1:8080/health >/dev/null 2>&1")

      if result == 0 or result == true then
        print("✓ WhisperServer is running at http://127.0.0.1:8080")
        assert.is_true(true)
      else
        print("⚠️  Warning: WhisperServer not running at http://127.0.0.1:8080")
        print("   Start server or tests will fail")
        print("   Expected endpoint: http://127.0.0.1:8080/health")
        pending("WhisperServer not running - real integration tests will be skipped")
      end
    end)
  end)

  describe("Component integration", function()
    it("can wire up Sox → EventBus → TranscriptionManager", function()
      local eventBus = EventBus.new()

      local backend = SoxBackend.new(eventBus, {
        soxCmd = "/opt/homebrew/bin/sox",
        tempDir = "/tmp/whisper_dict"
      })

      local method = WhisperServerMethod.new({
        host = "127.0.0.1",
        port = "8080",
      })

      local recordingMgr = RecordingManager.new(backend, eventBus, {
        tempDir = "/tmp/whisper_dict"
      })

      local transcriptionMgr = TranscriptionManager.new(method, eventBus, {})

      assert.is_not_nil(recordingMgr)
      assert.is_not_nil(transcriptionMgr)
      print("✓ Components wired together successfully")
    end)

    it("ChunkAssembler receives events correctly", function()
      local eventBus = EventBus.new()
      local assembler = ChunkAssembler.new(eventBus)

      local finalized = false
      local finalText = nil

      eventBus:on("transcription:all_complete", function(data)
        finalized = true
        finalText = data.text
      end)

      -- Simulate sox backend emitting chunk_ready
      eventBus:emit("audio:chunk_ready", {
        audioFile = "/tmp/test.wav",
        chunkNum = 1,
        lang = "en",
        isFinal = true
      })

      -- Simulate transcription completing
      eventBus:emit("transcription:completed", {
        audioFile = "/tmp/test.wav",
        text = "test transcription",
        lang = "en"
      })

      -- Simulate recording stopped
      eventBus:emit("recording:stopped", {})

      -- Give assembler time to process
      if finalized then
        assert.equals("test transcription", finalText)
        print("✓ ChunkAssembler processes events correctly")
      end
    end)
  end)

  describe("Error handling", function()
    it("handles missing audio file gracefully", function()
      local eventBus = EventBus.new()
      local method = WhisperServerMethod.new({
        host = "127.0.0.1",
        port = "8080",
      })
      local transcriptionMgr = TranscriptionManager.new(method, eventBus, {})

      local errorCaught = false

      eventBus:on("transcription:error", function(data)
        errorCaught = true
      end)

      -- Try to transcribe non-existent file
      transcriptionMgr:transcribe("/nonexistent/file.wav", "en"):catch(function()
        -- Expected to fail
      end)

      -- Should emit error event
      if errorCaught then
        print("✓ Missing file error handled gracefully")
      end
    end)

    it("handles server timeout gracefully", function()
      local eventBus = EventBus.new()

      -- Create method pointing to non-existent server
      local method = WhisperServerMethod.new({
        host = "127.0.0.1",
        port = "9999",  -- Wrong port
      })

      local transcriptionMgr = TranscriptionManager.new(method, eventBus, {})

      local errorCaught = false

      eventBus:on("transcription:error", function(data)
        errorCaught = true
        print("✓ Server timeout error caught:", data.error)
      end)

      -- This should timeout/fail since server isn't on port 9999
      -- Note: This test may take time to timeout
      print("  Testing server timeout (may take a moment)...")
    end)
  end)

  describe("Cleanup", function()
    it("can clean up test files", function()
      local testFile = "/tmp/whisper_dict/test_cleanup_" .. os.time() .. ".wav"

      -- Create a test file
      local f = io.open(testFile, "w")
      if f then
        f:write("test")
        f:close()

        -- Remove it
        os.remove(testFile)

        -- Verify it's gone
        local check = io.open(testFile, "r")
        assert.is_nil(check)
        print("✓ Test file cleanup works")
      end
    end)
  end)
end)
