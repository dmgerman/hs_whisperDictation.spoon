--- Mock Hammerspoon APIs for Testing
-- Provides test doubles for hs.* APIs without requiring Hammerspoon to be running

local MockHS = {}

-- State storage for mocks
local state = {
  alerts = {},
  clipboard = "",
  tasks = {},
  timers = {},
  fs_files = {},
}

--- Reset all mock state (call in after_each)
function MockHS._resetAll()
  state.alerts = {}
  state.clipboard = ""
  state.tasks = {}
  state.timers = {}
  state.fs_files = {}
  -- Clear task callbacks
  if MockHS.task then
    MockHS.task._creationCallback = nil
    MockHS.task._exitCallback = nil
  end
end

--- hs.alert - Alert notifications
MockHS.alert = {
  show = function(message, duration)
    table.insert(state.alerts, {
      message = message,
      duration = duration or 2,
      timestamp = os.time(),
    })
  end,
  _getAlerts = function()
    return state.alerts
  end,
}

--- hs.pasteboard - Clipboard
MockHS.pasteboard = {
  setContents = function(contents)
    state.clipboard = contents
  end,
  getContents = function()
    return state.clipboard
  end,
  readString = function()
    return state.clipboard
  end,
  writeObjects = function(obj)
    if type(obj) == "string" then
      state.clipboard = obj
    elseif type(obj) == "table" and obj[1] then
      state.clipboard = obj[1]
    end
  end,
}

--- hs.task - Process execution
MockHS.task = {
  _creationCallback = nil,  -- For testing task creation with specific arguments

  new = function(launchPath, callbackFn, args)
    local task = {
      _launchPath = launchPath,
      _callback = callbackFn,
      _args = args or {},
      _pid = #state.tasks + 1,
      _running = false,
      _streamingCallback = nil,
    }

    function task:start()
      self._running = true
      table.insert(state.tasks, self)
      -- Simulate async completion
      if self._callback then
        -- Call callback in next tick
        MockHS.timer.doAfter(0.001, function()
          if self._running then
            self._callback(0, "", "")  -- exitCode, stdout, stderr
          end
        end)
      end
      return self
    end

    function task:terminate()
      self._running = false
      if self._callback then
        self._callback(15, "", "")  -- SIGTERM exit code
      end
      return self
    end

    function task:pid()
      return self._pid
    end

    function task:isRunning()
      return self._running
    end

    function task:setStreamingCallback(fn)
      self._streamingCallback = fn
      return self
    end

    -- Call creation callback if registered (for testing)
    if MockHS.task._creationCallback then
      MockHS.task._creationCallback(launchPath, callbackFn, args)
    end

    return task
  end,

  _getTasks = function()
    return state.tasks
  end,

  _registerCreationCallback = function(fn)
    MockHS.task._creationCallback = fn
  end,

  _clearCreationCallback = function()
    MockHS.task._creationCallback = nil
  end,

  _registerExitCallback = function(fn)
    -- For testing task exit handling
    MockHS.task._exitCallback = fn
  end,

  _clearExitCallback = function()
    MockHS.task._exitCallback = nil
  end,
}

--- hs.timer - Timers and delays
MockHS.timer = {
  new = function(interval, fn)
    local timer = {
      _interval = interval,
      _fn = fn,
      _running = false,
      _id = #state.timers + 1,
    }

    function timer:start()
      self._running = true
      table.insert(state.timers, self)
      return self
    end

    function timer:stop()
      self._running = false
      return self
    end

    function timer:running()
      return self._running
    end

    return timer
  end,

  doAfter = function(delay, fn)
    -- Execute immediately ONLY for very short delays (< 1 second)
    -- This allows task completion callbacks to work while preventing
    -- timeout timers from firing during tests
    if fn and delay < 1.0 then
      fn()
    end
    -- For longer delays, return a timer that can be stopped but doesn't fire
    local timer = {
      _delay = delay,
      _fn = fn,
      _running = true,
      _id = #state.timers + 1,
    }

    function timer:stop()
      self._running = false
      return self
    end

    function timer:running()
      return self._running
    end

    table.insert(state.timers, timer)
    return timer
  end,

  doEvery = function(interval, fn)
    -- Return a timer object that can be stopped, but don't actually run
    -- Tests don't need the repeating behavior
    local timer = {
      _interval = interval,
      _fn = fn,
      _running = true,
      _id = #state.timers + 1,
    }

    function timer:stop()
      self._running = false
      return self
    end

    function timer:running()
      return self._running
    end

    table.insert(state.timers, timer)
    return timer
  end,

  usleep = function(microseconds)
    -- Mock microsecond sleep - just return immediately in tests
    -- No actual delay needed in tests
  end,

  waitUntil = function(predicateFn, actionFn, checkInterval)
    -- For tests, just check immediately
    if predicateFn() then
      actionFn()
    end
  end,

  _getTimers = function()
    return state.timers
  end,
}

