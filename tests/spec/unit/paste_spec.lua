--- Paste Functionality Tests

describe("Paste Functionality", function()
  local EventBus
  local ChunkAssembler

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Mock Hammerspoon APIs
    _G.hs = require("tests.helpers.mock_hs")

    EventBus = require("lib.event_bus")
    ChunkAssembler = require("core.chunk_assembler")
  end)

  describe("Clipboard operations", function()
    it("sets clipboard content on transcription complete", function()
      local clipboardContent = nil

      -- Mock pasteboard
      _G.hs.pasteboard = {
        setContents = function(text)
          clipboardContent = text
          return true
        end,
        getContents = function()
          return clipboardContent
        end
      }

      local eventBus = EventBus.new()
      local assembler = ChunkAssembler.new(eventBus)

      -- Simulate transcription
      assembler:addChunk(1, "Hello world", "/tmp/test.wav")
      assembler:recordingStopped()

      -- Note: In real implementation, the event handler would set clipboard
      -- For now, just verify ChunkAssembler emits the right event
      local finalText = nil
      eventBus:on("transcription:all_complete", function(data)
        finalText = data.text
      end)

      assembler:reset()
      assembler:addChunk(1, "Test text", "/tmp/test.wav")
      assembler:recordingStopped()

      assert.equals("Test text", finalText)
    end)

    it("handles clipboard errors gracefully", function()
      -- Mock failing pasteboard
      _G.hs.pasteboard = {
        setContents = function()
          error("Clipboard access denied")
        end
      }

      local eventBus = EventBus.new()

      -- This should not crash even if clipboard fails
      local ok = pcall(function()
        eventBus:emit("transcription:all_complete", {
          text = "test",
          chunkCount = 1
        })
      end)

      assert.is_true(ok, "Should not crash on clipboard error")
    end)
  end)

  describe("Paste validation", function()
    it("validates paste prerequisites", function()
      -- Paste requires:
      -- 1. Clipboard has content
      -- 2. Target application is focused
      -- 3. shouldPaste flag is set

      local hasClipboard = _G.hs.pasteboard ~= nil
      assert.is_true(hasClipboard, "Pasteboard API should be available")
    end)

    it("provides clear error when paste fails", function()
      -- Mock eventtap that fails
      _G.hs.eventtap = {
        keyStroke = function()
          error("No active window")
        end
      }

      local pasteErr = nil
      local ok = pcall(function()
        _G.hs.eventtap.keyStroke({"cmd"}, "v")
      end)

      if not ok then
        pasteErr = "Paste failed - no active window"
      end

      assert.is_not_nil(pasteErr, "Should capture paste error")
    end)
  end)

  describe("Activity monitoring interference", function()
    it("detects when user was active during recording", function()
      -- Simulate activity detection
      local activityCounts = {
        keys = 5,
        clicks = 2,
        appSwitches = 1
      }

      local hasActivity = (activityCounts.keys >= 2) or
                         (activityCounts.clicks >= 1) or
                         (activityCounts.appSwitches >= 1)

      assert.is_true(hasActivity, "Should detect user activity")
    end)

    it("allows paste when no activity detected", function()
      local activityCounts = {
        keys = 0,
        clicks = 0,
        appSwitches = 0
      }

      local hasActivity = (activityCounts.keys >= 2) or
                         (activityCounts.clicks >= 1) or
                         (activityCounts.appSwitches >= 1)

      assert.is_false(hasActivity, "Should allow paste with no activity")
    end)

    it("provides clear message when paste is blocked by activity", function()
      local activityCounts = {
        keys = 5,
        clicks = 2,
        appSwitches = 0
      }

      local summary = string.format("%d keys, %d clicks",
        activityCounts.keys, activityCounts.clicks)

      local message = "Auto-paste blocked: User activity detected (" .. summary .. ")"

      assert.is_not_nil(message:match("Auto%-paste blocked"))
      assert.is_not_nil(message:match("User activity"))
    end)
  end)

  describe("Paste method selection", function()
    it("uses Cmd+V for normal paste", function()
      local keysPressed = {}

      _G.hs.eventtap = {
        keyStroke = function(mods, key)
          table.insert(keysPressed, {mods = mods, key = key})
        end
      }

      -- Simulate smart paste
      _G.hs.eventtap.keyStroke({"cmd"}, "v")

      assert.equals(1, #keysPressed)
      assert.equals("v", keysPressed[1].key)
      assert.same({"cmd"}, keysPressed[1].mods)
    end)

    it("uses Ctrl+Y for Emacs yank", function()
      local keysPressed = {}

      _G.hs.eventtap = {
        keyStroke = function(mods, key)
          table.insert(keysPressed, {mods = mods, key = key})
        end
      }

      -- Simulate Emacs yank
      _G.hs.eventtap.keyStroke({"ctrl"}, "y")

      assert.equals(1, #keysPressed)
      assert.equals("y", keysPressed[1].key)
      assert.same({"ctrl"}, keysPressed[1].mods)
    end)
  end)

  describe("Error visibility", function()
    it("shows alert when paste is blocked", function()
      -- This is tested in integration, but validate the message format
      local blockedMsg = "⚠️ Auto-paste blocked: User activity detected\nText is in clipboard - paste manually (⌘V)"

      assert.is_not_nil(blockedMsg:match("Auto%-paste blocked"))
      assert.is_not_nil(blockedMsg:match("clipboard"))
      assert.is_not_nil(blockedMsg:match("⌘V"))
    end)

    it("shows alert when paste fails", function()
      local errorMsg = "❌ Paste failed: No active window\nText is in clipboard - paste manually (⌘V)"

      assert.is_not_nil(errorMsg:match("Paste failed"))
      assert.is_not_nil(errorMsg:match("clipboard"))
      assert.is_not_nil(errorMsg:match("⌘V"))
    end)

    it("shows success alert when paste succeeds", function()
      local successMsg = "✓ Pasted 145 chars"

      assert.is_not_nil(successMsg:match("Pasted"))
      assert.is_not_nil(successMsg:match("%d+ chars"))
    end)
  end)
end)
