--- Filter - Post-transcription text filtering via shell commands
---
--- Pipes text through an external command (stdin → stdout).
--- Falls back to original text on any error.
---
--- @module Filter

local Filter = {}

--- Apply a filter to text via async shell command.
--- If no filter is active, calls callback immediately with unmodified text.
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
  if not filter or not filter.cmd then
    callback(text)
    return
  end

  if logger then
    logger:info("Applying filter: " .. filter.name)
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
