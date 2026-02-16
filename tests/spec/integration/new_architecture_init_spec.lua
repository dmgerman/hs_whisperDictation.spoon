--- Integration tests for new architecture init.lua integration
--- Tests initialization, configuration, and basic spoon interface

local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS

describe("New Architecture - init.lua Integration", function()
  local spoonPath = "/Users/dmg/.hammerspoon/Spoons/hs_whisperDictation.spoon/"
  local init

  before_each(function()
    MockHS._resetAll()
    -- Load init.lua fresh each time
    package.loaded[spoonPath .. "init"] = nil
    init = dofile(spoonPath .. "init.lua")
  end)

  describe("Configuration", function()
    it("has new architecture config structure", function()
      assert.is_not_nil(init.config)
      assert.equals("sox", init.config.recorder)
      assert.equals("whispercli", init.config.transcriber)
    end)

    it("has sox recorder config", function()
      assert.is_not_nil(init.config.sox)
      assert.equals("/opt/homebrew/bin/sox", init.config.sox.soxCmd)
      assert.is_nil(init.config.sox.audioInputDevice)  -- default = nil
    end)

    it("has whispercli transcriber config", function()
      assert.is_not_nil(init.config.whispercli)
      assert.is_not_nil(init.config.whispercli.executable)
      assert.is_not_nil(init.config.whispercli.modelPath)
    end)

    it("allows audioInputDevice configuration", function()
      init.config.sox.audioInputDevice = "BlackHole 2ch"
      assert.equals("BlackHole 2ch", init.config.sox.audioInputDevice)
    end)
  end)

  describe("Initialization with valid components", function()
    before_each(function()
      -- Register sox and whisper executables as existing
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", {mode = "file", size = 1024 * 1024})
    end)

    it("creates manager on start", function()
      local ok = init:start()

      assert.is_true(ok)
      assert.is_not_nil(init.manager)
      assert.equals("IDLE", init.manager.state)
    end)

    it("creates recorder instance", function()
      init:start()

      assert.is_not_nil(init.recorder)
      assert.equals("sox", init.recorder:getName())
    end)

    it("creates transcriber instance", function()
      init:start()

      assert.is_not_nil(init.transcriber)
      assert.equals("WhisperCLI", init.transcriber:getName())
    end)

    it("shows success notification", function()
      init:start()

      local alerts = MockHS.alert._getAlerts()
      local found = false
      for _, alert in ipairs(alerts) do
        if alert.message:match("WhisperDictation ready") then
          found = true
          break
        end
      end
      assert.is_true(found, "Should show ready notification")
    end)

    it("creates menubar", function()
      init:start()

      assert.is_not_nil(init.menubar)
    end)
  end)

  describe("Initialization with invalid components", function()
    before_each(function()
      -- Explicitly clear all registered files before each test
      MockHS._resetAll()
      package.loaded[spoonPath .. "init"] = nil
      init = dofile(spoonPath .. "init.lua")
    end)

    it("fails if sox not found", function()
      -- Don't register sox executable
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", {mode = "file", size = 1024 * 1024})

      local ok = init:start()

      assert.is_false(ok)
      assert.is_nil(init.manager)
    end)

    it("fails if whisper executable not found", function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", {mode = "file", size = 1024})
      -- Don't register whisper executable
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", {mode = "file", size = 1024 * 1024})

      local ok = init:start()

      assert.is_false(ok)
      assert.is_nil(init.manager)
    end)

    it("fails if whisper model not found", function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", {mode = "file", size = 1024})
      -- Don't register model file

      local ok = init:start()

      assert.is_false(ok)
      assert.is_nil(init.manager)
    end)

    it("shows error notification on failure", function()
      -- No files registered

      init:start()

      local alerts = MockHS.alert._getAlerts()
      local found = false
      for _, alert in ipairs(alerts) do
        if alert.message:match("error") or alert.message:match("failed") or alert.message:match("not found") then
          found = true
          break
        end
      end
      assert.is_true(found, "Should show error notification")
    end)
  end)

  describe("Recording lifecycle via spoon interface", function()
    before_each(function()
      -- Register all required files
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", {mode = "file", size = 1024 * 1024})

      init:start()
    end)

    it("can start recording via beginTranscribe", function()
      init:beginTranscribe()

      assert.equals("RECORDING", init.manager.state)
      assert.is_true(init:isRecording())
    end)

    it("can stop recording via endTranscribe", function()
      init:beginTranscribe()

      -- Register audio file that will be created
      local audioFile = init.recorder._currentAudioFile
      MockHS.fs._registerFile(audioFile, {mode = "file", size = 1024})

      init:endTranscribe()

      -- Manager should transition through TRANSCRIBING to IDLE (synchronous in tests)
      assert.equals("IDLE", init.manager.state)
      assert.is_false(init:isRecording())
    end)

    it("can toggle recording on and off", function()
      -- Toggle on
      init:toggleTranscribe()
      assert.equals("RECORDING", init.manager.state)

      -- Register audio file
      local audioFile = init.recorder._currentAudioFile
      MockHS.fs._registerFile(audioFile, {mode = "file", size = 1024})

      -- Toggle off
      init:toggleTranscribe()
      assert.equals("IDLE", init.manager.state)
    end)

    it("completes full recording cycle with transcription", function()
      init:beginTranscribe()

      -- Register audio file
      local audioFile = init.recorder._currentAudioFile
      MockHS.fs._registerFile(audioFile, {mode = "file", size = 1024})

      -- Register transcript file that whisper will create
      MockHS.fs._registerFile(audioFile .. ".txt", {
        mode = "file",
        size = 100,
        contents = "Test transcription"
      })

      init:endTranscribe()

      -- Check final state
      assert.equals("IDLE", init.manager.state)
      assert.equals(0, init.manager.pendingTranscriptions)

      -- Check clipboard
      local clipboard = MockHS.pasteboard.getContents()
      assert.is_not_nil(clipboard)
      assert.is_true(clipboard:match("Test transcription") ~= nil)
    end)
  end)

  describe("Error handling", function()
    before_each(function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", {mode = "file", size = 1024 * 1024})

      init:start()
    end)

    it("handles start without initialization", function()
      local uninitializedInit = dofile(spoonPath .. "init.lua")

      uninitializedInit:beginTranscribe()

      -- Should log error but not crash
      assert.is_nil(uninitializedInit.manager)
    end)

    it("prevents recording when already recording", function()
      init:beginTranscribe()

      local stateBefore = init.manager.state
      init:beginTranscribe()  -- Try to start again

      -- Should remain in RECORDING state, not create duplicate
      assert.equals(stateBefore, init.manager.state)
    end)

    it("prevents stopping when not recording", function()
      -- Manager is IDLE

      init:endTranscribe()

      -- Should remain IDLE
      assert.equals("IDLE", init.manager.state)
    end)
  end)

  describe("Audio device configuration", function()
    before_each(function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", {mode = "file", size = 1024 * 1024})
    end)

    it("uses default audio device when not specified", function()
      init.config.sox.audioInputDevice = nil

      init:start()

      assert.is_nil(init.recorder.audioInputDevice)
    end)

    it("uses specified audio device when configured", function()
      init.config.sox.audioInputDevice = "BlackHole 2ch"

      init:start()

      assert.equals("BlackHole 2ch", init.recorder.audioInputDevice)
    end)

    it("passes device to sox command", function()
      init.config.sox.audioInputDevice = "BlackHole 2ch"
      init:start()

      init:beginTranscribe()

      -- Check that recorder was created with device
      assert.equals("BlackHole 2ch", init.recorder.audioInputDevice)
    end)
  end)

  describe("Cleanup", function()
    before_each(function()
      MockHS.fs._registerFile("/opt/homebrew/bin/sox", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/opt/homebrew/bin/whisper-cli", {mode = "file", size = 1024})
      MockHS.fs._registerFile("/usr/local/whisper/ggml-large-v3.bin", {mode = "file", size = 1024 * 1024})

      init:start()
    end)

    it("cleans up manager on stop", function()
      init:stop()

      assert.is_nil(init.manager)
      assert.is_nil(init.recorder)
      assert.is_nil(init.transcriber)
    end)

    it("removes menubar on stop", function()
      local menubarBefore = init.menubar

      init:stop()

      assert.is_nil(init.menubar)
    end)
  end)
end)
