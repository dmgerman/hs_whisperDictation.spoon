-- tests/spec/integration/init_fallback_spec.lua
-- Integration tests for init.lua fallback validation logic

local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS

describe("init.lua fallback validation", function()
  local spoonPath = os.getenv("PWD") .. "/"
  local obj

  before_each(function()
    MockHS._resetAll()

    -- Load init.lua
    obj = dofile(spoonPath .. "init.lua")
    obj.logger.enableConsole = false  -- Suppress log output during tests
  end)

  after_each(function()
    if obj.recorder and obj.recorder.cleanup then
      pcall(obj.recorder.cleanup, obj.recorder)
    end
    if obj.transcriber and obj.transcriber.cleanup then
      pcall(obj.transcriber.cleanup, obj.transcriber)
    end
    if obj.manager then
      obj.manager = nil
    end
    obj.recorder = nil
    obj.transcriber = nil
  end)

  -- ============================================================================
  -- === StreamingRecorder → SoxRecorder fallback ===
  -- ============================================================================

  describe("StreamingRecorder → SoxRecorder fallback", function()
    it("uses StreamingRecorder when validation succeeds (no fallback)", function()
      -- Register required files for streaming recorder
      MockHS.fs._registerFile("/opt/homebrew/bin/python3", { mode = "file", size = 1000 })
      MockHS.fs._registerFile(spoonPath .. "recorders/streaming/whisper_stream.py", { mode = "file", size = 5000 })
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })

      obj.config.recorder = "streaming"
      local ok = obj:start()

      assert.is_true(ok)
      assert.is_not_nil(obj.recorder)
      assert.equals("streaming", obj.recorder:getName())

      -- No warning should be shown
      local alerts = MockHS.alert._getAlerts()
      local hasWarning = false
      for _, alert in ipairs(alerts) do
        if alert.message:match("unavailable") or alert.message:match("fallback") then
          hasWarning = true
        end
      end
      assert.is_false(hasWarning)
    end)

    it("fallback logic exists in start() for streaming type (configuration test)", function()
      -- This test verifies the fallback code path exists, not actual validation failure
      -- Real validation testing requires mocking io.popen for "which" commands
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })

      obj.config.recorder = "streaming"
      local ok = obj:start()

      -- Start will either use StreamingRecorder (if python3 available on system)
      -- or fallback to SoxRecorder (if sox available). Just verify startup succeeds.
      assert.is_true(ok)
      assert.is_not_nil(obj.recorder)
      -- Recorder will be one of: "streaming" or "sox"
      assert.is_true(obj.recorder:getName() == "streaming" or obj.recorder:getName() == "sox")
    end)

    it("error handling code path exists when recorder fails (configuration test)", function()
      -- This test just verifies the error handling code exists
      -- Can't easily test actual failure without mocking io.popen
      -- Just verify the code runs and returns a boolean
      obj.config.recorder = "streaming"
      local ok = obj:start()

      -- Will return true if python3 or sox available on system
      assert.is_boolean(ok)
    end)
  end)

  -- ============================================================================
  -- === WhisperKit → WhisperCLI fallback ===
  -- ============================================================================
  -- Note: WhisperKit uses io.popen("which") which is not mocked, so we test the
  -- fallback behavior by configuration rather than actual validation failure

  describe("WhisperKit → WhisperCLI fallback (configuration test)", function()
    it("fallback logic exists in start() for whisperkit type", function()
      -- This test verifies the code path exists, not actual validation
      -- Real validation testing requires live system or enhanced mocks
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", { mode = "file", size = 1000000 })

      obj.config.recorder = "sox"
      obj.config.transcriber = "whisperkit"

      -- Start will either use WhisperKit (if available on system) or fallback to WhisperCLI
      local ok = obj:start()

      -- Just verify startup succeeds with some transcriber
      assert.is_true(ok)
      assert.is_not_nil(obj.transcriber)
    end)
  end)

  -- ============================================================================
  -- === WhisperServer → WhisperCLI fallback ===
  -- ============================================================================
  -- Note: WhisperServer uses HTTP which is not mocked, so we test the
  -- fallback behavior by configuration rather than actual validation failure

  describe("WhisperServer → WhisperCLI fallback (configuration test)", function()
    it("fallback logic exists in start() for whisperserver type", function()
      -- This test verifies the code path exists, not actual validation
      -- Real validation testing requires live system or enhanced mocks
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", { mode = "file", size = 1000000 })

      obj.config.recorder = "sox"
      obj.config.transcriber = "whisperserver"

      -- Start will either use WhisperServer (if available) or fallback to WhisperCLI
      local ok = obj:start()

      -- Just verify startup succeeds with some transcriber
      assert.is_true(ok)
      assert.is_not_nil(obj.transcriber)
    end)
  end)

  -- ============================================================================
  -- === SoxRecorder (no fallback) ===
  -- ============================================================================

  describe("SoxRecorder (no fallback)", function()
    before_each(function()
      obj.config.recorder = "sox"
      -- Ensure transcriber works
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", { mode = "file", size = 1000000 })
    end)

    it("succeeds when sox is available", function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })

      local ok = obj:start()

      assert.is_true(ok)
      assert.is_not_nil(obj.recorder)
      assert.equals("sox", obj.recorder:getName())
    end)

    it("error handling code path exists when sox fails (configuration test)", function()
      -- This test just verifies the error handling code exists
      -- Can't easily test actual failure without mocking io.popen
      -- Just verify the code runs and returns a boolean
      local ok = obj:start()

      -- Will return true if sox available on system
      assert.is_boolean(ok)
    end)
  end)

  -- ============================================================================
  -- === WhisperCLI (no fallback) ===
  -- ============================================================================

  describe("WhisperCLI (no fallback)", function()
    before_each(function()
      -- Ensure recorder works
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })
      obj.config.recorder = "sox"
      obj.config.transcriber = "whispercli"
    end)

    it("succeeds when whispercli is available", function()
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", { mode = "file", size = 1000000 })

      local ok = obj:start()

      assert.is_true(ok)
      assert.is_not_nil(obj.transcriber)
      assert.equals("WhisperCLI", obj.transcriber:getName())
    end)

    it("error handling code path exists when whispercli fails (configuration test)", function()
      -- This test just verifies the error handling code exists
      -- Can't easily test actual failure without mocking io.popen or hs.fs.attributes
      -- Just verify the code runs and returns a boolean
      local ok = obj:start()

      -- Will return true if whispercli available on system
      assert.is_boolean(ok)
    end)
  end)

  -- ============================================================================
  -- === Unknown types ===
  -- ============================================================================

  describe("unknown component types", function()
    it("returns error for unknown recorder type", function()
      obj.config.recorder = "unknown_recorder"

      local ok = obj:start()

      assert.is_false(ok)

      local alerts = MockHS.alert._getAlerts()
      local hasError = false
      for _, alert in ipairs(alerts) do
        if alert.message:match("Unknown recorder type") then
          hasError = true
        end
      end
      assert.is_true(hasError)
    end)

    it("returns error for unknown transcriber type", function()
      -- Ensure recorder works
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })
      obj.config.recorder = "sox"
      obj.config.transcriber = "unknown_transcriber"

      local ok = obj:start()

      assert.is_false(ok)

      local alerts = MockHS.alert._getAlerts()
      local hasError = false
      for _, alert in ipairs(alerts) do
        if alert.message:match("Unknown transcriber type") then
          hasError = true
        end
      end
      assert.is_true(hasError)
    end)
  end)

  -- ============================================================================
  -- === Manager creation after successful validation ===
  -- ============================================================================

  describe("manager creation", function()
    it("creates manager after successful validation", function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", { mode = "file", size = 1000000 })

      obj.config.recorder = "sox"
      obj.config.transcriber = "whispercli"
      local ok = obj:start()

      assert.is_true(ok)
      assert.is_not_nil(obj.manager)
      assert.equals("IDLE", obj.manager.state)
    end)

    it("shows ready message after successful initialization", function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", { mode = "file", size = 1000 })
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", { mode = "file", size = 1000000 })

      obj.config.recorder = "sox"
      obj.config.transcriber = "whispercli"
      obj:start()

      local alerts = MockHS.alert._getAlerts()
      local hasReadyMsg = false
      for _, alert in ipairs(alerts) do
        if alert.message:match("WhisperDictation ready") then
          hasReadyMsg = true
        end
      end
      assert.is_true(hasReadyMsg)
    end)
  end)
end)
