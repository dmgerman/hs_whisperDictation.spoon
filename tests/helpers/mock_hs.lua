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
  new = function(launchPath, callbackFn, args)
    local task = {
      _launchPath = launchPath,
      _callback = callbackFn,
      _args = args or {},
      _pid = #state.tasks + 1,
      _running = false,
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

    return task
  end,
  _getTasks = function()
    return state.tasks
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
    -- Execute immediately in tests (can't wait for real delays)
    -- For tests that need async behavior, they can handle it themselves
    if fn then
      fn()
    end
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

    function sock:read(delimiter)
      -- Return mock data
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
    return {
      setTitle = function() return {} end,
      setTooltip = function() return {} end,
      setMenu = function() return {} end,
      setIcon = function() return {} end,
      delete = function() return {} end,
    }
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

return MockHS
