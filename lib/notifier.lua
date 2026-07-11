--- Notifier - Centralized UI Boundary for WhisperDictation
--- This is the ONLY module that should call hs.alert.show()
--- All UI feedback must go through this module to maintain the UI boundary pattern

local spoonPath = debug.getinfo(1, "S").source:match("@(.*/)")
local Loggers = dofile(spoonPath .. "loggers.lua")

local logger = Loggers.new("WhisperDictation")

local Notifier = {}
Notifier._logger = logger  -- exposed for testing; not part of the public API

-- Valid categories and severities
local VALID_CATEGORIES = {
  init = true,
  config = true,
  recording = true,
  transcription = true,
}

local VALID_SEVERITIES = {
  debug = true,
  info = true,
  warning = true,
  error = true,
}

-- Icon mapping by category
local CATEGORY_ICONS = {
  init = "✓",
  config = "⚙️",
  recording = "🎙️",
  transcription = "📝",
}

-- Severity-specific icons (override category icons for warning/error)
local SEVERITY_ICONS = {
  warning = "⚠️",
  error = "❌",
}

-- Duration mapping by severity (in seconds)
local SEVERITY_DURATIONS = {
  debug = 0,    -- No alert shown
  info = 3,
  warning = 5,
  error = 10,
}

--- Show a notification with category, severity, and message
--- @param category string One of: init, config, recording, transcription
--- @param severity string One of: debug, info, warning, error
--- @param message string The message to display
function Notifier.show(category, severity, message)
  -- Validate category
  if not VALID_CATEGORIES[category] then
    error(string.format(
      "Invalid category: %s. Must be one of: init, config, recording, transcription",
      tostring(category)
    ))
  end

  -- Validate severity
  if not VALID_SEVERITIES[severity] then
    error(string.format(
      "Invalid severity: %s. Must be one of: debug, info, warning, error",
      tostring(severity)
    ))
  end

  -- Validate message
  if not message or type(message) ~= "string" then
    error("Message must be a non-empty string")
  end

  -- Get icon: severity-specific icon overrides category icon for warning/error
  local icon = SEVERITY_ICONS[severity] or CATEGORY_ICONS[category]

  -- Get duration
  local duration = SEVERITY_DURATIONS[severity]

  -- Format full message
  local fullMessage = string.format("%s %s", icon, message)

  -- Log at the level that matches the notifier severity so the runtime log
  -- level (see lib/loggers.lua + wd:setDebug) actually filters correctly.
  -- Previously everything went through logger.f (info-equivalent), which
  -- meant an "error" alert never reached the console at warning level.
  local formatted = string.format("[%s:%s] %s", category, severity, message)
  local sink = logger and ({
    debug = logger.d,
    info = logger.i,
    warning = logger.w,
    error = logger.e,
  })[severity]
  if sink then
    sink(formatted)
  else
    print(formatted)
  end

  -- Show alert for non-debug severities
  if severity ~= "debug" and duration > 0 then
    if hs and hs.alert then
      hs.alert.show(fullMessage, duration)
    else
      -- Fallback for testing without Hammerspoon
      print(string.format("ALERT [%ds]: %s", duration, fullMessage))
    end
  end
end

--- Get valid categories (for testing)
--- @return table List of valid category names
function Notifier.getValidCategories()
  local categories = {}
  for category, _ in pairs(VALID_CATEGORIES) do
    table.insert(categories, category)
  end
  table.sort(categories)
  return categories
end

--- Get valid severities (for testing)
--- @return table List of valid severity names
function Notifier.getValidSeverities()
  local severities = {}
  for severity, _ in pairs(VALID_SEVERITIES) do
    table.insert(severities, severity)
  end
  table.sort(severities)
  return severities
end

--- Get icon for a category/severity combination (for testing)
--- @param category string The category
--- @param severity string The severity
--- @return string The icon that would be shown
function Notifier.getIcon(category, severity)
  return SEVERITY_ICONS[severity] or CATEGORY_ICONS[category]
end

--- Get duration for a severity (for testing)
--- @param severity string The severity
--- @return number Duration in seconds
function Notifier.getDuration(severity)
  return SEVERITY_DURATIONS[severity]
end

return Notifier
