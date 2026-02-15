--- Promise Unit Tests

describe("Promise", function()
  local Promise
  local promise

  before_each(function()
    Promise = require("lib.promise")
  end)

  describe("initialization", function()
    it("creates a promise in pending state", function()
      promise = Promise.new(function(resolve, reject) end)

      assert.is_not_nil(promise)
      assert.equals("pending", promise.state)
    end)

    it("executes executor function immediately", function()
      local executed = false

      promise = Promise.new(function(resolve, reject)
        executed = true
      end)

      assert.is_true(executed)
    end)
  end)

  describe("resolve()", function()
    it("transitions to fulfilled state", function()
      promise = Promise.new(function(resolve, reject)
        resolve("success")
      end)

      assert.equals("fulfilled", promise.state)
      assert.equals("success", promise.value)
    end)

    it("calls onFulfilled handler", function()
      local result = nil

      promise = Promise.new(function(resolve, reject)
        resolve("success")
      end)

      promise:andThen(function(value)
        result = value
      end)

      assert.equals("success", result)
    end)

    it("calls onFulfilled for late subscribers", function()
      local result = nil

      promise = Promise.new(function(resolve, reject)
        resolve("success")
      end)

      -- Subscribe after resolution
      promise:andThen(function(value)
        result = value
      end)

      assert.equals("success", result)
    end)

    it("ignores subsequent resolve calls", function()
      local resolveCalls = 0

      promise = Promise.new(function(resolve, reject)
        resolve("first")
        resolve("second")
      end)

      promise:andThen(function(value)
        resolveCalls = resolveCalls + 1
      end)

      assert.equals(1, resolveCalls)
      assert.equals("first", promise.value)
    end)
  end)

  describe("reject()", function()
    it("transitions to rejected state", function()
      promise = Promise.new(function(resolve, reject)
        reject("error")
      end)

      assert.equals("rejected", promise.state)
      assert.equals("error", promise.value)
    end)

    it("calls onRejected handler", function()
      local error = nil

      promise = Promise.new(function(resolve, reject)
        reject("failure")
      end)

      promise:catch(function(reason)
        error = reason
      end)

      assert.equals("failure", error)
    end)

    it("ignores subsequent reject calls", function()
      local rejectCalls = 0

      promise = Promise.new(function(resolve, reject)
        reject("first")
        reject("second")
      end)

      promise:catch(function(reason)
        rejectCalls = rejectCalls + 1
      end)

      assert.equals(1, rejectCalls)
      assert.equals("first", promise.value)
    end)
  end)

  describe("andThen()", function()
    it("registers onFulfilled handler", function()
      local called = false

      promise = Promise.new(function(resolve, reject)
        resolve("value")
      end)

      promise:andThen(function()
        called = true
      end)

      assert.is_true(called)
    end)

    it("registers onRejected handler", function()
      local called = false

      promise = Promise.new(function(resolve, reject)
        reject("error")
      end)

      promise:andThen(nil, function()
        called = true
      end)

      assert.is_true(called)
    end)

    it("supports chaining", function()
      local result = nil

      promise = Promise.new(function(resolve, reject)
        resolve(1)
      end)

      promise:andThen(function(value)
        return value + 1
      end):andThen(function(value)
        return value * 2
      end):andThen(function(value)
        result = value
      end)

      assert.equals(4, result)  -- (1 + 1) * 2 = 4
    end)
  end)

  describe("catch()", function()
    it("is shorthand for andThen(nil, onRejected)", function()
      local error = nil

      promise = Promise.new(function(resolve, reject)
        reject("failure")
      end)

      promise:catch(function(reason)
        error = reason
      end)

      assert.equals("failure", error)
    end)

    it("does not call handler on success", function()
      local called = false

      promise = Promise.new(function(resolve, reject)
        resolve("success")
      end)

      promise:catch(function()
        called = true
      end)

      assert.is_false(called)
    end)
  end)

  describe("static methods", function()
    describe("Promise.resolve()", function()
      it("creates a resolved promise", function()
        promise = Promise.resolve("instant success")

        assert.equals("fulfilled", promise.state)
        assert.equals("instant success", promise.value)
      end)
    end)

    describe("Promise.reject()", function()
      it("creates a rejected promise", function()
        promise = Promise.reject("instant failure")

        assert.equals("rejected", promise.state)
        assert.equals("instant failure", promise.value)
      end)
    end)

    describe("Promise.all()", function()
      it("resolves when all promises resolve", function()
        local p1 = Promise.resolve(1)
        local p2 = Promise.resolve(2)
        local p3 = Promise.resolve(3)

        local result = nil
        Promise.all({p1, p2, p3}):andThen(function(values)
          result = values
        end)

        assert.same({1, 2, 3}, result)
      end)

      it("rejects if any promise rejects", function()
        local p1 = Promise.resolve(1)
        local p2 = Promise.reject("error")
        local p3 = Promise.resolve(3)

        local error = nil
        Promise.all({p1, p2, p3}):catch(function(reason)
          error = reason
        end)

        assert.equals("error", error)
      end)
    end)
  end)

  describe("edge cases", function()
    it("handles executor throwing error", function()
      local error = nil

      promise = Promise.new(function(resolve, reject)
        error("Executor throws")
      end)

      promise:catch(function(reason)
        error = reason
      end)

      assert.is_not_nil(error)
    end)

    it("handles handler throwing error", function()
      local error = nil

      promise = Promise.new(function(resolve, reject)
        resolve("value")
      end)

      promise:andThen(function()
        error("Handler throws")
      end):catch(function(reason)
        error = reason
      end)

      assert.is_not_nil(error)
    end)

    it("handles multiple andThen calls", function()
      local count = 0

      promise = Promise.new(function(resolve, reject)
        resolve("value")
      end)

      promise:andThen(function() count = count + 1 end)
      promise:andThen(function() count = count + 1 end)
      promise:andThen(function() count = count + 1 end)

      assert.equals(3, count)
    end)
  end)
end)
