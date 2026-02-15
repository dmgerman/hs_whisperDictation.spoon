--- Promise - Async operation abstraction
-- Simplifies async code by replacing callback hell with chainable promises

local Promise = {}
Promise.__index = Promise

--- Create a new Promise
-- @param executor (function): function(resolve, reject) called immediately
-- @return (Promise): New promise instance
function Promise.new(executor)
  local self = setmetatable({}, Promise)
  self.state = "pending"  -- pending, fulfilled, rejected
  self.value = nil
  self.handlers = {}

  local function resolve(value)
    if self.state ~= "pending" then return end
    self.state = "fulfilled"
    self.value = value
    self:_processHandlers()
  end

  local function reject(reason)
    if self.state ~= "pending" then return end
    self.state = "rejected"
    self.value = reason
    self:_processHandlers()
  end

  -- Execute executor, catching errors
  local ok, err = pcall(executor, resolve, reject)
  if not ok then
    reject(err)
  end

  return self
end

--- Process handlers after resolution
function Promise:_processHandlers()
  for _, handler in ipairs(self.handlers) do
    self:_handle(handler)
  end
  self.handlers = {}
end

--- Handle a single handler
function Promise:_handle(handler)
  if self.state == "pending" then
    table.insert(self.handlers, handler)
    return
  end

  -- Select appropriate callback based on state
  local callback
  if self.state == "fulfilled" then
    callback = handler.onFulfilled
  else
    callback = handler.onRejected
  end

  if not callback then
    -- No handler for this state, pass through value
    if self.state == "fulfilled" then
      if handler.resolve then
        handler.resolve(self.value)
      end
    else
      if handler.reject then
        handler.reject(self.value)
      end
    end
    return
  end

  -- Call handler, catching errors
  local ok, result = pcall(callback, self.value)

  if ok then
    -- Check if result is a Promise - if so, chain to it
    if type(result) == "table" and type(result.andThen) == "function" then
      -- Result is a promise, chain to it
      result:andThen(
        function(value)
          if handler.resolve then
            handler.resolve(value)
          end
        end,
        function(reason)
          if handler.reject then
            handler.reject(reason)
          end
        end
      )
    else
      -- Regular value, resolve with it
      if handler.resolve then
        handler.resolve(result)
      end
    end
  else
    if handler.reject then
      handler.reject(result)
    end
  end
end

--- Register fulfillment and/or rejection handlers
-- @param onFulfilled (function|nil): Called when promise resolves
-- @param onRejected (function|nil): Called when promise rejects
-- @return (Promise): New promise for chaining
function Promise:andThen(onFulfilled, onRejected)
  return Promise.new(function(resolve, reject)
    self:_handle({
      onFulfilled = onFulfilled,
      onRejected = onRejected,
      resolve = resolve,
      reject = reject,
    })
  end)
end

--- Register fulfillment handler (alias for andThen for modern Promise API)
-- @param onFulfilled (function): Called when promise fulfills
-- @return (Promise): New promise for chaining
function Promise:next(onFulfilled)
  return self:andThen(onFulfilled, nil)
end

--- Register rejection handler (shorthand for andThen(nil, onRejected))
-- @param onRejected (function): Called when promise rejects
-- @return (Promise): New promise for chaining
function Promise:catch(onRejected)
  return self:andThen(nil, onRejected)
end

--- Create a pre-resolved promise
-- @param value (any): Value to resolve with
-- @return (Promise): Resolved promise
function Promise.resolve(value)
  return Promise.new(function(resolve, reject)
    resolve(value)
  end)
end

--- Create a pre-rejected promise
-- @param reason (any): Reason to reject with
-- @return (Promise): Rejected promise
function Promise.reject(reason)
  return Promise.new(function(resolve, reject)
    reject(reason)
  end)
end

--- Wait for all promises to resolve
-- @param promises (table): Array of promises
-- @return (Promise): Promise that resolves with array of values, or rejects with first error
function Promise.all(promises)
  return Promise.new(function(resolve, reject)
    if #promises == 0 then
      resolve({})
      return
    end

    local results = {}
    local remaining = #promises

    for i, promise in ipairs(promises) do
      promise:andThen(function(value)
        results[i] = value
        remaining = remaining - 1
        if remaining == 0 then
          resolve(results)
        end
      end, function(reason)
        reject(reason)
      end)
    end
  end)
end

return Promise