--- hs.fs - Filesystem operations
MockHS.fs = {
  attributes = function(filepath)
    -- Return mock attributes if file is registered
    if state.fs_files[filepath] then
      return state.fs_files[filepath]
    end
    -- Check if file actually exists (for real file testing)
    local f = io.open(filepath, "r")
    if f then
      f:close()
      return { mode = "file", size = 0 }
    end
    return nil
  end,

  mkdir = function(dirname)
    state.fs_files[dirname] = { mode = "directory" }
    return true
  end,

  rmdir = function(dirname)
    state.fs_files[dirname] = nil
    return true
  end,

  dir = function(path)
    -- Return an iterator over files in directory
    -- For tests, return empty iterator
    local files = {}
    for filepath, _ in pairs(state.fs_files) do
      if filepath:match("^" .. path .. "/[^/]+$") then
        local filename = filepath:match("[^/]+$")
        table.insert(files, filename)
      end
    end

    local index = 0
    local function iterator()
      index = index + 1
      return files[index]
    end

    return iterator, nil
  end,

  _registerFile = function(filepath, attrs)
    state.fs_files[filepath] = attrs or { mode = "file", size = 0 }
  end,

  _unregisterFile = function(filepath)
    state.fs_files[filepath] = nil
  end,
}

--- hs.socket - TCP sockets
MockHS.socket = {
  new = function(callbackFn)
    local sock = {
      _callback = callbackFn,
      _connected = false,
      _data = "",
    }

    function sock:connect(host, port, fn)
      self._host = host
      self._port = port
      self._connected = true
      if fn then
        fn(self)
      end
      if self._callback then
        self._callback("connect", self)
      end
      return self
    end

    function sock:disconnect()
      self._connected = false
      if self._callback then
        self._callback("closed", self)
      end
      return self
    end

    function sock:send(data)
      self._data = self._data .. data
      return self
    end

    function sock:write(data)
      self._data = self._data .. data
      return true  -- Return success
    end

    function sock:read(delimiter)
      -- Store delimiter for simulation
      self._readDelimiter = delimiter
      return ""
    end

    function sock:setCallback(fn)
      self._callback = fn
      return self
    end

    function sock:connected()
      return self._connected
    end

    -- Test helper to simulate receiving data
    function sock:_simulateReceive(data)
      if self._callback then
        self._callback("receive", data)
      end
    end

    return sock
  end,
}

--- hs.drawing - On-screen drawing
MockHS.drawing = {
  rectangle = function(rect)
    return {
      setFill = function() return {} end,
      setStroke = function() return {} end,
      setFillColor = function() return {} end,
      setStrokeColor = function() return {} end,
      setRoundedRectRadii = function() return {} end,
      show = function() return {} end,
      hide = function() return {} end,
      delete = function() return {} end,
    }
  end,

  text = function(rect, text)
    return {
      setTextSize = function() return {} end,
      setTextColor = function() return {} end,
      setTextFont = function() return {} end,
      show = function() return {} end,
      hide = function() return {} end,
      delete = function() return {} end,
    }
  end,
}

--- hs.screen - Screen information
MockHS.screen = {
  primaryScreen = function()
    return {
      frame = function()
        return { x = 0, y = 0, w = 1920, h = 1080 }
      end,
    }
  end,
}

