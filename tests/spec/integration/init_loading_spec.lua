--- Integration Test: Load init.lua and verify event handlers work

describe("Init.lua Loading and Event Handlers", function()
  local spoon

  setup(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Mock Hammerspoon APIs
    _G.hs = require("tests.helpers.mock_hs")

    -- Mock spoon global
    _G.spoon = {}
  end)

  before_each(function()
    -- Fresh load of init.lua
    package.loaded["init"] = nil
    spoon = dofile("init.lua")
  end)

  describe("Module loading", function()
    it("init.lua loads without errors", function()
      assert.is_not_nil(spoon)
      assert.is_table(spoon)
    end)

    it("has required methods", function()
      assert.is_function(spoon.start)
      assert.is_function(spoon.stop)
      assert.is_function(spoon.bindHotKeys)
    end)
  end)

  describe("Event handler scope", function()
    it("all event handlers can access helper functions", function()
      -- Start the spoon to set up event handlers
      spoon:start()

      assert.is_not_nil(spoon.eventBus, "EventBus should be initialized")

      -- Fire events and verify no "attempt to call nil" errors
      local errors = {}
      local old_print = _G.print
      _G.print = function(msg)
        if msg:match("attempt to call") or msg:match("nil value") then
          table.insert(errors, msg)
        end
      end

      -- Test transcription:all_complete (this was crashing)
      local ok, err = pcall(function()
        spoon.eventBus:emit("transcription:all_complete", {
          text = "test transcription",
          chunkCount = 1
        })
      end)

      _G.print = old_print

      if not ok then
        print("ERROR firing transcription:all_complete:", err)
      end

      assert.equals(0, #errors, "Should have no scope errors")
      assert.is_true(ok, "Event handler should not crash: " .. tostring(err))
    end)

    it("transcription:completed handler can be called", function()
      spoon:start()

      local ok, err = pcall(function()
        spoon.eventBus:emit("transcription:completed", {
          audioFile = "/tmp/test.wav",
          text = "test",
          lang = "en"
        })
      end)

      assert.is_true(ok, "Handler should not crash: " .. tostring(err))
    end)

    it("recording:stopped handler can be called", function()
      spoon:start()

      local ok, err = pcall(function()
        spoon.eventBus:emit("recording:stopped", {})
      end)

      assert.is_true(ok, "Handler should not crash: " .. tostring(err))
    end)

    it("audio:chunk_ready handler can be called", function()
      spoon:start()

      local ok, err = pcall(function()
        spoon.eventBus:emit("audio:chunk_ready", {
          audioFile = "/tmp/chunk.wav",
          chunkNum = 1,
          lang = "en"
        })
      end)

      assert.is_true(ok, "Handler should not crash: " .. tostring(err))
    end)
  end)

  describe("Function ordering", function()
    it("all functions used in event handlers are defined before use", function()
      -- This test would have caught the getRecentRecordings scope issue
      spoon:start()

      -- Try to fire all events and verify no undefined function errors
      local events_to_test = {
        {name = "recording:started", data = {lang = "en"}},
        {name = "recording:stopped", data = {}},
        {name = "audio:chunk_ready", data = {audioFile = "/tmp/test.wav", chunkNum = 1, lang = "en"}},
        {name = "transcription:started", data = {audioFile = "/tmp/test.wav", lang = "en"}},
        {name = "transcription:completed", data = {audioFile = "/tmp/test.wav", text = "test", lang = "en"}},
        {name = "transcription:error", data = {error = "test error"}},
        {name = "transcription:all_complete", data = {text = "test", chunkCount = 1}},
      }

      for _, event in ipairs(events_to_test) do
        local ok, err = pcall(function()
          spoon.eventBus:emit(event.name, event.data)
        end)

        assert.is_true(ok, string.format(
          "Event '%s' handler crashed: %s",
          event.name,
          tostring(err)
        ))
      end
    end)
  end)

  describe("Runtime errors in handlers", function()
    it("catches and reports handler errors", function()
      spoon:start()

      local errors_logged = {}
      local old_print = _G.print
      _G.print = function(msg)
        if msg:match("Error in listener") then
          table.insert(errors_logged, msg)
        end
      end

      -- Fire event that would trigger getRecentRecordings
      spoon.eventBus:emit("transcription:all_complete", {
        text = "test",
        chunkCount = 1
      })

      _G.print = old_print

      -- With the fix, there should be NO errors
      assert.equals(0, #errors_logged,
        "Should have no handler errors. Got: " .. table.concat(errors_logged, "\n"))
    end)
  end)
end)
