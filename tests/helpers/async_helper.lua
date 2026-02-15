--- Async Test Helper
-- Provides utilities for testing async Promise-based code

local AsyncHelper = {}

--- Wait for a promise to resolve and run assertions
-- @param promise (Promise): The promise to wait for
-- @param assertions (function): Function containing assertions to run after resolution
-- @return (boolean): true if assertions passed
function AsyncHelper.waitFor(promise, assertions)
  local resolved = false
  local rejected = false
  local result = nil
  local error = nil

  promise
    :next(function(value)
      resolved = true
      result = value
    end)
    :catch(function(err)
      rejected = true
      error = err
    end)

  -- In synchronous test environment, promise should resolve immediately
  if resolved then
    if assertions then
      assertions(result)
    end
    return true
  elseif rejected then
    error("Promise rejected: " .. tostring(error))
  else
    error("Promise did not resolve synchronously")
  end
end

--- Create a resolved promise for testing
-- @param value (any): Value to resolve with
-- @return (Promise): Resolved promise
function AsyncHelper.resolved(value)
  local Promise = require("lib.promise")
  return Promise.resolve(value)
end

--- Create a rejected promise for testing
-- @param reason (any): Reason to reject with
-- @return (Promise): Rejected promise
function AsyncHelper.rejected(reason)
  local Promise = require("lib.promise")
  return Promise.reject(reason)
end

return AsyncHelper
