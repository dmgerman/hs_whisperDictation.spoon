--- Filter - Post-transcription text filtering via shell command or Lua function
---
--- Pipes text through an external command (stdin → stdout), or through a
--- Lua function that takes the text and returns the transformed text.
--- Falls back to original text on any error.
---
--- @module Filter

local Filter = {}

--- Apply a Lua-function filter synchronously.
--- Wraps the call in pcall so a raising fn falls back to the original text.
local function applyFn(text, filter, logger, callback)
  local ok, result = pcall(filter.fn, text)
  if ok and type(result) == "string" and #result > 0 then
    if logger then
      logger:info("Filter applied successfully")
    end
    callback(result)
    return
  end

  local reason
  if not ok then
    reason = "error: " .. tostring(result)
  elseif type(result) ~= "string" then
    reason = "returned non-string (" .. type(result) .. ")"
  else
    reason = "returned empty string"
  end

  local msg = "Filter '" .. filter.name .. "' failed (" .. reason .. ")"
  if logger then
    logger:warn(msg .. " — using unfiltered text")
  end
  hs.alert.show("⚠️ " .. msg .. "\nUsing unfiltered text", 5)
  callback(text)
end

--- Apply a filter to text via async shell command or Lua function.
--- If no filter is active, calls callback immediately with unmodified text.
--- A filter entry may specify `fn` (Lua function taking text, returning string)
--- or `cmd` (shell command reading stdin, writing stdout). If both are present,
--- `fn` takes precedence.
---
--- @param text string The text to filter
--- @param config table Filter configuration {activeFilter, whisperFilters}
--- @param logger table Logger with info/warn methods (optional)
--- @param callback function Called with filtered text: callback(filteredText)
function Filter.apply(text, config, logger, callback)
  if not config or not config.activeFilter or not config.whisperFilters or #config.whisperFilters == 0 then
    callback(text)
    return
  end

  local filter = config.whisperFilters[config.activeFilter]
  if not filter or (not filter.fn and not filter.cmd) then
    callback(text)
    return
  end

  if logger then
    logger:info("Applying filter: " .. filter.name)
  end

  if type(filter.fn) == "function" then
    applyFn(text, filter, logger, callback)
    return
  end

  local task = hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
    if exitCode == 0 and stdOut and #stdOut > 0 then
      -- Trim trailing newline added by most commands
      local filtered = stdOut:gsub("\n$", "")
      if logger then
        logger:info("Filter applied successfully")
      end
      callback(filtered)
    else
      local msg = "Filter '" .. filter.name .. "' failed (exit " .. exitCode .. "): " .. tostring(stdErr)
      if logger then
        logger:warn(msg .. " — using unfiltered text")
      end
      hs.alert.show("⚠️ " .. msg .. "\nUsing unfiltered text", 5)
      callback(text)
    end
  end, {"-l", "-c", filter.cmd})

  if not task then
    if logger then
      logger:warn("Failed to create filter task — using unfiltered text")
    end
    callback(text)
    return
  end

  task:setInput(text)
  task:start()
end

return Filter
