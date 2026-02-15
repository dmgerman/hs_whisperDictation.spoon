--- EventBus Unit Tests

describe("EventBus", function()
  local EventBus
  local bus

  before_each(function()
    -- Load EventBus module
    EventBus = require("lib.event_bus")
    bus = EventBus.new()
  end)

  describe("initialization", function()
    it("creates a new EventBus instance", function()
      assert.is_not_nil(bus)
      assert.is_table(bus)
    end)
  end)

  describe("on() - register listeners", function()
    it("registers a listener for an event", function()
      local called = false

      bus:on("test:event", function()
        called = true
      end)

      bus:emit("test:event")

      assert.is_true(called)
    end)

    it("passes data to listeners", function()
      local receivedData = nil

      bus:on("test:event", function(data)
        receivedData = data
      end)

      bus:emit("test:event", {foo = "bar", num = 42})

      assert.is_not_nil(receivedData)
      assert.equals("bar", receivedData.foo)
      assert.equals(42, receivedData.num)
    end)

    it("supports multiple listeners for same event", function()
      local count = 0

      bus:on("test:event", function() count = count + 1 end)
      bus:on("test:event", function() count = count + 1 end)
      bus:on("test:event", function() count = count + 1 end)

      bus:emit("test:event")

      assert.equals(3, count)
    end)

    it("returns an unsubscribe function", function()
      local unsubscribe = bus:on("test:event", function() end)

      assert.is_function(unsubscribe)
    end)
  end)

  describe("emit() - trigger events", function()
    it("does nothing if no listeners registered", function()
      -- Should not error
      assert.has_no.errors(function()
        bus:emit("nonexistent:event")
      end)
    end)

    it("calls all listeners in order", function()
      local order = {}

      bus:on("test:event", function() table.insert(order, 1) end)
      bus:on("test:event", function() table.insert(order, 2) end)
      bus:on("test:event", function() table.insert(order, 3) end)

      bus:emit("test:event")

      assert.same({1, 2, 3}, order)
    end)

    it("handles listener errors gracefully", function()
      local goodListenerCalled = false

      bus:on("test:event", function()
        error("Listener intentionally throws error")
      end)

      bus:on("test:event", function()
        goodListenerCalled = true
      end)

      -- Should not throw, should continue to next listener
      assert.has_no.errors(function()
        bus:emit("test:event")
      end)

      assert.is_true(goodListenerCalled, "Good listener should still be called")
    end)
  end)

  describe("off() - unregister listeners", function()
    it("unsubscribes using returned function", function()
      local called = false

      local unsubscribe = bus:on("test:event", function()
        called = true
      end)

      unsubscribe()
      bus:emit("test:event")

      assert.is_false(called, "Listener should not be called after unsubscribe")
    end)

    it("unsubscribes specific listener", function()
      local listener1Called = false
      local listener2Called = false

      local listener1 = function() listener1Called = true end
      local listener2 = function() listener2Called = true end

      bus:on("test:event", listener1)
      bus:on("test:event", listener2)

      bus:off("test:event", listener1)
      bus:emit("test:event")

      assert.is_false(listener1Called, "Listener1 should not be called")
      assert.is_true(listener2Called, "Listener2 should still be called")
    end)

    it("removes all listeners when no listener specified", function()
      local count = 0

      bus:on("test:event", function() count = count + 1 end)
      bus:on("test:event", function() count = count + 1 end)

      bus:off("test:event")  -- Remove all
      bus:emit("test:event")

      assert.equals(0, count, "No listeners should be called")
    end)

    it("does nothing for non-existent event", function()
      assert.has_no.errors(function()
        bus:off("nonexistent:event")
      end)
    end)
  end)

  describe("offAll() - clear all listeners", function()
    it("removes all listeners for all events", function()
      local count = 0

      bus:on("event1", function() count = count + 1 end)
      bus:on("event2", function() count = count + 1 end)
      bus:on("event3", function() count = count + 1 end)

      bus:offAll()

      bus:emit("event1")
      bus:emit("event2")
      bus:emit("event3")

      assert.equals(0, count, "No listeners should be called")
    end)
  end)

  describe("edge cases", function()
    it("handles nil data", function()
      local receivedData = "not nil"

      bus:on("test:event", function(data)
        receivedData = data
      end)

      bus:emit("test:event", nil)

      assert.is_nil(receivedData)
    end)

    it("handles emitting during emission", function()
      local innerEmitted = false

      bus:on("outer", function()
        bus:emit("inner")
      end)

      bus:on("inner", function()
        innerEmitted = true
      end)

      bus:emit("outer")

      assert.is_true(innerEmitted, "Inner event should be emitted")
    end)

    it("handles unsubscribing during emission", function()
      local count = 0
      local unsubscribe

      unsubscribe = bus:on("test:event", function()
        count = count + 1
        unsubscribe()  -- Unsubscribe self during callback
      end)

      bus:emit("test:event")
      bus:emit("test:event")  -- Should not call listener again

      assert.equals(1, count, "Listener should only be called once")
    end)
  end)
end)