--- hs.menubar - Menubar items
MockHS.menubar = {
  new = function()
    local menubar = {
      _title = "",
      _tooltip = "",
      _callback = nil,
    }

    function menubar:setTitle(title)
      self._title = title
      return self
    end

    function menubar:setTooltip(tooltip)
      self._tooltip = tooltip
      return self
    end

    function menubar:setMenu(menu)
      self._menu = menu
      return self
    end

    function menubar:setIcon(icon)
      self._icon = icon
      return self
    end

    function menubar:setClickCallback(callback)
      self._callback = callback
      return self
    end

    function menubar:delete()
      self._deleted = true
      return self
    end

    return menubar
  end,
}

--- hs.hotkey - Keyboard shortcuts
MockHS.hotkey = {
  bind = function(mods, key, pressedfn, releasedfn, repeatfn)
    return {
      enable = function() return {} end,
      disable = function() return {} end,
      delete = function() return {} end,
    }
  end,
}

--- hs.eventtap - Event tapping
MockHS.eventtap = {
  keyStroke = function(modifiers, character, delay)
    -- Mock keystroke
  end,

  event = {
    types = {
      keyDown = 10,
      keyUp = 11,
    },
  },
}

--- hs.chooser - UI chooser
MockHS.chooser = {
  new = function(completionFn)
    return {
      choices = function() return {} end,
      show = function() return {} end,
      hide = function() return {} end,
      delete = function() return {} end,
    }
  end,
}

--- hs.json - JSON encoding/decoding
MockHS.json = {
  encode = function(obj, prettyprint)
    -- Simple JSON encoding (use Lua's built-in if available)
    local function encode_value(v)
      local t = type(v)
      if t == "string" then
        return '"' .. v:gsub('"', '\\"') .. '"'
      elseif t == "number" or t == "boolean" then
        return tostring(v)
      elseif t == "table" then
        local isArray = #v > 0
        if isArray then
          local parts = {}
          for i, val in ipairs(v) do
            table.insert(parts, encode_value(val))
          end
          return "[" .. table.concat(parts, ",") .. "]"
        else
          local parts = {}
          for k, val in pairs(v) do
            table.insert(parts, '"' .. k .. '":' .. encode_value(val))
          end
          return "{" .. table.concat(parts, ",") .. "}"
        end
      else
        return "null"
      end
    end
    return encode_value(obj)
  end,

  decode = function(jsonString)
    -- Simple JSON decoding - just for basic tests
    -- For real JSON, use a proper library or cjson
    if jsonString == "null" then
      return nil
    end
    -- Very basic - just handle simple objects
    return {}
  end,
}

--- hs.logger - Logging
MockHS.logger = {
  new = function(id, loglevel)
    return {
      i = function(msg) end,
      d = function(msg) end,
      w = function(msg) end,
      e = function(msg) end,
      f = function(msg) end,
      setLogLevel = function(level) end,
    }
  end,
}

--- hs.application - Application management
MockHS.application = {
  frontmostApplication = function()
    return {
      bundleID = function() return "com.apple.Terminal" end,
      name = function() return "Terminal" end,
    }
  end,
}

--- hs.window - Window management
MockHS.window = {
  focusedWindow = function()
    return {
      screen = function()
        return MockHS.screen.mainScreen()
      end,
    }
  end,
}

--- hs.screen - Screen management
MockHS.screen = {
  mainScreen = function()
    return {
      frame = function()
        return { x = 0, y = 0, w = 1920, h = 1080 }
      end,
    }
  end,
}

--- hs.geometry - Geometric objects
MockHS.geometry = {
  rect = function(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
  end,
}

--- hs.drawing - Drawing on screen
MockHS.drawing = {
  circle = function(rect)
    return {
      setFillColor = function() end,
      setStrokeColor = function() end,
      setStrokeWidth = function() end,
      show = function() end,
      delete = function() end,
    }
  end,
}

--- hs.menubar - Menubar items
MockHS.menubar = {
  new = function()
    return {
      setTitle = function() end,
      setTooltip = function() end,
      setClickCallback = function() end,
      setMenu = function() end,
      delete = function() end,
    }
  end,
}

return MockHS
