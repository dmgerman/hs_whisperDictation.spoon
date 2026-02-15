--- EventBus - Pub/Sub event system for component communication
-- Allows components to communicate without tight coupling

local EventBus = {}
EventBus.__index = EventBus

--- Valid event names (add new events here)
EventBus.VALID_EVENTS = {
  -- Recording events
  "recording:started",
  "recording:stopped",
  "recording:error",

  -- Audio events
  "audio:chunk_ready",
  "audio:chunk_error",

  -- Streaming backend events
  "streaming:server_started",
  "streaming:server_stopped",
  "streaming:server_ready",
  "streaming:silence_warning",
  "streaming:complete_file",

  -- Transcription events
  "transcription:started",
  "transcription:completed",  -- NOTE: "completed" not "complete"!
  "transcription:error",
  "transcription:all_complete",
}

--- Create a new EventBus instance
-- @param strict (boolean): If true, warn on invalid event names (default: true)
-- @return (EventBus): New event bus
function EventBus.new(strict)
  local self = setmetatable({}, EventBus)
  self.listeners = {}  -- {eventName => {listener1, listener2, ...}}
  self.strict = (strict == nil) and true or strict
  self.knownEvents = {}

  -- Build lookup table for fast validation
  for _, eventName in ipairs(EventBus.VALID_EVENTS) do
    self.knownEvents[eventName] = true
  end

  return self
end

--- Validate event name
-- @param eventName (string): Event name to validate
-- @return (boolean): true if valid
function EventBus:_validateEventName(eventName)
  if not self.strict then
    return true
  end

  if not self.knownEvents[eventName] then
    local msg = string.format(
      "⚠️  INVALID EVENT NAME: '%s' is not in EventBus.VALID_EVENTS!\n" ..
      "This is likely a bug. Valid events: %s",
      eventName,
      table.concat(EventBus.VALID_EVENTS, ", ")
    )

    if _G.hs and _G.hs.alert then
      _G.hs.alert.show("❌ Invalid event: " .. eventName, 10.0)
    end

    if _G.print then
      print(msg)
    end

    return false
  end

  return true
end

--- Register a listener for an event
-- @param eventName (string): Name of the event to listen for
-- @param listener (function): Callback function to call when event is emitted
-- @return (function): Unsubscribe function - call to remove this listener
function EventBus:on(eventName, listener)
  -- Validate event name
  self:_validateEventName(eventName)

  if not self.listeners[eventName] then
    self.listeners[eventName] = {}
  end

  table.insert(self.listeners[eventName], listener)

  -- Return unsubscribe function
  local self_ref = self
  local listener_ref = listener
  return function()
    self_ref:off(eventName, listener_ref)
  end
end

--- Unregister listener(s) for an event
-- @param eventName (string): Event name
-- @param listener (function|nil): Specific listener to remove, or nil to remove all
function EventBus:off(eventName, listener)
  if not self.listeners[eventName] then
    return  -- No listeners for this event
  end

  if listener then
    -- Remove specific listener
    for i = #self.listeners[eventName], 1, -1 do
      if self.listeners[eventName][i] == listener then
        table.remove(self.listeners[eventName], i)
        -- Don't break - remove all instances of this listener
      end
    end
  else
    -- Remove all listeners for this event
    self.listeners[eventName] = nil
  end
end

--- Remove all listeners for all events
function EventBus:offAll()
  self.listeners = {}
end

--- Emit an event to all registered listeners
-- @param eventName (string): Name of event to emit
-- @param data (any): Data to pass to listeners (optional)
function EventBus:emit(eventName, data)
  -- Validate event name
  self:_validateEventName(eventName)

  if not self.listeners[eventName] then
    return  -- No listeners registered for this event
  end

  -- Create a copy of listeners array in case listeners modify it during iteration
  local listeners = {}
  for i, listener in ipairs(self.listeners[eventName]) do
    listeners[i] = listener
  end

  -- Call each listener
  for _, listener in ipairs(listeners) do
    -- Wrap in pcall to handle errors gracefully
    local ok, err = pcall(listener, data)
    if not ok then
      -- Log error but continue to next listener
      if _G.print then
        print(string.format("[EventBus] Error in listener for '%s': %s", eventName, tostring(err)))
      end
    end
  end
end

return EventBus
