--- Centralized Error and Alert Handler
--- Provides a single place for showing alerts and handling errors

local ErrorHandler = {}

--- Show an error alert and emit error event
--- @param message (string): Error message to display
--- @param eventBus (EventBus?): Optional EventBus to emit error event
--- @param duration (number?): Alert duration in seconds (default: 10)
function ErrorHandler.showError(message, eventBus, duration)
  duration = duration or 10.0

  -- Always log to console
  print("[ERROR] " .. tostring(message))

  -- Show alert if available
  if _G.hs and _G.hs.alert then
    _G.hs.alert.show("❌ " .. tostring(message), duration)
  end

  -- Emit event if eventBus provided
  if eventBus and eventBus.emit then
    eventBus:emit("recording:error", { error = tostring(message) })
  end
end

--- Show a warning alert
--- @param message (string): Warning message to display
--- @param duration (number?): Alert duration in seconds (default: 5)
function ErrorHandler.showWarning(message, duration)
  duration = duration or 5.0

  -- Log to console
  print("[WARNING] " .. tostring(message))

  -- Show alert if available
  if _G.hs and _G.hs.alert then
    _G.hs.alert.show("⚠️  " .. tostring(message), duration)
  end
end

--- Show an info alert
--- @param message (string): Info message to display
--- @param duration (number?): Alert duration in seconds (default: 3)
function ErrorHandler.showInfo(message, duration)
  duration = duration or 3.0

  -- Log to console
  print("[INFO] " .. tostring(message))

  -- Show alert if available
  if _G.hs and _G.hs.alert then
    _G.hs.alert.show("ℹ️  " .. tostring(message), duration)
  end
end

--- Handle server crash/error
--- @param exitCode (number): Server exit code
--- @param stderr (string?): Server stderr output
--- @param eventBus (EventBus?): Optional EventBus
function ErrorHandler.handleServerCrash(exitCode, stderr, eventBus)
  local errorMsg = string.format("Python server crashed (exit %d)", exitCode)

  if stderr and #stderr > 0 then
    print("[ERROR] Server stderr: " .. stderr)
    errorMsg = errorMsg .. ":\n" .. stderr:sub(1, 200)
  end

  ErrorHandler.showError(errorMsg, eventBus, 15.0)
end

--- Handle invalid server message
--- @param data (string): The invalid message data
--- @param eventBus (EventBus?): Optional EventBus
function ErrorHandler.handleInvalidMessage(data, eventBus)
  local errorMsg = "Invalid server message: " .. tostring(data):sub(1, 100)
  ErrorHandler.showError(errorMsg, eventBus)
end

--- Handle unknown event type
--- @param eventType (string): The unknown event type
--- @param eventBus (EventBus?): Optional EventBus
function ErrorHandler.handleUnknownEvent(eventType, eventBus)
  local errorMsg = string.format("Unknown server event type: %s", tostring(eventType))
  ErrorHandler.showError(errorMsg, eventBus)
end

return ErrorHandler
