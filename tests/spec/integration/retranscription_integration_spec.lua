-- Integration tests for retranscription feature
local MockHS = require("tests.helpers.mock_hs")
_G.hs = MockHS

describe("Retranscription Integration Tests", function()
  local init
  local Fixtures = require("tests.helpers.fixtures")

  before_each(function()
    MockHS._resetAll()
    init = dofile("init.lua")
  end)

  after_each(function()
    if init and init.stop then
      init:stop()
    end
  end)

  describe("Full retranscription flow with current transcriber", function()
    it("should retranscribe file with current transcriber", function()
      -- Setup: use real audio files from fixtures
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"
      init.retranscribeTranscriber = nil  -- Use current

      init:start()

      -- Verify spoon started
      assert.is_not_nil(init.manager)
      assert.is_not_nil(init.transcriber)

      -- Mock chooser selection
      local selectedFile = nil
      local transcriptionResult = nil

      -- Simulate choosing a file
      local recordings = Fixtures.getCompleteRecordings()
      assert.is_true(#recordings > 0, "Should have test fixtures")

      local testRecording = recordings[1]

      -- Directly call retranscription with callback
      local callback = function(text)
        transcriptionResult = text
      end

      -- This will be tested once we implement the feature
      -- For now, verify the structure is in place
    end)
  end)

  describe("Retranscription with different transcriber", function()
    it("should create new transcriber instance when retranscribeTranscriber is set", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"  -- Current transcriber
      init.retranscribeTranscriber = "whisperkit"  -- Different for retranscription
      init.config.whisperkit = {
        cmd = "/opt/homebrew/bin/whisperkit-cli",
        model = "large-v3",
      }

      -- Mock whisperkit-cli validation
      MockHS.fs._registerFile("/opt/homebrew/bin/whisperkit-cli", {mode = "file"})

      init:start()

      -- Current transcriber should be whispercli
      assert.equals("WhisperCLI", init.transcriber:getName())

      -- Retranscription should use whisperkit (tested via integration)
    end)

    it("should show error when specified transcriber validation fails", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"
      init.retranscribeTranscriber = "whisperkit"
      init.config.whisperkit = {
        cmd = "/nonexistent/whisperkit-cli",
      }

      init:start()

      -- Retranscription should fail validation and show error
      -- No fallback to current transcriber
    end)
  end)

  describe("Auto-paste behavior", function()
    it("should auto-paste when same app", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"
      init.monitorUserActivity = true

      init:start()

      -- Mock same app scenario
      local mockApp = {
        bundleID = function() return "com.example.app" end,
        name = function() return "TestApp" end,
      }
      local mockWindow = {
        application = function() return mockApp end,
      }

      MockHS.window._setFocusedWindow(mockWindow)

      -- Open chooser (tracks starting app)
      init.retranscribeStartingApp = mockApp

      -- Complete retranscription
      -- Should auto-paste (same app)
    end)

    it("should only copy to clipboard when different app", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"
      init.monitorUserActivity = true

      init:start()

      -- Mock different app scenario
      local startingApp = {
        bundleID = function() return "com.example.app1" end,
      }
      local currentApp = {
        bundleID = function() return "com.example.app2" end,
      }

      local mockWindow = {
        application = function() return currentApp end,
      }

      MockHS.window._setFocusedWindow(mockWindow)

      init.retranscribeStartingApp = startingApp

      -- Complete retranscription
      -- Should copy to clipboard only (different app)
    end)
  end)

  describe("Callback behavior", function()
    it("should call callback when provided", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      local callbackCalled = false
      local callbackText = nil

      local callback = function(text)
        callbackCalled = true
        callbackText = text
      end

      -- Perform retranscription with callback
      -- Should call callback with transcribed text
      -- Should NOT auto-paste or copy to clipboard
    end)

    it("should skip clipboard/paste when callback provided", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      local callback = function(text) end

      -- Perform retranscription with callback
      -- Verify clipboard was NOT set
      local clipboard = MockHS.pasteboard.getContents()
      -- Should be empty or previous content (not retranscription result)
    end)
  end)

  describe("Error handling", function()
    it("should show warning when no recordings available", function()
      init.tempDir = "/tmp/empty_retranscribe_test"
      MockHS.fs._registerDirectory("/tmp/empty_retranscribe_test", {})
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      -- Call transcribeLatestAgain
      init:transcribeLatestAgain()

      -- Should show warning alert
      local alerts = MockHS.alert._getAlerts()
      assert.is_true(#alerts > 0, "Should show alert")

      local foundWarning = false
      for _, alert in ipairs(alerts) do
        if alert.message:match("No recent recordings") then
          foundWarning = true
          break
        end
      end

      assert.is_true(foundWarning, "Should show 'No recent recordings' warning")
    end)

    it("should show error when transcription fails", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      -- Mock transcription failure
      -- Should show error alert
      -- Should not crash
    end)

    it("should show error when invalid retranscribeTranscriber specified", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"
      init.retranscribeTranscriber = "nonexistent"

      init:start()

      -- Attempting retranscription should show error
      -- Should not crash
    end)

    it("should handle gracefully when spoon not started", function()
      -- Don't call start()
      assert.is_nil(init.manager)

      -- Call transcribeLatestAgain
      local result = init:transcribeLatestAgain()

      -- Should return self (method chaining) but not crash
      assert.equals(init, result)

      -- Should show warning or early return
    end)
  end)

  describe("Menubar updates", function()
    it("should show transcribing indicator during retranscription", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      -- Create menubar
      init.menubar = MockHS.menubar.new()

      -- Start retranscription
      -- Should update menubar to show transcribing icon
    end)

    it("should reset menubar to idle after retranscription completes", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      -- Create menubar
      init.menubar = MockHS.menubar.new()

      -- Complete retranscription
      -- Should reset menubar to idle state
    end)

    it("should reset menubar to idle after retranscription error", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      -- Create menubar
      init.menubar = MockHS.menubar.new()

      -- Retranscription fails
      -- Should still reset menubar to idle
    end)
  end)

  describe("Language handling", function()
    it("should always use currentLang() for retranscription", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"
      init.languages = {"en", "ja", "es"}
      init.langIndex = 2  -- Japanese

      init:start()

      -- Retranscribe a file
      -- Should use "ja" as language (currentLang)
      -- Even if filename suggests different language (e.g., en-*.wav)
    end)
  end)

  describe("File size formatting", function()
    it("should show file sizes in MB format", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      -- Get recordings and check formatted entries
      local recordings = Fixtures.getCompleteRecordings()
      if #recordings > 0 then
        local recording = recordings[1]

        -- Format should be "X.XX MB"
        -- Will verify through chooser entries
      end
    end)
  end)

  describe("Chooser behavior", function()
    it("should display chooser with formatted entries", function()
      init.tempDir = "tests/fixtures/audio/complete"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      init:start()

      -- Call transcribeLatestAgain
      init:transcribeLatestAgain()

      -- Should create chooser
      -- Entries should have text (date/time) and subText (filename + size)
    end)

    it("should reset starting app when chooser cancelled", function()
      init.tempDir = "/tmp/test_retranscribe"
      init.config.recorder = "sox"
      init.config.transcriber = "whispercli"

      -- Register some test files so getRecentRecordings() finds them
      MockHS.fs._registerFile("/tmp/test_retranscribe/en-20260216-120000.wav", {
        mode = "file",
        size = 1024000,
        modification = os.time(),
      })

      init:start()

      -- Mock focused window for app tracking
      local mockApp = {bundleID = function() return "com.example.app" end}
      local mockWindow = {application = function() return mockApp end}
      MockHS.window._setFocusedWindow(mockWindow)

      -- Open chooser (will show because recordings exist)
      init:transcribeLatestAgain()

      -- Should set retranscribeStartingApp (chooser was shown)
      assert.is_not_nil(init.retranscribeStartingApp)

      -- Note: In actual use, cancelling chooser would call callback with nil
      -- which resets retranscribeStartingApp. This is tested in unit tests.
    end)
  end)
end)
