-- Test suite for Notifier module

-- Load test infrastructure
local mock_hs = require("tests.helpers.mock_hs")

-- Mock Hammerspoon before loading Notifier
_G.hs = mock_hs

-- Load the module under test
local Notifier = require("lib.notifier")

describe("Notifier", function()
  local alertSpy
  local logSpy

  before_each(function()
    -- Reset mocks
    mock_hs._resetAll()

    -- Create spies
    alertSpy = spy.new(function() end)
    logSpy = spy.new(function() end)

    mock_hs.alert.show = alertSpy

    -- The Notifier module captures its logger at load time via the shared
    -- Loggers registry, so we spy on the exposed instance rather than
    -- replacing hs.logger.new (which no longer runs at Notifier.show time).
    -- Route every severity method to the same spy so any of debug/info/
    -- warning/error triggers "was_called".
    Notifier._logger.d = logSpy
    Notifier._logger.i = logSpy
    Notifier._logger.w = logSpy
    Notifier._logger.e = logSpy
    Notifier._logger.f = logSpy
  end)

  describe("Category validation", function()
    it("should accept 'init' category", function()
      assert.has_no.errors(function()
        Notifier.show("init", "info", "Test message")
      end)
    end)

    it("should accept 'config' category", function()
      assert.has_no.errors(function()
        Notifier.show("config", "info", "Test message")
      end)
    end)

    it("should accept 'recording' category", function()
      assert.has_no.errors(function()
        Notifier.show("recording", "info", "Test message")
      end)
    end)

    it("should accept 'transcription' category", function()
      assert.has_no.errors(function()
        Notifier.show("transcription", "info", "Test message")
      end)
    end)

    it("should reject invalid category", function()
      assert.has_error(function()
        Notifier.show("invalid", "info", "Test message")
      end)
      local status, err = pcall(function()
        Notifier.show("invalid", "info", "Test message")
      end)
      assert.is_false(status)
      assert.matches("Invalid category", err)
    end)

    it("should reject nil category", function()
      assert.has_error(function()
        Notifier.show(nil, "info", "Test message")
      end)
      local status, err = pcall(function()
        Notifier.show(nil, "info", "Test message")
      end)
      assert.is_false(status)
      assert.matches("Invalid category", err)
    end)

    it("should reject empty string category", function()
      assert.has_error(function()
        Notifier.show("", "info", "Test message")
      end)
      local status, err = pcall(function()
        Notifier.show("", "info", "Test message")
      end)
      assert.is_false(status)
      assert.matches("Invalid category", err)
    end)
  end)

  describe("Severity validation", function()
    it("should accept 'debug' severity", function()
      assert.has_no.errors(function()
        Notifier.show("init", "debug", "Test message")
      end)
    end)

    it("should accept 'info' severity", function()
      assert.has_no.errors(function()
        Notifier.show("init", "info", "Test message")
      end)
    end)

    it("should accept 'warning' severity", function()
      assert.has_no.errors(function()
        Notifier.show("init", "warning", "Test message")
      end)
    end)

    it("should accept 'error' severity", function()
      assert.has_no.errors(function()
        Notifier.show("init", "error", "Test message")
      end)
    end)

    it("should reject invalid severity", function()
      assert.has_error(function()
        Notifier.show("init", "invalid", "Test message")
      end)
      local status, err = pcall(function()
        Notifier.show("init", "invalid", "Test message")
      end)
      assert.is_false(status)
      assert.matches("Invalid severity", err)
    end)

    it("should reject nil severity", function()
      assert.has_error(function()
        Notifier.show("init", nil, "Test message")
      end)
      local status, err = pcall(function()
        Notifier.show("init", nil, "Test message")
      end)
      assert.is_false(status)
      assert.matches("Invalid severity", err)
    end)

    it("should reject empty string severity", function()
      assert.has_error(function()
        Notifier.show("init", "", "Test message")
      end)
      local status, err = pcall(function()
        Notifier.show("init", "", "Test message")
      end)
      assert.is_false(status)
      assert.matches("Invalid severity", err)
    end)
  end)

  describe("Message validation", function()
    it("should accept valid message", function()
      assert.has_no.errors(function()
        Notifier.show("init", "info", "Valid message")
      end)
    end)

    it("should reject nil message", function()
      assert.has_error(function()
        Notifier.show("init", "info", nil)
      end)
      local status, err = pcall(function()
        Notifier.show("init", "info", nil)
      end)
      assert.is_false(status)
      assert.matches("Message must be", err)
    end)

    it("should reject non-string message", function()
      assert.has_error(function()
        Notifier.show("init", "info", 123)
      end)
      local status, err = pcall(function()
        Notifier.show("init", "info", 123)
      end)
      assert.is_false(status)
      assert.matches("Message must be", err)
    end)
  end)

  describe("Alert display behavior", function()
    it("should show alert for 'info' severity", function()
      Notifier.show("init", "info", "Test")
      assert.spy(alertSpy).was_called()
    end)

    it("should show alert for 'warning' severity", function()
      Notifier.show("init", "warning", "Test")
      assert.spy(alertSpy).was_called()
    end)

    it("should show alert for 'error' severity", function()
      Notifier.show("init", "error", "Test")
      assert.spy(alertSpy).was_called()
    end)

    it("should NOT show alert for 'debug' severity", function()
      Notifier.show("init", "debug", "Test")
      assert.spy(alertSpy).was_not_called()
    end)

    it("should still log 'debug' messages even though no alert shown", function()
      Notifier.show("init", "debug", "Test")
      assert.spy(logSpy).was_called()
    end)
  end)

  describe("Icon mapping", function()
    it("should use ✓ icon for 'init' category", function()
      local icon = Notifier.getIcon("init", "info")
      assert.equals("✓", icon)
    end)

    it("should use ⚙️ icon for 'config' category", function()
      local icon = Notifier.getIcon("config", "info")
      assert.equals("⚙️", icon)
    end)

    it("should use 🎙️ icon for 'recording' category", function()
      local icon = Notifier.getIcon("recording", "info")
      assert.equals("🎙️", icon)
    end)

    it("should use 📝 icon for 'transcription' category", function()
      local icon = Notifier.getIcon("transcription", "info")
      assert.equals("📝", icon)
    end)

    it("should use ⚠️ icon for 'warning' severity (overrides category)", function()
      local icon = Notifier.getIcon("init", "warning")
      assert.equals("⚠️", icon)
    end)

    it("should use ❌ icon for 'error' severity (overrides category)", function()
      local icon = Notifier.getIcon("init", "error")
      assert.equals("❌", icon)
    end)

    it("should include icon in alert message", function()
      Notifier.show("recording", "info", "Test")
      assert.spy(alertSpy).was_called_with(match.matches("🎙️ Test"), match._)
    end)
  end)

  describe("Duration mapping", function()
    it("should use 0 second duration for 'debug'", function()
      local duration = Notifier.getDuration("debug")
      assert.equals(0, duration)
    end)

    it("should use 3 second duration for 'info'", function()
      local duration = Notifier.getDuration("info")
      assert.equals(3, duration)
    end)

    it("should use 5 second duration for 'warning'", function()
      local duration = Notifier.getDuration("warning")
      assert.equals(5, duration)
    end)

    it("should use 10 second duration for 'error'", function()
      local duration = Notifier.getDuration("error")
      assert.equals(10, duration)
    end)

    it("should pass correct duration to hs.alert.show for 'info'", function()
      Notifier.show("init", "info", "Test")
      assert.spy(alertSpy).was_called_with(match._, 3)
    end)

    it("should pass correct duration to hs.alert.show for 'warning'", function()
      Notifier.show("init", "warning", "Test")
      assert.spy(alertSpy).was_called_with(match._, 5)
    end)

    it("should pass correct duration to hs.alert.show for 'error'", function()
      Notifier.show("init", "error", "Test")
      assert.spy(alertSpy).was_called_with(match._, 10)
    end)
  end)

  describe("Helper functions", function()
    it("should return all valid categories", function()
      local categories = Notifier.getValidCategories()
      assert.equals(4, #categories)
      local categoriesStr = table.concat(categories, ",")
      assert.is_not_nil(categoriesStr:find("init"))
      assert.is_not_nil(categoriesStr:find("config"))
      assert.is_not_nil(categoriesStr:find("recording"))
      assert.is_not_nil(categoriesStr:find("transcription"))
    end)

    it("should return all valid severities", function()
      local severities = Notifier.getValidSeverities()
      assert.equals(4, #severities)
      local severitiesStr = table.concat(severities, ",")
      assert.is_not_nil(severitiesStr:find("debug"))
      assert.is_not_nil(severitiesStr:find("info"))
      assert.is_not_nil(severitiesStr:find("warning"))
      assert.is_not_nil(severitiesStr:find("error"))
    end)
  end)

  describe("Complete message formatting", function()
    it("should format message with category icon and text", function()
      Notifier.show("recording", "info", "Started")
      assert.spy(alertSpy).was_called_with("🎙️ Started", 3)
    end)

    it("should format message with severity icon overriding category", function()
      Notifier.show("recording", "error", "Failed")
      assert.spy(alertSpy).was_called_with("❌ Failed", 10)
    end)
  end)
end)
