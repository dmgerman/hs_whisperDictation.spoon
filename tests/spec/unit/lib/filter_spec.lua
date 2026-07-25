--- Tests for Filter module - Post-transcription text filtering
---
--- Covers: passthrough cases, successful filtering, and all failure modes

local mock_hs = require("tests.helpers.mock_hs")
_G.hs = mock_hs

local Filter = dofile("lib/filter.lua")

-- Simple logger mock
local function makeLogger()
  local log = { infos = {}, warns = {} }
  log.info = function(self, msg) table.insert(self.infos, msg) end
  log.warn = function(self, msg) table.insert(self.warns, msg) end
  return log
end

describe("Filter", function()
  local logger

  before_each(function()
    mock_hs._resetAll()
    logger = makeLogger()
  end)

  describe("passthrough (no filtering)", function()
    it("passes through when config is nil", function()
      local result = nil
      Filter.apply("hello", nil, logger, function(text) result = text end)
      assert.equals("hello", result)
    end)

    it("passes through when activeFilter is nil", function()
      local result = nil
      local config = { activeFilter = nil, whisperFilters = {{ name = "x", cmd = "cat" }} }
      Filter.apply("hello", config, logger, function(text) result = text end)
      assert.equals("hello", result)
    end)

    it("passes through when whisperFilters is empty", function()
      local result = nil
      local config = { activeFilter = 1, whisperFilters = {} }
      Filter.apply("hello", config, logger, function(text) result = text end)
      assert.equals("hello", result)
    end)

    it("passes through when activeFilter index is out of bounds", function()
      local result = nil
      local config = { activeFilter = 99, whisperFilters = {{ name = "x", cmd = "cat" }} }
      Filter.apply("hello", config, logger, function(text) result = text end)
      assert.equals("hello", result)
    end)

    it("passes through when filter entry has no cmd or fn", function()
      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{ name = "no cmd" }} }
      Filter.apply("hello", config, logger, function(text) result = text end)
      assert.equals("hello", result)
    end)
  end)

  describe("Lua function filter", function()
    it("returns text transformed by fn", function()
      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{
        name = "upper",
        fn = function(text) return text:upper() end,
      }} }
      Filter.apply("hello", config, logger, function(text) result = text end)
      assert.equals("HELLO", result)
    end)

    it("logs info on success", function()
      local config = { activeFilter = 1, whisperFilters = {{
        name = "my fn filter",
        fn = function(text) return text .. "!" end,
      }} }
      Filter.apply("hi", config, logger, function() end)

      assert.is_true(#logger.infos >= 2)
      assert.is_truthy(logger.infos[1]:match("Applying filter: my fn filter"))
      assert.is_truthy(logger.infos[2]:match("Filter applied successfully"))
    end)

    it("prefers fn over cmd when both are present", function()
      -- If cmd were run, the mock would consume _setNextOutput; we set a
      -- distinct value so a wrong path would surface.
      mock_hs.task._setNextOutput(0, "FROM CMD\n", "")

      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{
        name = "both",
        cmd = "tr a-z A-Z",
        fn = function(text) return "FROM FN: " .. text end,
      }} }
      Filter.apply("hello", config, logger, function(text) result = text end)

      assert.equals("FROM FN: hello", result)
    end)

    it("falls back to original text when fn raises", function()
      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{
        name = "boom",
        fn = function(_) error("kaboom") end,
      }} }
      Filter.apply("original", config, logger, function(text) result = text end)

      assert.equals("original", result)
      assert.is_true(#logger.warns > 0)
      local alerts = mock_hs.alert._getAlerts()
      assert.is_true(#alerts > 0)
      assert.is_truthy(alerts[1].message:match("boom"))
    end)

    it("falls back when fn returns non-string", function()
      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{
        name = "wrong-type",
        fn = function(_) return 42 end,
      }} }
      Filter.apply("original", config, logger, function(text) result = text end)

      assert.equals("original", result)
      assert.is_true(#logger.warns > 0)
    end)

    it("falls back when fn returns empty string", function()
      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{
        name = "empty-fn",
        fn = function(_) return "" end,
      }} }
      Filter.apply("original", config, logger, function(text) result = text end)

      assert.equals("original", result)
      assert.is_true(#logger.warns > 0)
    end)
  end)

  describe("successful filtering", function()
    it("returns filtered text from stdout", function()
      mock_hs.task._setNextOutput(0, "FILTERED TEXT\n", "")

      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{ name = "upper", cmd = "tr a-z A-Z" }} }
      Filter.apply("hello", config, logger, function(text) result = text end)

      assert.equals("FILTERED TEXT", result)
    end)

    it("trims trailing newline from output", function()
      mock_hs.task._setNextOutput(0, "output\n", "")

      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{ name = "echo", cmd = "cat" }} }
      Filter.apply("input", config, logger, function(text) result = text end)

      assert.equals("output", result)
    end)

    it("logs info on success", function()
      mock_hs.task._setNextOutput(0, "ok\n", "")

      local config = { activeFilter = 1, whisperFilters = {{ name = "my filter", cmd = "cat" }} }
      Filter.apply("input", config, logger, function() end)

      assert.is_true(#logger.infos >= 2)
      assert.is_truthy(logger.infos[1]:match("Applying filter: my filter"))
      assert.is_truthy(logger.infos[2]:match("Filter applied successfully"))
    end)
  end)

  describe("failure modes", function()
    it("falls back to original text on non-zero exit code", function()
      mock_hs.task._setNextOutput(1, "", "error message")

      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{ name = "failing", cmd = "false" }} }
      Filter.apply("original", config, logger, function(text) result = text end)

      assert.equals("original", result)
    end)

    it("shows alert on non-zero exit code", function()
      mock_hs.task._setNextOutput(1, "", "some error")

      local config = { activeFilter = 1, whisperFilters = {{ name = "failing", cmd = "false" }} }
      Filter.apply("original", config, logger, function() end)

      local alerts = mock_hs.alert._getAlerts()
      assert.is_true(#alerts > 0)
      assert.is_truthy(alerts[1].message:match("failing"))
    end)

    it("falls back to original text on empty stdout", function()
      mock_hs.task._setNextOutput(0, "", "")

      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{ name = "empty", cmd = "true" }} }
      Filter.apply("original", config, logger, function(text) result = text end)

      assert.equals("original", result)
    end)

    it("falls back to original text when task creation fails", function()
      mock_hs.task._failNextCreation = true

      local result = nil
      local config = { activeFilter = 1, whisperFilters = {{ name = "broken", cmd = "cat" }} }
      Filter.apply("original", config, logger, function(text) result = text end)

      assert.equals("original", result)
      assert.is_true(#logger.warns > 0)
    end)

    it("logs warning on failure", function()
      mock_hs.task._setNextOutput(127, "", "/bin/zsh: command not found: badcmd")

      local config = { activeFilter = 1, whisperFilters = {{ name = "bad", cmd = "badcmd" }} }
      Filter.apply("original", config, logger, function() end)

      assert.is_true(#logger.warns > 0)
      assert.is_truthy(logger.warns[1]:match("failed"))
    end)
  end)
end)
