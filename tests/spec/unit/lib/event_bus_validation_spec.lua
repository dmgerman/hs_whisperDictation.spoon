--- EventBus Event Name Validation Tests

describe("EventBus Event Name Validation", function()
  local EventBus
  local bus

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"
    EventBus = require("lib.event_bus")
    bus = EventBus.new(true)  -- strict mode enabled
  end)

  describe("Valid event names", function()
    it("allows valid recording events", function()
      local called = false
      bus:on("recording:started", function() called = true end)
      bus:emit("recording:started", {})
      assert.is_true(called)
    end)

    it("allows valid transcription events", function()
      local called = false
      bus:on("transcription:completed", function() called = true end)
      bus:emit("transcription:completed", {})
      assert.is_true(called)
    end)

    it("allows valid audio events", function()
      local called = false
      bus:on("audio:chunk_ready", function() called = true end)
      bus:emit("audio:chunk_ready", {})
      assert.is_true(called)
    end)

    it("accepts all events in VALID_EVENTS list", function()
      for _, eventName in ipairs(EventBus.VALID_EVENTS) do
        local called = false
        bus:on(eventName, function() called = true end)
        bus:emit(eventName, {})
        assert.is_true(called, "Event should work: " .. eventName)
      end
    end)
  end)

  describe("Invalid event names", function()
    it("warns on invalid event in on()", function()
      -- Capture print output
      local warnings = {}
      local old_print = _G.print
      _G.print = function(msg)
        table.insert(warnings, msg)
      end

      bus:on("invalid:event", function() end)

      _G.print = old_print

      assert.is_true(#warnings > 0, "Should have printed a warning")
      assert.is_not_nil(warnings[1]:match("INVALID EVENT NAME"), "Warning should mention invalid event")
    end)

    it("warns on invalid event in emit()", function()
      local warnings = {}
      local old_print = _G.print
      _G.print = function(msg)
        table.insert(warnings, msg)
      end

      bus:emit("another:invalid", {})

      _G.print = old_print

      assert.is_true(#warnings > 0, "Should have printed a warning")
    end)

    it("catches common typo: transcription:complete instead of completed", function()
      local warnings = {}
      local old_print = _G.print
      _G.print = function(msg)
        table.insert(warnings, msg)
      end

      -- This was the actual bug!
      bus:on("transcription:complete", function() end)  -- WRONG
      bus:emit("transcription:complete", {})             -- WRONG

      _G.print = old_print

      assert.is_true(#warnings >= 2, "Should warn on both on() and emit()")
      assert.is_not_nil(warnings[1]:match("transcription:complete"), "Should mention the typo")
    end)

    it("lists valid events in warning message", function()
      local warnings = {}
      local old_print = _G.print
      _G.print = function(msg)
        table.insert(warnings, msg)
      end

      bus:on("typo:event", function() end)

      _G.print = old_print

      local warning = warnings[1] or ""
      assert.is_not_nil(warning:match("Valid events:"), "Should list valid events")
      assert.is_not_nil(warning:match("recording:started"), "Should mention valid event examples")
    end)
  end)

  describe("Non-strict mode", function()
    it("allows any event name when strict = false", function()
      local bus_relaxed = EventBus.new(false)

      local called = false
      bus_relaxed:on("any:event:name", function() called = true end)
      bus_relaxed:emit("any:event:name", {})

      assert.is_true(called, "Non-strict mode should allow any event")
    end)
  end)

  describe("Event name best practices", function()
    it("all valid events follow namespace:action pattern", function()
      for _, eventName in ipairs(EventBus.VALID_EVENTS) do
        assert.is_not_nil(eventName:match("^[%w_]+:[%w_]+$"),
          string.format("Event '%s' should follow 'namespace:action' pattern", eventName))
      end
    end)

    it("transcription events use 'completed' not 'complete'", function()
      local has_completed = false
      local has_complete = false

      for _, eventName in ipairs(EventBus.VALID_EVENTS) do
        if eventName:match("transcription") then
          if eventName:match("completed") then
            has_completed = true
          end
          if eventName:match(":complete$") then  -- ends with :complete (not :completed)
            has_complete = true
          end
        end
      end

      assert.is_true(has_completed, "Should have 'transcription:completed' event")
      assert.is_false(has_complete, "Should NOT have 'transcription:complete' event")
    end)
  end)

  describe("Runtime event discovery", function()
    it("tracks which events have listeners", function()
      bus:on("recording:started", function() end)
      bus:on("transcription:completed", function() end)

      local hasListeners = {}
      for eventName, listeners in pairs(bus.listeners) do
        if #listeners > 0 then
          hasListeners[eventName] = true
        end
      end

      assert.is_true(hasListeners["recording:started"])
      assert.is_true(hasListeners["transcription:completed"])
    end)
  end)
end)
