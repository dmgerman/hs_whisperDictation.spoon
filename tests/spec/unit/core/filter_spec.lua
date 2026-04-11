--- Tests for whisperFilters - Post-transcription text filtering
---
--- Covers: Manager._finalize with onTextReady callback,
--- clipboard-before-IDLE ordering, filter error fallback

local mock_hs = require("tests.helpers.mock_hs")
_G.hs = mock_hs

local Manager = dofile("core/manager.lua")
local MockRecorder = dofile("tests/mocks/mock_recorder.lua")
local MockTranscriber = dofile("tests/mocks/mock_transcriber.lua")

describe("whisperFilters", function()
  local manager, recorder, transcriber, config

  before_each(function()
    mock_hs._resetAll()
    config = {
      language = "en",
      tempDir = "/tmp/whisper_test",
    }
    recorder = MockRecorder.new({chunkCount = 1})
    transcriber = MockTranscriber.new()
    manager = Manager.new(recorder, transcriber, config)
  end)

  after_each(function()
    if recorder then recorder:cleanup() end
    if transcriber then transcriber:cleanup() end
  end)

  --- Helper: put manager into TRANSCRIBING state with a result, then call _finalize
  local function setupAndFinalize()
    manager:transitionTo(Manager.STATES.RECORDING, "test")
    manager:transitionTo(Manager.STATES.TRANSCRIBING, "test")
    manager.results[1] = "Hello world"
    manager:_finalize()
  end

  describe("Manager._finalize with onTextReady", function()
    it("should call onTextReady with assembled text and transitionToIdle", function()
      local receivedText = nil
      local receivedCallback = nil

      manager.onTextReady = function(text, transitionToIdle)
        receivedText = text
        receivedCallback = transitionToIdle
      end

      setupAndFinalize()

      assert.equals("Hello world", receivedText)
      assert.is_function(receivedCallback)
    end)

    it("should stay in TRANSCRIBING until transitionToIdle is called", function()
      local savedTransition = nil

      manager.onTextReady = function(text, transitionToIdle)
        savedTransition = transitionToIdle
        -- Don't call transitionToIdle yet - simulating async filter
      end

      setupAndFinalize()

      -- Manager should still be in TRANSCRIBING (filter hasn't completed)
      assert.equals(Manager.STATES.TRANSCRIBING, manager.state)

      -- Now call transitionToIdle (simulating filter completion)
      savedTransition()
      assert.equals(Manager.STATES.IDLE, manager.state)
    end)

    it("should allow clipboard to be set before IDLE transition", function()
      local stateAtClipboardSet = nil

      manager.onTextReady = function(text, transitionToIdle)
        mock_hs.pasteboard.setContents("filtered: " .. text)
        stateAtClipboardSet = manager.state
        transitionToIdle()
      end

      setupAndFinalize()

      -- Clipboard was set while still in TRANSCRIBING
      assert.equals(Manager.STATES.TRANSCRIBING, stateAtClipboardSet)
      -- After transitionToIdle, now in IDLE
      assert.equals(Manager.STATES.IDLE, manager.state)
      -- Clipboard has filtered text
      assert.equals("filtered: Hello world", mock_hs.pasteboard.getContents())
    end)

    it("should use direct clipboard when onTextReady is nil", function()
      manager.onTextReady = nil

      setupAndFinalize()

      -- Should transition to IDLE and set clipboard directly
      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals("Hello world", mock_hs.pasteboard.getContents())
    end)
  end)

  describe("onTextReady with simulated filter", function()
    it("should pass text through uppercase filter before clipboard", function()
      manager.onTextReady = function(text, transitionToIdle)
        mock_hs.pasteboard.setContents(text:upper())
        transitionToIdle()
      end

      setupAndFinalize()

      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals("HELLO WORLD", mock_hs.pasteboard.getContents())
    end)

    it("should handle filter error by using original text", function()
      manager.onTextReady = function(text, transitionToIdle)
        -- Simulate filter failure: fall back to original
        mock_hs.pasteboard.setContents(text)
        transitionToIdle()
      end

      setupAndFinalize()

      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals("Hello world", mock_hs.pasteboard.getContents())
    end)
  end)

  describe("hs.task filter execution", function()
    it("should create task with correct shell and arguments", function()
      local createdLaunchPath = nil
      local createdArgs = nil

      mock_hs.task._registerCreationCallback(function(launchPath, callbackFn, args)
        createdLaunchPath = launchPath
        createdArgs = args
      end)

      mock_hs.task._setNextOutput(0, "filtered output\n", "")

      manager.onTextReady = function(text, transitionToIdle)
        local task = mock_hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
          if exitCode == 0 and stdOut and #stdOut > 0 then
            mock_hs.pasteboard.setContents(stdOut:gsub("\n$", ""))
          else
            mock_hs.pasteboard.setContents(text)
          end
          transitionToIdle()
        end, {"-l", "-c", "my-filter-cmd"})
        task:setInput(text)
        task:start()
      end

      setupAndFinalize()

      assert.equals("/bin/zsh", createdLaunchPath)
      assert.equals("-l", createdArgs[1])
      assert.equals("-c", createdArgs[2])
      assert.equals("my-filter-cmd", createdArgs[3])
      assert.equals("filtered output", mock_hs.pasteboard.getContents())
      assert.equals(Manager.STATES.IDLE, manager.state)

      mock_hs.task._clearCreationCallback()
    end)

    it("should fall back to original text on task failure", function()
      mock_hs.task._setNextOutput(1, "", "command not found")

      manager.onTextReady = function(text, transitionToIdle)
        local task = mock_hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
          if exitCode == 0 and stdOut and #stdOut > 0 then
            mock_hs.pasteboard.setContents(stdOut:gsub("\n$", ""))
          else
            mock_hs.pasteboard.setContents(text)
          end
          transitionToIdle()
        end, {"-l", "-c", "bad-cmd"})
        task:setInput(text)
        task:start()
      end

      setupAndFinalize()

      assert.equals(Manager.STATES.IDLE, manager.state)
      assert.equals("Hello world", mock_hs.pasteboard.getContents())
    end)

    it("should fall back to original text on empty stdout", function()
      mock_hs.task._setNextOutput(0, "", "")

      manager.onTextReady = function(text, transitionToIdle)
        local task = mock_hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
          if exitCode == 0 and stdOut and #stdOut > 0 then
            mock_hs.pasteboard.setContents(stdOut:gsub("\n$", ""))
          else
            mock_hs.pasteboard.setContents(text)
          end
          transitionToIdle()
        end, {"-l", "-c", "empty-cmd"})
        task:setInput(text)
        task:start()
      end

      setupAndFinalize()

      assert.equals("Hello world", mock_hs.pasteboard.getContents())
    end)

    it("should store input text on task via setInput", function()
      local capturedTask = nil

      manager.onTextReady = function(text, transitionToIdle)
        local task = mock_hs.task.new("/bin/zsh", function() transitionToIdle() end, {"-l", "-c", "cat"})
        task:setInput(text)
        capturedTask = task
        task:start()
      end

      setupAndFinalize()

      assert.is_not_nil(capturedTask)
      assert.equals("Hello world", capturedTask._input)
    end)
  end)
end)
