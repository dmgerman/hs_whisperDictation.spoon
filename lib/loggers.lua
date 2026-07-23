--- Loggers - Central registry for hs.logger instances used by the spoon.
---
--- Modules obtain their logger via Loggers.new(name) instead of
--- hs.logger.new(name, level). The registry keeps references so a later
--- Loggers.setLevel(level) call retroactively updates every logger created
--- through it. This lets the spoon toggle diagnostics at runtime without a
--- reload — see wd:setDebug(bool) in init.lua.
---
--- Callers throughout the spoon use dofile() (paths in module code are
--- resolved via debug.getinfo, not package.path). dofile() re-executes the
--- file on every call, which would give each caller its own fresh registry
--- and defeat the whole point of the module. To keep a single shared
--- registry across all dofile() calls we self-cache in package.loaded on
--- first execution and return the cached table on subsequent runs.
---
--- @module Loggers

local CACHE_KEY = "_whisperDictation.Loggers"
if package.loaded[CACHE_KEY] then
  return package.loaded[CACHE_KEY]
end

local Loggers = {}

Loggers._registry = {}
Loggers._level = "warning"

--- Create (or return cached) hs.logger for a module.
---
--- If Hammerspoon is not present (unit tests without a live hs global) a
--- minimal stub with the same call surface is returned so modules don't need
--- to guard every log call.
---
--- @param name string Module name shown in log lines
--- @return table hs.logger instance (or stub)
function Loggers.new(name)
  local log
  if hs and hs.logger then
    log = hs.logger.new(name, Loggers._level)
  else
    -- Test stub: silent no-op logger with the same method names
    log = {
      setLogLevel = function() end,
      i = function() end, w = function() end, e = function() end,
      d = function() end, v = function() end, f = function() end,
    }
  end
  table.insert(Loggers._registry, log)
  return log
end

--- Set the log level for every logger created through the registry.
---
--- @param level string hs.logger level: "verbose", "debug", "info",
---   "warning", "error", or "nothing".
function Loggers.setLevel(level)
  Loggers._level = level
  for _, log in ipairs(Loggers._registry) do
    -- hs.logger methods use dot syntax (bare functions), not colon; calling
    -- log:setLogLevel(level) would pass the logger table as the level
    -- argument and trigger "loglevel must be a string or a number".
    if log.setLogLevel then
      log.setLogLevel(level)
    end
  end
end

--- Current registry level (last value passed to setLevel).
---
--- @return string level
function Loggers.getLevel()
  return Loggers._level
end

package.loaded[CACHE_KEY] = Loggers
return Loggers
