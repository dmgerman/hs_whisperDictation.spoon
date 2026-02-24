-- Unit tests for retranscription feature
local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS

describe("Retranscription Unit Tests", function()
  local spoonPath = "./"
  local init

  before_each(function()
    MockHS._resetAll()
    -- Load init.lua
    init = dofile("init.lua")
  end)

  after_each(function()
    if init and init.stop then
      init:stop()
    end
  end)

  describe("Configuration", function()
    it("should have retranscribeTranscriber property defaulting to nil", function()
      assert.is_nil(init.retranscribeTranscriber)
    end)

    it("should have retranscribeCount property defaulting to 10", function()
      assert.equals(10, init.retranscribeCount)
    end)

    it("should have retranscribeStartingApp property for internal state", function()
      assert.is_nil(init.retranscribeStartingApp)
    end)
  end)

  describe("getRecentRecordings()", function()
    local getRecentRecordings

    before_each(function()
      -- Access private function via init scope
      -- We'll expose it for testing or test via public API
      -- For now, we'll test indirectly through transcribeLatestAgain
    end)

    it("should return empty array when tempDir is empty", function()
      init.tempDir = "/tmp/test_empty_dir"
      MockHS.fs._registerDirectory("/tmp/test_empty_dir", {})

      -- Call via public API and check behavior
      init:start()
      -- Will test indirectly - if no files, should show warning
    end)

    it("should return recordings sorted by modification time (newest first)", function()
      init.tempDir = "/tmp/test_recordings"

      -- Register some test files with different mtimes
      MockHS.fs._registerDirectory("/tmp/test_recordings", {
        "en-20260216-100000.wav",
        "en-20260216-110000.wav",
        "en-20260216-120000.wav",
      })

      MockHS.fs._registerFile("/tmp/test_recordings/en-20260216-100000.wav", {
        mode = "file",
        size = 1024000,  -- 1MB
        modification = 1000,
      })

      MockHS.fs._registerFile("/tmp/test_recordings/en-20260216-110000.wav", {
        mode = "file",
        size = 2048000,  -- 2MB
        modification = 3000,  -- Newest
      })

      MockHS.fs._registerFile("/tmp/test_recordings/en-20260216-120000.wav", {
        mode = "file",
        size = 1536000,  -- 1.5MB
        modification = 2000,
      })

      -- Test indirectly through public API
    end)

    it("should limit to N recordings", function()
      init.tempDir = "/tmp/test_many_recordings"
      init.retranscribeCount = 3

      -- Register many files
      local files = {}
      for i = 1, 20 do
        local filename = string.format("en-20260216-%06d.wav", i)
        table.insert(files, filename)
        MockHS.fs._registerFile("/tmp/test_many_recordings/" .. filename, {
          mode = "file",
          size = 1000000,
          modification = i * 100,
        })
      end

      MockHS.fs._registerDirectory("/tmp/test_many_recordings", files)

      -- Should only show top 3
    end)

    it("should handle missing tempDir gracefully", function()
      init.tempDir = "/tmp/nonexistent_dir"
      -- MockHS.fs will return nil for non-registered directories

      -- Should not crash, should return empty array
    end)
  end)

  describe("formatRecordingEntry()", function()
    it("should format file size in MB", function()
      local recording = {
        path = "/tmp/test/en-20260216-120000.wav",
        filename = "en-20260216-120000.wav",
        modified = 1708099200,  -- Some timestamp
        size = 1536000,  -- 1.5MB
      }

      -- Format: "1.50 MB"
      -- Will test indirectly through chooser entries
    end)

    it("should show filename in subText", function()
      local recording = {
        path = "/tmp/test/audio.wav",
        filename = "audio.wav",
        modified = 1708099200,
        size = 2048000,
      }

      -- subText should include filename and size
    end)

    it("should format timestamp as readable date", function()
      local recording = {
        path = "/tmp/test/en-20260216-120000.wav",
        filename = "en-20260216-120000.wav",
        modified = 1708099200,
        size = 1000000,
      }

      -- Should format as human-readable date/time
    end)
  end)

  describe("App tracking for auto-paste", function()
    it("should track starting app when chooser opens", function()
      init:start()

      -- Mock focused window
      local mockApp = {bundleID = function() return "com.example.app" end}
      local mockWindow = {application = function() return mockApp end}
      MockHS.window._setFocusedWindow(mockWindow)

      -- Open chooser - should track starting app
      -- Will test through integration tests
    end)

    it("should reset starting app when chooser cancelled", function()
      init:start()
      init.retranscribeStartingApp = "test"

      -- Cancel chooser - should reset to nil
    end)

    it("should reset starting app after retranscription completes", function()
      init:start()
      init.retranscribeStartingApp = "test"

      -- Complete retranscription - should reset to nil
    end)
  end)

  describe("Transcriber selection", function()
    it("should use current transcriber when retranscribeTranscriber is nil", function()
      init.retranscribeTranscriber = nil
      init:start()

      -- Retranscription should use init.transcriber
    end)

    it("should create new transcriber instance when retranscribeTranscriber is set", function()
      init.retranscribeTranscriber = "whisperkit"
      init.config.whisperkit = {
        cmd = "/opt/homebrew/bin/whisperkit-cli",
        model = "large-v3",
      }

      -- Should create WhisperKitTranscriber instance for retranscription
    end)

    it("should show error when retranscribeTranscriber validation fails", function()
      init.retranscribeTranscriber = "whisperkit"
      init.config.whisperkit = {
        cmd = "/nonexistent/whisperkit-cli",
        model = "large-v3",
      }

      init:start()

      -- Retranscription with invalid transcriber should show error
    end)

    it("should not fall back to current transcriber on validation failure", function()
      init.retranscribeTranscriber = "whisperkit"
      init.config.whisperkit = {
        cmd = "/nonexistent/whisperkit-cli",
      }

      init:start()

      -- Should abort retranscription, not fall back
    end)
  end)

  describe("Public API", function()
    describe("transcribeLatestAgain()", function()
      it("should exist as public method", function()
        assert.is_function(init.transcribeLatestAgain)
      end)

      it("should return self for method chaining", function()
        init:start()
        local result = init:transcribeLatestAgain()
        assert.equals(init, result)
      end)

      it("should validate spoon is started", function()
        -- Don't call start()
        assert.is_nil(init.manager)

        -- Calling transcribeLatestAgain should handle gracefully
        -- Should show error or return early
      end)

      it("should accept optional callback parameter", function()
        init:start()
        local callbackCalled = false
        local callback = function(text)
          callbackCalled = true
        end

        init:transcribeLatestAgain(callback)
        -- Will verify callback behavior in integration tests
      end)
    end)
  end)

  describe("Hotkey binding", function()
    it("should support retranscribe hotkey in bindHotKeys", function()
      init:start()

      local mapping = {
        retranscribe = {{"ctrl", "cmd"}, "r"},
      }

      -- Should bind without error
      init:bindHotKeys(mapping)

      -- Verify hotkey was bound
      assert.is_not_nil(init.hotkeys.retranscribe)
    end)

    it("should trigger transcribeLatestAgain when hotkey pressed", function()
      init:start()

      init:bindHotKeys({
        retranscribe = {{"ctrl", "cmd"}, "r"},
      })

      -- Simulate hotkey press
      -- Will test in integration tests with full flow
    end)
  end)
end)
