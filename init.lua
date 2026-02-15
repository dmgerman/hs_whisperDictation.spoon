--- === WhisperDictation ===
---
--- Toggle local Whisper-based dictation with menubar indicator.
--- Records from mic, transcribes via multiple backends, shows chunks in real-time.
---
--- Features:
--- • Multiple recording backends: sox (simple), python-stream (continuous with Silero VAD)
--- • Continuous recording with auto-chunking (VAD-based silence detection)
--- • Real-time chunk display with hs.alert
--- • Multiple transcription backends: whisperkit-cli, whisper-cli, whisper-server
--- • Chunk-by-chunk transcription with ordered display
--- • Final concatenation to clipboard with chunk count summary
--- • Multiple languages support
--- • Optional activity monitoring
--- • Microphone off detection (perfect silence warning)
---
--- Usage:
-- wd = hs.loadSpoon("hs_whisperDictation")
-- wd.languages = {"en", "ja", "es", "fr"}
-- wd.recordingBackend = "pythonstream"  -- or "sox" for simple recording
-- wd.transcriptionMethod = "whisperkitcli"  -- or "whispercli", "whisperserver"
-- wd:bindHotKeys({
--    toggle = {dmg_all_keys, "l"},
--    nextLang = {dmg_all_keys, ";"},
-- })
-- wd:start()
--
-- Python stream backend requirements:
--   pip install sounddevice scipy torch
--
-- Requirements:
--      see readme.org

local obj = {}
obj.__index = obj

obj.name = "WhisperDictation"
obj.version = "1.0"
obj.author = "dmg"
obj.license = "MIT"

-- Load recording backends
local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local RecordingBackends = dofile(spoonPath .. "recording-backend.lua")

-- === Icons ===
obj.icons = {
  idle = "🎤",
  recording = "🎙️",
  clipboard = "📋",
  language = "🌐",
  stopped = "🛑",
  transcribing = "⏳",
  error = "❌",
  info = "ℹ️",
}

-- === Recording Indicator Style ===
obj.recordingIndicatorStyle = {
  fillColor = {red = 1, green = 0, blue = 0, alpha = 0.7},
  strokeColor = {red = 1, green = 0, blue = 0, alpha = 1},
  strokeWidth = 2,
}

-- === Config ===
obj.model = "large-v3"
obj.tempDir = "/tmp/whisper_dict"
obj.recordCmd = "/opt/homebrew/bin/sox"
obj.languages = {"en"}
obj.langIndex = 1
obj.showRecordingIndicator = true
obj.timeoutSeconds = 1800  -- Auto-stop recording after 1800 seconds (30 minutes). Set to nil to disable.
obj.retranscribeMethod = "whisperkitcli"  -- Backend used by transcribeLatestAgain()
obj.retranscribeCount = 10                -- Number of recent recordings to show in chooser
obj.monitorUserActivity = false           -- Track keyboard/mouse/app activity during recording
obj.autoPasteDelay = 0.1                  -- Delay in seconds before auto-pasting
obj.pasteWithEmacsYank = false            -- If true, paste with Ctrl-Y in Emacs instead of Cmd-V
obj.defaultHotkeys = {
  toggle = {{"ctrl", "cmd"}, "d"},
  nextLang = {{"ctrl", "cmd"}, "l"},
}

-- === Server Configuration (for whisperserver method) ===
obj.serverConfig = {
  executable = "/path/to/whisper-server",
  modelPath = "/usr/local/whisper/ggml-model.bin",
  modelPathFallback = "/usr/local/whisper/ggml-large-v3-turbo.bin",
  host = "127.0.0.1",
  port = "8080",
  startupTimeout = 10,  -- seconds to wait for server to start
  curlCmd = "/usr/bin/curl",
}

-- === Python Stream Backend Configuration ===
obj.pythonstreamConfig = {
  port = 12341,  -- TCP server port (user-configurable)
  host = "127.0.0.1",
  serverStartupTimeout = 5.0,  -- Seconds to wait for server ready
}

-- === Transcription Methods ===
-- Method-agnostic transcription system. Users select which method to use.
-- Each method implements: validate(), transcribe(audioFile, lang, callback)
-- callback signature: callback(success, text_or_error)
obj.transcriptionMethods = {
  whisperkitcli = {
    name = "whisperkitcli",
    displayName = "WhisperKit CLI",
    config = {
      cmd = "/opt/homebrew/bin/whisperkit-cli",
      model = "large-v3",
    },
    validate = function(self)
      return hs.fs.attributes(self.config.cmd) ~= nil
    end,
    --- Transcribe audio file using WhisperKit CLI.
    -- @param audioFile (string): Path to the WAV file
    -- @param lang (string): Language code (e.g., "en", "ja")
    -- @param callback (function): Called with (success, text_or_error)
    transcribe = function(self, audioFile, lang, callback)
      local args = {
        "transcribe",
        "--model=" .. self.config.model,
        "--audio-path=" .. audioFile,
        "--language=" .. lang,
      }
      obj.logger:info("Running: " .. self.config.cmd .. " " .. table.concat(args, " "))
      local task = hs.task.new(self.config.cmd, function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
          callback(false, stdErr or "whisperkit-cli failed")
          return
        end
        local text = stdOut or ""
        if text == "" then
          callback(false, "Empty transcript output")
          return
        end
        callback(true, text)
      end, args)
      if not task then
        callback(false, "Failed to create hs.task for WhisperKit CLI")
        return
      end
      local ok, err = pcall(function() task:start() end)
      if not ok then
        callback(false, "Failed to start WhisperKit CLI: " .. tostring(err))
      end
    end,
  },

  whispercli = {
    name = "whispercli",
    displayName = "Whisper CLI",
    config = {
      cmd = "/opt/homebrew/bin/whisper-cli",
      modelPath = "/usr/local/whisper/ggml-large-v3.bin",
    },
    validate = function(self)
      return hs.fs.attributes(self.config.cmd) ~= nil
    end,
    --- Transcribe audio file using Whisper CLI (whisper.cpp).
    -- @param audioFile (string): Path to the WAV file
    -- @param lang (string): Language code (e.g., "en", "ja")
    -- @param callback (function): Called with (success, text_or_error)
    transcribe = function(self, audioFile, lang, callback)
      local args = {
        "-np",
        "--model", self.config.modelPath,
        "--language", lang,
        "--output-txt",
        audioFile,
      }
      obj.logger:info("Running: " .. self.config.cmd .. " " .. table.concat(args, " "))
      local task = hs.task.new(self.config.cmd, function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
          callback(false, stdErr or "whisper-cli failed")
          return
        end
        -- whisper-cli creates a .txt file with same name as audio (e.g., audio.wav.txt)
        local outputFile = audioFile .. ".txt"
        local f = io.open(outputFile, "r")
        if not f then
          callback(false, "Could not read transcript file: " .. outputFile)
          return
        end
        local text = f:read("*a")
        f:close()
        if not text or text == "" then
          callback(false, "Empty transcript file")
          return
        end
        callback(true, text)
      end, args)
      if not task then
        callback(false, "Failed to create hs.task for Whisper CLI")
        return
      end
      local ok, err = pcall(function() task:start() end)
      if not ok then
        callback(false, "Failed to start Whisper CLI: " .. tostring(err))
      end
    end,
  },

  whisperserver = {
    name = "whisperserver",
    displayName = "Whisper Server",
    config = {}, -- Uses obj.serverConfig
    validate = function(self)
      return hs.fs.attributes(obj.serverConfig.executable) ~= nil
    end,
    --- Transcribe audio file by sending to whisper server via HTTP POST.
    -- @param audioFile (string): Path to the WAV file
    -- @param lang (string): Language code for transcription
    -- @param callback (function): Called with (success, text_or_error)
    transcribe = function(self, audioFile, lang, callback)
      -- Check server status before transcribing
      if not obj:isServerRunning() then
        if obj.serverStarting then
          -- Server is starting, fail with message
          hs.alert.show("Server is starting, please try again when ready")
          callback(false, "Server is starting, please try again when ready")
          return
        else
          -- Server not running and not starting, start it and fail current request
          hs.alert.show("Server starting... please try again when ready")
          obj:startServer()  -- Start async, no callback needed
          callback(false, "Server starting... please try again when ready")
          return
        end
      end
      local serverUrl = string.format("http://%s:%s/inference",
        obj.serverConfig.host, obj.serverConfig.port)
      local args = {
        "-s", "-X", "POST", serverUrl,
        "-F", string.format("file=@%s", audioFile),
        "-F", "response_format=text",
        "-F", string.format("language=%s", lang),
      }
      obj.logger:info("Running: " .. obj.serverConfig.curlCmd .. " " .. table.concat(args, " "))
      local task = hs.task.new(obj.serverConfig.curlCmd, function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
          callback(false, "curl failed: " .. (stdErr or "unknown error"))
          return
        end
        local text = (stdOut or ""):match("^%s*(.-)%s*$") -- trim whitespace
        if text == "" then
          callback(false, "Empty response from server")
          return
        end
        -- Check for server error response
        if text:match('^{"error"') then
          callback(false, "Server error: " .. text)
          return
        end
        -- Post-process: remove leading spaces from each line
        local lines = {}
        for line in text:gmatch("[^\n]+") do
          table.insert(lines, line:match("^%s*(.-)$"))
        end
        callback(true, table.concat(lines, "\n"))
      end, args)
      if not task then
        callback(false, "Failed to create hs.task for curl")
        return
      end
      local ok, err = pcall(function() task:start() end)
      if not ok then
        callback(false, "Failed to start curl: " .. tostring(err))
      end
    end,
  },
}

-- Select active transcription method (default to whispercli)
obj.transcriptionMethod = "whispercli"

-- === Recording Backend Configuration ===
obj.recordingBackend = "pythonstream"  -- "sox" or "pythonstream"
obj.recordingBackends = RecordingBackends
obj.chunkAlertDuration = 5.0  -- Duration to show chunk alerts (seconds)

-- === Logger ===
local Logger = {}
Logger.__index = Logger

function Logger.new()
  local self = setmetatable({}, Logger)
  self.logFile = os.getenv("HOME") .. "/.hammerspoon/Spoons/hs_whisperDictation/whisper.log"
  self.levels = {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
  }
  self.levelNames = {
    [0] = "DEBUG",
    [1] = "INFO",
    [2] = "WARN",
    [3] = "ERROR",
  }
  self.currentLevel = self.levels.INFO
  self.enableConsole = true
  self.enableFile = false
  return self
end

function Logger:_formatMessage(level, msg)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local levelName = self.levelNames[level]
  return string.format("[%s] [%s] %s", timestamp, levelName, msg)
end

function Logger:_writeToFile(formatted)
  local ok, f = pcall(io.open, self.logFile, "a")
  if ok and f then
    f:write(formatted .. "\n")
    f:close()
  end
end

function Logger:_log(level, msg, showAlert)
  if level < self.currentLevel then
    return
  end

  local formatted = self:_formatMessage(level, msg)

  if self.enableConsole then
    print("[WhisperDictation] " .. formatted)
  end

  if self.enableFile then
    self:_writeToFile(formatted)
  end

  if showAlert then
    local icon = level == self.levels.ERROR and obj.icons.error or obj.icons.info
    hs.alert.show(icon .. " " .. msg)
  end
end

function Logger:debug(msg)
  self:_log(self.levels.DEBUG, msg, false)
end

function Logger:info(msg, showAlert)
  self:_log(self.levels.INFO, msg, showAlert or false)
end

function Logger:warn(msg, showAlert)
  self:_log(self.levels.WARN, msg, showAlert or true)
end

function Logger:error(msg, showAlert)
  self:_log(self.levels.ERROR, msg, showAlert or true)
end

function Logger:setLevel(level)
  if self.levels[level] then
    self.currentLevel = self.levels[level]
  end
end



-- === Internal ===
obj.logger = Logger.new()

obj.recTask = nil
obj.menubar = nil
obj.hotkeys = {}
obj.timer = nil
obj.timeoutTimer = nil
obj.startTime = nil
obj.currentAudioFile = nil
obj.recordingIndicator = nil
obj.transcriptionCallback = nil

-- Server state (for whisperserver method)
obj.serverProcess = nil
obj.serverStarting = false   -- Track if server is currently starting (for async startup)

-- Activity monitoring state
obj.activityWatcher = nil
obj.appWatcher = nil
obj.userActivityDetected = false
obj.activityCounts = {keys = 0, clicks = 0, appSwitches = 0}
obj.startingApp = nil
obj.shouldPaste = false
obj.serverStartupTimer = nil  -- Keep timer alive to prevent garbage collection

-- Chunk tracking state (for continuous recording backends)
obj.recordingStartTime = nil        -- Total recording start time
obj.currentChunkStartTime = nil     -- Current chunk start time
obj.chunkCount = 0                  -- Total chunks received
obj.pendingChunks = {}              -- [chunkNum] = true while transcribing
obj.completedChunks = {}            -- [chunkNum] = text when done
obj.allChunksText = {}              -- Ordered array of all chunk texts for final concatenation
obj.recordingBackendFallback = false  -- Track if we fell back to sox

-- === Helpers ===
local function ensureDir(path)
  hs.fs.mkdir(path)
end

local function timestampedFile(baseDir, prefix, ext)
  local t = os.date("%Y%m%d-%H%M%S")
  return string.format("%s/%s-%s.%s", baseDir, prefix, t, ext)
end

local function currentLang()
  return obj.languages[obj.langIndex]
end

--- Scan tempDir for recent .wav recordings, sorted by modification time (newest first).
-- @param n (number): Maximum number of entries to return
-- @return (table): Array of { path, filename } tables
local function getRecentRecordings(n)
  local recordings = {}
  local iter, dirObj = hs.fs.dir(obj.tempDir)
  if not iter then
    return recordings
  end
  for filename in iter, dirObj do
    if filename:match("%.wav$") then
      local fullPath = obj.tempDir .. "/" .. filename
      local attrs = hs.fs.attributes(fullPath)
      if attrs then
        table.insert(recordings, {
          path = fullPath,
          filename = filename,
          modified = attrs.modification,
          size = attrs.size,
        })
      end
    end
  end
  table.sort(recordings, function(a, b) return a.modified > b.modified end)
  local result = {}
  for i = 1, math.min(n, #recordings) do
    result[i] = recordings[i]
  end
  return result
end

local function updateMenu(title, tip)
  if obj.menubar then
    obj.menubar:setTitle(title)
    obj.menubar:setTooltip(tip)
  end
end

local function resetMenuToIdle()
  updateMenu(obj.icons.idle .. " (" .. currentLang() .. ")", "Idle")
end

local function updateElapsed()
  if obj.startTime then
    local totalElapsed = os.difftime(os.time(), obj.startTime)

    -- Only show chunk info if using continuous backend (not sox)
    if obj.recordingBackend ~= "sox" and obj.chunkCount > 0 then
      local chunkElapsed = obj.currentChunkStartTime and os.difftime(os.time(), obj.currentChunkStartTime) or 0
      updateMenu(
        string.format(obj.icons.recording .. " Chunk %d (%ds/%ds) (%s)",
                     obj.chunkCount + 1, chunkElapsed, totalElapsed, currentLang()),
        "Recording..."
      )
    else
      updateMenu(string.format(obj.icons.recording .. " %ds (%s)", totalElapsed, currentLang()), "Recording...")
    end
  end
end

local function showRecordingIndicator()
  if obj.recordingIndicator then return end

  local focusedWindow = hs.window.focusedWindow()
  local screen = focusedWindow and focusedWindow:screen() or hs.screen.mainScreen()
  local frame = screen:frame()
  local centerX = frame.x + frame.w / 2
  local centerY = frame.y + frame.h / 2
  local radius = frame.h / 20

  obj.recordingIndicator = hs.drawing.circle(
    hs.geometry.rect(
      centerX - radius,
      centerY - radius,
      radius * 2,
      radius * 2
    )
  )

  local style = obj.recordingIndicatorStyle
  obj.recordingIndicator:setFillColor(style.fillColor)
  obj.recordingIndicator:setStrokeColor(style.strokeColor)
  obj.recordingIndicator:setStrokeWidth(style.strokeWidth)
  obj.recordingIndicator:show()
end

local function hideRecordingIndicator()
  if obj.recordingIndicator then
    obj.recordingIndicator:delete()
    obj.recordingIndicator = nil
  end
end

-- === Activity Monitoring ===

--- Check if a key code corresponds to a modifier key.
-- Modifier keys don't count toward activity (they're part of hotkey combos).
-- @param keyCode (number): The key code from event:getKeyCode()
-- @return (boolean): true if it's a modifier key
local function isModifierKey(keyCode)
  -- Modifier key codes on macOS:
  -- 54 = Right Cmd, 55 = Left Cmd
  -- 56 = Left Shift, 60 = Right Shift
  -- 58 = Left Alt/Option, 61 = Right Alt/Option
  -- 59 = Left Ctrl, 62 = Right Ctrl
  -- 63 = Fn
  local modifiers = {
    [54] = true, [55] = true,  -- Cmd
    [56] = true, [60] = true,  -- Shift
    [58] = true, [61] = true,  -- Alt/Option
    [59] = true, [62] = true,  -- Ctrl
    [63] = true,               -- Fn
  }
  return modifiers[keyCode] == true
end

--- Start monitoring user activity (keyboard, mouse clicks, app switches).
local function startActivityMonitoring()
  -- Reset activity state
  obj.userActivityDetected = false
  obj.activityCounts = {keys = 0, clicks = 0, appSwitches = 0}

  -- Track starting application
  local focusedWindow = hs.window.focusedWindow()
  obj.startingApp = focusedWindow and focusedWindow:application()

  -- Start eventtap for keyboard and mouse events
  local events = {
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.rightMouseDown,
    hs.eventtap.event.types.otherMouseDown,
  }

  obj.activityWatcher = hs.eventtap.new(events, function(event)
    local eventType = event:getType()

    if eventType == hs.eventtap.event.types.keyDown then
      -- Only count non-modifier keys
      -- This way Cmd+L counts as 1 key (L), not 2 (Cmd + L)
      local keyCode = event:getKeyCode()
      if not isModifierKey(keyCode) then
        obj.activityCounts.keys = obj.activityCounts.keys + 1
        obj.userActivityDetected = true
      end
    else
      -- Mouse click
      obj.activityCounts.clicks = obj.activityCounts.clicks + 1
      obj.userActivityDetected = true
    end

    -- Don't block the event
    return false
  end)

  obj.activityWatcher:start()

  -- Start application watcher for app switches
  obj.appWatcher = hs.application.watcher.new(function(appName, eventType, app)
    if eventType == hs.application.watcher.activated then
      -- Check if switched to a different app
      if obj.startingApp and app and app:bundleID() ~= obj.startingApp:bundleID() then
        obj.activityCounts.appSwitches = obj.activityCounts.appSwitches + 1
        obj.userActivityDetected = true
      end
    end
  end)

  obj.appWatcher:start()
  obj.logger:debug("Activity monitoring started")
end

--- Stop activity monitoring.
local function stopActivityMonitoring()
  if obj.activityWatcher then
    obj.activityWatcher:stop()
    obj.activityWatcher = nil
  end

  if obj.appWatcher then
    obj.appWatcher:stop()
    obj.appWatcher = nil
  end

  obj.logger:debug("Activity monitoring stopped")
end

--- Get a human-readable summary of detected activity.
-- @return (string): Summary like "3 keys, 2 clicks, 1 app switch"
local function getActivitySummary()
  local parts = {}
  local c = obj.activityCounts

  if c.keys > 0 then
    local keyDesc = c.keys == 1 and "1 key" or string.format("%d keys", c.keys)
    table.insert(parts, keyDesc)
  end
  if c.clicks > 0 then
    table.insert(parts, string.format("%d click%s", c.clicks, c.clicks == 1 and "" or "s"))
  end
  if c.appSwitches > 0 then
    table.insert(parts, string.format("%d app switch%s", c.appSwitches, c.appSwitches == 1 and "" or "es"))
  end

  return #parts > 0 and table.concat(parts, ", ") or "no activity"
end

--- Check if current focused app matches the starting app.
-- @return (boolean): true if same app is focused
local function isSameAppFocused()
  if not obj.startingApp then
    return false
  end

  local focusedWindow = hs.window.focusedWindow()
  local currentApp = focusedWindow and focusedWindow:application()

  if not currentApp then
    return false
  end

  return currentApp:bundleID() == obj.startingApp:bundleID()
end

--- Paste text using appropriate method for current application.
-- If pasteWithEmacsYank is enabled and current app is Emacs, uses Ctrl-Y.
-- Otherwise uses standard Cmd-V.
local function smartPaste()
  if obj.pasteWithEmacsYank then
    local focusedWindow = hs.window.focusedWindow()
    local currentApp = focusedWindow and focusedWindow:application()
    if currentApp and currentApp:bundleID() == "org.gnu.Emacs" then
      hs.eventtap.keyStroke({"ctrl"}, "y")
      return
    end
  end
  -- Default paste
  hs.eventtap.keyStroke({"cmd"}, "v")
end

local function startRecordingSession()
  -- Start elapsed time display timer
  obj.startTime = os.time()
  if obj.timer then obj.timer:stop() end
  obj.timer = hs.timer.doEvery(1, updateElapsed)

  -- Start auto-stop timeout timer if configured
  if obj.timeoutSeconds and obj.timeoutSeconds > 0 then
    if obj.timeoutTimer then obj.timeoutTimer:stop() end
    obj.timeoutTimer = hs.timer.doAfter(obj.timeoutSeconds, function()
      -- Check if any backend is still recording
      local isRecording = false
      for _, backend in pairs(obj.recordingBackends) do
        if backend:isRecording() then
          isRecording = true
          break
        end
      end

      if isRecording then
        obj.logger:warn(obj.icons.stopped .. " Recording auto-stopped due to timeout (" .. obj.timeoutSeconds .. "s)", true)
        obj:toggleTranscribe()
      end
    end)
  end

  -- Show recording indicator if enabled
  if obj.showRecordingIndicator then
    showRecordingIndicator()
  end

  -- Start activity monitoring if enabled and not using callback
  if obj.monitorUserActivity and not obj.transcriptionCallback then
    startActivityMonitoring()
  end
end

local function stopRecordingSession()
  obj.logger:info(obj.icons.stopped .. " Recording stopped")

  -- Stop elapsed time display timer
  if obj.timer then
    obj.timer:stop()
    obj.timer = nil
  end
  obj.startTime = nil

  -- Stop auto-stop timeout timer
  if obj.timeoutTimer then
    obj.timeoutTimer:stop()
    obj.timeoutTimer = nil
  end

  -- Hide recording indicator
  hideRecordingIndicator()

  -- Stop activity monitoring if enabled
  if obj.monitorUserActivity and (obj.activityWatcher or obj.appWatcher) then
    stopActivityMonitoring()
  end

  -- Reset menu to idle state
  resetMenuToIdle()
end

-- === Server Lifecycle Methods ===

--- Get the best available model path.
-- Checks primary path first, falls back to fallback path.
-- @return (string|nil): Model path or nil if neither exists
local function getServerModelPath()
  if hs.fs.attributes(obj.serverConfig.modelPath) then
    return obj.serverConfig.modelPath
  end
  return nil
end

--- Check if a whisper server is responding on the configured port.
-- @return (boolean): true if server is healthy (regardless of who started it)
function obj:isServerRunning()
  -- Health check via curl (synchronous, fast)
  -- In Lua 5.2+, os.execute returns: true/nil, "exit"/"signal", code
  local serverUrl = string.format("http://%s:%s", self.serverConfig.host, self.serverConfig.port)
  local ok = os.execute(string.format(
    "%s -s -o /dev/null --connect-timeout 1 %s 2>/dev/null",
    self.serverConfig.curlCmd, serverUrl
  ))
  -- If server is not responding but we have a process handle, clean it up
  if ok ~= true and self.serverProcess then
    if not self.serverProcess:isRunning() then
      self.serverProcess = nil
    end
  end
  return ok == true
end

--- Start the whisper server asynchronously.
-- If a server is already running on the port (externally started), adopts it.
-- @param callback (function|nil): Optional callback called with (success, error_message) when server is ready or fails
-- @return (boolean, string|nil): success (immediate check), error message on failure
function obj:startServer(callback)
  if self:isServerRunning() then
    -- Server already running - could be ours or external
    if self.serverProcess then
      self.logger:info("Whisper server already running (managed by this spoon)")
    else
      self.logger:info("Whisper server already running (external process)")
    end
    if callback then callback(true, nil) end
    return true, nil
  end

  -- Check if server is already starting
  if self.serverStarting then
    hs.alert.show("Server already starting...")
    self.logger:info("Server startup already in progress")
    return false, "Server already starting"
  end

  local modelPath = getServerModelPath()
  if not modelPath then
    local err = "Whisper model not found at " .. self.serverConfig.modelPath
    self.logger:error(err, true)
    if callback then callback(false, err) end
    return false, err
  end

  if not hs.fs.attributes(self.serverConfig.executable) then
    local err = "Whisper server executable not found at " .. self.serverConfig.executable
    self.logger:error(err, true)
    if callback then callback(false, err) end
    return false, err
  end

  local args = {
    "-m", modelPath,
    "--host", self.serverConfig.host,
    "--port", self.serverConfig.port,
  }

  self.logger:info("Starting whisper server with model " .. modelPath)
  self.serverProcess = hs.task.new(self.serverConfig.executable, function(exitCode, stdOut, stdErr)
    self.logger:warn("Whisper server exited with code " .. tostring(exitCode))
    if stdErr and #stdErr > 0 then
      self.logger:debug("Server stderr: " .. stdErr)
    end
    self.serverProcess = nil
    self.serverStarting = false
  end, args)

  if not self.serverProcess then
    local err = "Failed to create server task"
    self.logger:error(err, true)
    if callback then callback(false, err) end
    return false, err
  end

  local ok, err = pcall(function() self.serverProcess:start() end)
  if not ok then
    self.serverProcess = nil
    local errMsg = "Failed to start server: " .. tostring(err)
    self.logger:error(errMsg, true)
    if callback then callback(false, errMsg) end
    return false, errMsg
  end

  -- Mark server as starting and show alert
  self.serverStarting = true
  hs.alert.show("Starting whisper server...")

  -- Start async polling to check when server is ready
  local pollInterval = 0.5
  local maxAttempts = math.ceil(self.serverConfig.startupTimeout / pollInterval)
  local attempts = 0

  local pollTimer
  pollTimer = hs.timer.doEvery(pollInterval, function()
    attempts = attempts + 1
    if self:isServerRunning() then
      -- Server is ready
      pollTimer:stop()
      self.serverStarting = false
      self.logger:info("Whisper server ready")
      hs.alert.show("Whisper server ready")
      if callback then callback(true, nil) end
    elseif attempts >= maxAttempts then
      -- Timeout reached
      pollTimer:stop()
      self.serverStarting = false
      local errMsg = "Server failed to start after " .. self.serverConfig.startupTimeout .. " seconds"
      self.logger:error(errMsg, true)
      if callback then callback(false, errMsg) end
    elseif not self.serverProcess or not self.serverProcess:isRunning() then
      -- Server process died
      pollTimer:stop()
      self.serverStarting = false
      local errMsg = "Server process exited unexpectedly"
      self.logger:error(errMsg, true)
      if callback then callback(false, errMsg) end
    end
  end)

  return true, nil
end

--- Stop the whisper server (only if managed by this spoon).
-- External servers are not stopped.
function obj:stopServer()
  if self.serverProcess and self.serverProcess:isRunning() then
    self.logger:info("Stopping whisper server")
    self.serverProcess:terminate()
    self.serverProcess = nil
    self.serverStarting = false
  elseif self:isServerRunning() then
    self.logger:info("External whisper server running - not stopping (not managed by this spoon)")
  end
end

--- Ensure the whisper server is running, starting it if needed.
-- This is now an async function that uses a callback.
-- @param callback (function): Called with (success, error_message) when server is ready or fails
function obj:ensureServer(callback)
  if self:isServerRunning() then
    if callback then callback(true, nil) end
    return
  end

  if self.serverStarting then
    if callback then callback(false, "Server is starting...") end
    return
  end

  -- Start the server asynchronously
  self:startServer(callback)
end

-- === Transcription Handling ===

--- Handle transcription result from any method.
-- @param success (boolean): Whether transcription succeeded
-- @param textOrError (string): Transcribed text on success, error message on failure
-- @param audioFile (string): Path to the audio file (for saving transcript)
local function handleTranscriptionResult(success, textOrError, audioFile)
  local method = obj.transcriptionMethods[obj.transcriptionMethod]

  if not success then
    obj.logger:error(method.displayName .. ": " .. textOrError, true)
    resetMenuToIdle()
    return
  end

  local text = textOrError

  -- Save transcript to file
  local outputFile = audioFile:gsub("%.wav$", ".txt")
  local f, err = io.open(outputFile, "w")
  if f then
    f:write(text)
    f:close()
    obj.logger:debug("Transcript written to file: " .. outputFile)
  else
    obj.logger:warn("Could not save transcript file: " .. tostring(err))
  end

  -- Call the callback if one was provided
  if obj.transcriptionCallback then
    local ok, callbackErr = pcall(obj.transcriptionCallback, text)
    if not ok then
      obj.logger:error("Callback error: " .. tostring(callbackErr))
    end
    obj.transcriptionCallback = nil
  else
    -- Copy to clipboard
    local ok, errPB = pcall(hs.pasteboard.setContents, text)
    if not ok then
      obj.logger:error("Failed to copy to clipboard: " .. tostring(errPB), true)
      resetMenuToIdle()
      return
    end

    -- Handle auto-paste logic if requested
    if obj.shouldPaste then
      local c = obj.activityCounts
      local hasActivity = (c.keys >= 2) or (c.clicks >= 1) or (c.appSwitches >= 1)

      if obj.monitorUserActivity and hasActivity then
        -- Activity detected - warn and skip paste
        local summary = getActivitySummary()
        obj.logger:warn(
          "⚠️  User activity detected during recording (" .. summary .. ") - text copied to clipboard (not pasted)",
          true
        )
      elseif obj.monitorUserActivity and not isSameAppFocused() then
        -- Different app focused - skip paste
        obj.logger:warn(
          "⚠️  Application changed during recording - text copied to clipboard (not pasted)",
          true
        )
      else
        -- No activity (or monitoring disabled) and same app - auto-paste
        obj.logger:info(obj.icons.clipboard .. " Copied to clipboard (" .. #text .. " chars) - pasting...", true)
        hs.timer.doAfter(obj.autoPasteDelay, function()
          smartPaste()
        end)
      end
      obj.shouldPaste = false
    else
      -- Normal mode - just copy to clipboard
      obj.logger:info(obj.icons.clipboard .. " Copied to clipboard (" .. #text .. " chars)", true)
    end
  end

  resetMenuToIdle()
end

--- Transcribe an audio file using the selected method.
-- @param audioFile (string): Path to the WAV file to transcribe
local function transcribe(audioFile)
  local method = obj.transcriptionMethods[obj.transcriptionMethod]
  if not method then
    obj.logger:error("Unknown transcription method: " .. obj.transcriptionMethod, true)
    resetMenuToIdle()
    return
  end

  obj.logger:info(obj.icons.transcribing .. " Transcribing (" .. currentLang() .. ")...", true)
  updateMenu(obj.icons.idle .. " (" .. currentLang() .. " T)", "Transcribing...")

  -- Call the method's transcribe function with callback
  method:transcribe(audioFile, currentLang(), function(success, textOrError)
    handleTranscriptionResult(success, textOrError, audioFile)
  end)
end


local function showLanguageChooser()
  local choices = {}
  for i, lang in ipairs(obj.languages) do
    table.insert(choices, {
      text = lang,
      subText = (i == obj.langIndex and "✓ Selected" or ""),
      lang = lang,
      index = i,
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if choice then
      obj.langIndex = choice.index
      obj.logger:info(obj.icons.language .. " Language switched to: " .. choice.lang, true)
      resetMenuToIdle()
    end
  end)

--  chooser:width(0.3)
  chooser:choices(choices)
  chooser:show()
end

--- Re-transcribe a previously recorded audio file using the retranscribe backend.
-- @param audioFile (string): Path to the WAV file
-- @param lang (string): Language code extracted from the filename
-- @param callback (function|nil): Optional callback receiving transcribed text
local function retranscribe(audioFile, lang, callback)
  local method = obj.transcriptionMethods[obj.retranscribeMethod]
  if not method then
    obj.logger:error("Unknown retranscription method: " .. obj.retranscribeMethod, true)
    return
  end

  obj.transcriptionCallback = callback
  local savedMethod = obj.transcriptionMethod
  obj.transcriptionMethod = obj.retranscribeMethod

  obj.logger:info(obj.icons.transcribing .. " Re-transcribing with " .. method.displayName .. " (" .. lang .. ")...", true)
  updateMenu(obj.icons.idle .. " (" .. lang .. " T)", "Re-transcribing...")

  method:transcribe(audioFile, lang, function(success, textOrError)
    obj.transcriptionMethod = savedMethod
    handleTranscriptionResult(success, textOrError, audioFile)
  end)
end

--- Show a chooser with recent recordings for re-transcription.
-- @param callback (function|nil): Optional callback receiving transcribed text
local function showRetranscribeChooser(callback)
  local recordings = getRecentRecordings(obj.retranscribeCount)
  if #recordings == 0 then
    obj.logger:warn("No recent recordings found in " .. obj.tempDir, true)
    return
  end

  local choices = {}
  for _, rec in ipairs(recordings) do
    -- Parse filename pattern: {lang}-{YYYYMMDD-HHMMSS}.wav
    local lang, dateStr, timeStr = rec.filename:match("^(%w+)-(%d%d%d%d%d%d%d%d)-(%d%d%d%d%d%d)%.wav$")
    local displayText = rec.filename
    if lang and dateStr and timeStr then
      local y = dateStr:sub(1, 4)
      local m = dateStr:sub(5, 6)
      local d = dateStr:sub(7, 8)
      local hh = timeStr:sub(1, 2)
      local mm = timeStr:sub(3, 4)
      local ss = timeStr:sub(5, 6)
      local timestamp = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d),
                                  hour=tonumber(hh), min=tonumber(mm), sec=tonumber(ss)})
      displayText = lang .. " - " .. os.date("%b %d, %Y %H:%M:%S", timestamp)
    end

    table.insert(choices, {
      text = displayText,
      subText = rec.filename .. string.format(" (%.1f MB)", rec.size / (1024 * 1024)),
      path = rec.path,
      lang = lang or "en",
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if choice then
      retranscribe(choice.path, choice.lang, callback)
    end
  end)

  chooser:choices(choices)
  chooser:show()
end

-- === Recording Backend Event Handling ===

-- Helper functions (called by transcription callbacks)
local function concatenateChunks()
  local parts = {}
  for i = 1, obj.chunkCount do
    local text = obj.allChunksText[i]
    if text then
      table.insert(parts, text)
    end
  end
  return table.concat(parts, "\n\n")
end

local function hasPendingChunks()
  for _, _ in pairs(obj.pendingChunks) do
    return true
  end
  return false
end

local function isStillRecording()
  local backend = obj.recordingBackends[obj.recordingBackend]
  return backend and backend:isRecording()
end

--- Finalize transcription - concatenate all chunks and copy to clipboard.
local function finalizeTranscription()
  print(string.format("[DEBUG] finalizeTranscription: chunkCount=%d", obj.chunkCount))

  -- Check if recording was aborted (no chunks processed)
  if obj.chunkCount == 0 then
    obj.logger:info("❌ Transcription aborted (no audio recorded)", true)
    resetMenuToIdle()
    return
  end

  local fullText = concatenateChunks()
  local charCount = #fullText
  print(string.format("[DEBUG] Concatenated text length: %d", charCount))

  -- Save transcription to .txt file (matching complete WAV file)
  if obj.completeRecordingFile then
    local txtFile = obj.completeRecordingFile:gsub("%.wav$", ".txt")
    local f, err = io.open(txtFile, "w")
    if f then
      f:write(fullText)
      f:close()
      print(string.format("[DEBUG] Transcription saved to: %s", txtFile))
    else
      obj.logger:warn("Failed to save transcription file: " .. tostring(err))
    end
  end

  local ok, err = pcall(hs.pasteboard.setContents, fullText)
  if not ok then
    obj.logger:error("Failed to copy to clipboard: " .. tostring(err), true)
    return
  end
  print("[DEBUG] Text copied to clipboard successfully")

  -- Show different message for single vs multiple chunks
  local message
  if obj.chunkCount == 1 then
    message = string.format("Transcription complete: %d characters", charCount)
  else
    message = string.format("Transcription complete: %d chunks, %d characters", obj.chunkCount, charCount)
  end

  -- Handle auto-paste if enabled
  if obj.shouldPaste then
    local c = obj.activityCounts
    local hasActivity = (c.keys >= 2) or (c.clicks >= 1) or (c.appSwitches >= 1)

    if obj.monitorUserActivity and hasActivity then
      -- Activity detected - warn and skip paste
      local summary = getActivitySummary()
      obj.logger:warn(
        "⚠️  User activity detected during recording (" .. summary .. ") - text copied to clipboard (not pasted)",
        true
      )
    elseif obj.monitorUserActivity and not isSameAppFocused() then
      -- Different app focused - skip paste
      obj.logger:warn(
        "⚠️  Application changed during recording - text copied to clipboard (not pasted)",
        true
      )
    else
      -- Auto-paste after delay
      obj.logger:info(obj.icons.clipboard .. " Copied to clipboard (" .. charCount .. " chars) - pasting...", true)
      hs.timer.doAfter(obj.autoPasteDelay, function()
        smartPaste()
      end)
    end
    obj.shouldPaste = false
  end

  print(string.format("[DEBUG] Showing completion alert: %s", message))
  hs.alert.show(message, 5.0)
  obj.logger:info(message)
  resetMenuToIdle()
end

--- Check if all pending transcriptions are complete and finalize if done.
local function checkIfTranscriptionComplete()
  local stillRecording = isStillRecording()
  local pending = hasPendingChunks()
  print(string.format("[DEBUG] checkIfTranscriptionComplete: stillRecording=%s, hasPending=%s", tostring(stillRecording), tostring(pending)))

  if stillRecording then
    print("[DEBUG] Still recording, not finalizing")
    return
  end

  if not pending then
    print("[DEBUG] No pending chunks, calling finalizeTranscription")
    finalizeTranscription()
  else
    print("[DEBUG] Still have pending chunks, waiting")
  end
end

--- Save completed chunks to clipboard in case of error.
local function saveCompletedChunks()
  if obj.chunkCount == 0 then
    return
  end

  local fullText = concatenateChunks()
  if #fullText > 0 then
    local ok, err = pcall(hs.pasteboard.setContents, fullText)
    if ok then
      local chunkCount = 0
      for i = 1, obj.chunkCount do
        if obj.allChunksText[i] then
          chunkCount = chunkCount + 1
        end
      end
      obj.logger:info(string.format("Saved %d completed chunks to clipboard", chunkCount), true)
    end
  end
end

-- Transcription handlers
local function handleChunkTranscriptionSuccess(chunkNum, text)
  print(string.format("[DEBUG] handleChunkTranscriptionSuccess: chunk=%d, length=%d", chunkNum, #text))
  obj.completedChunks[chunkNum] = text
  obj.allChunksText[chunkNum] = text

  -- Only show chunk number if using continuous backend (not sox)
  if obj.recordingBackend ~= "sox" then
    print(string.format("[DEBUG] Showing chunk alert for chunk %d", chunkNum))
    hs.alert.show(string.format("Chunk %d: %s", chunkNum, text), obj.chunkAlertDuration)
  end
  obj.logger:info(string.format("Chunk %d transcribed (%d chars)", chunkNum, #text))

  print(string.format("[DEBUG] Calling checkIfTranscriptionComplete"))
  checkIfTranscriptionComplete()
end

local function handleChunkTranscriptionFailure(chunkNum, error)
  print(string.format("[DEBUG] handleChunkTranscriptionFailure: chunk=%d, error=%s", chunkNum, error))
  obj.logger:error(string.format("Chunk %d transcription failed: %s", chunkNum, error), true)
  checkIfTranscriptionComplete()
end

--- Transcribe a single chunk.
-- @param chunkNum (number): Chunk sequence number
-- @param audioFile (string): Path to audio file
-- @param isFinal (boolean): Whether this is the final chunk
local function transcribeChunk(chunkNum, audioFile, isFinal)
  print(string.format("[DEBUG] transcribeChunk: chunk=%d, file=%s", chunkNum, audioFile))
  local method = obj.transcriptionMethods[obj.transcriptionMethod]
  if not method then
    obj.logger:error("Unknown transcription method: " .. obj.transcriptionMethod, true)
    obj.pendingChunks[chunkNum] = nil
    return
  end

  print(string.format("[DEBUG] Starting transcription with %s", method.displayName))
  obj.logger:debug(string.format("Transcribing chunk %d with %s", chunkNum, method.displayName))

  method:transcribe(audioFile, currentLang(), function(success, textOrError)
    print(string.format("[DEBUG] Transcription callback: chunk=%d, success=%s", chunkNum, tostring(success)))
    obj.pendingChunks[chunkNum] = nil

    if success then
      handleChunkTranscriptionSuccess(chunkNum, textOrError)
    else
      handleChunkTranscriptionFailure(chunkNum, textOrError)
    end
  end)
end

local function handleChunkReady(event)
  local chunkNum = event.chunk_num or event.chunkNum or 1
  local audioFile = event.audio_file or event.audioFile
  local isFinal = event.is_final or event.isFinal or false

  print(string.format("[DEBUG] handleChunkReady: chunk=%d, file=%s, final=%s", chunkNum, audioFile, tostring(isFinal)))
  obj.logger:info(string.format("Chunk %d ready: %s%s", chunkNum, audioFile, isFinal and " (final)" or ""))

  -- Show alert that chunk is being saved and transcribed
  hs.alert.show(string.format("Chunk %d recorded, transcribing...", chunkNum), 2.0)

  -- Update chunk count and start time for next chunk
  if chunkNum > obj.chunkCount then
    obj.chunkCount = chunkNum
    obj.currentChunkStartTime = os.time()
    print(string.format("[DEBUG] Updated chunkCount to %d", obj.chunkCount))
  end

  -- Mark chunk as pending and transcribe
  obj.pendingChunks[chunkNum] = true
  print(string.format("[DEBUG] Marked chunk %d as pending, calling transcribeChunk", chunkNum))
  transcribeChunk(chunkNum, audioFile, isFinal)
end

local function handleRecordingError(event)
  local errorMsg = event.error or "Unknown error from recording backend"
  obj.logger:error("Recording error: " .. errorMsg, true)

  -- Stop recording immediately
  local backend = obj.recordingBackends[obj.recordingBackend]
  if backend and backend:isRecording() then
    pcall(function() backend:stopRecording() end)
  end
  stopRecordingSession()

  -- Save completed chunks if we have any (mid-recording error)
  local hasCompletedChunks = false
  for _, text in pairs(obj.completedChunks) do
    if text then
      hasCompletedChunks = true
      break
    end
  end

  if hasCompletedChunks then
    saveCompletedChunks()
  end

  resetMenuToIdle()
end

local function handleSilenceWarning(event)
  local message = event.message or "Perfect silence detected - microphone may be off"
  obj.logger:warn("⚠️  " .. message, true)
end

--- Handle events from recording backend.
-- @param event (table): Event from recording backend
local function handleRecordingEvent(event)
  local eventType = event.type
  if eventType == "server_ready" then
    obj.logger:debug("Recording server ready")
  elseif eventType == "recording_started" then
    obj.logger:debug("Recording backend started")
    hs.alert.show("🎙️ Ready to record", 1.5)
  elseif eventType == "chunk_ready" then
    handleChunkReady(event)
  elseif eventType == "recording_stopped" then
    obj.logger:info("Recording backend stopped")

    -- For persistent backends (pythonstream), keep connection alive
    -- For sox, clean up as before
    local backend = obj.recordingBackends[obj.recordingBackend]
    if backend and backend.name == "sox" and backend._client then
      pcall(function() backend._client:disconnect() end)
      backend._client = nil
      backend._serverProcess = nil
      backend._callback = nil
      backend._outputDir = nil
      backend._stopping = false
    end

    -- Stop recording session UI (menubar, timer, indicator)
    stopRecordingSession()

    -- Trigger finalization check now that recording has stopped
    checkIfTranscriptionComplete()
  elseif eventType == "complete_file" then
    obj.completeRecordingFile = event.file_path
  elseif eventType == "silence_warning" then
    handleSilenceWarning(event)
  elseif eventType == "error" then
    handleRecordingError(event)
  elseif eventType == "debug" then
    -- Ignore debug events
  else
    obj.logger:warn("Unknown event type from recording backend: " .. tostring(eventType))
  end
end

-- === Public API ===

local function parseCallbackOrPaste(callbackOrPaste)
  if type(callbackOrPaste) == "function" then
    obj.transcriptionCallback = callbackOrPaste
    obj.shouldPaste = false
  elseif type(callbackOrPaste) == "boolean" then
    obj.transcriptionCallback = nil
    obj.shouldPaste = callbackOrPaste
  else
    obj.transcriptionCallback = nil
    obj.shouldPaste = false
  end
end

local function resetChunkState()
  obj.recordingStartTime = os.time()
  obj.currentChunkStartTime = os.time()
  obj.chunkCount = 0
  obj.pendingChunks = {}
  obj.completedChunks = {}
  obj.allChunksText = {}
  obj.recordingBackendFallback = false
  obj.completeRecordingFile = nil  -- Path to complete WAV file
end

local function tryStartRecording(backend)
  return backend:startRecording(
    obj.tempDir,
    currentLang(),
    currentLang(),
    handleRecordingEvent
  )
end

--- Begin transcription with optional callback or auto-paste flag.
-- @param callbackOrPaste (function|boolean|nil): If function, uses callback. If true, enables auto-paste. If nil/false, clipboard only.
-- @return self
function obj:beginTranscribe(callbackOrPaste)
  local backend = self.recordingBackends[self.recordingBackend]
  if not backend then
    self.logger:error("Unknown recording backend: " .. self.recordingBackend, true)
    return self
  end

  if backend:isRecording() then
    self.logger:warn("Recording already in progress", true)
    return self
  end

  parseCallbackOrPaste(callbackOrPaste)
  resetChunkState()
  ensureDir(self.tempDir)

  local success, err = tryStartRecording(backend)

  if not success then
    self.logger:error("Failed to start " .. backend.displayName .. ": " .. tostring(err))

    -- Auto-fallback to sox if pythonstream fails
    if self.recordingBackend == "pythonstream" then
      self.logger:warn("Falling back to Sox backend")
      hs.alert.show("Python stream failed, using simple recording mode")
      self.recordingBackend = "sox"
      self.recordingBackendFallback = true
      backend = self.recordingBackends.sox

      success, err = tryStartRecording(backend)
    end

    if not success then
      -- Even sox failed - critical error
      self.logger:error("All backends failed: " .. tostring(err), true)
      resetMenuToIdle()
      return self
    end
  end

  self.logger:info(self.icons.recording .. " Recording started with " .. backend.displayName .. " (" .. currentLang() .. ")", true)
  startRecordingSession()
  return self
end

function obj:endTranscribe()
  -- Get active recording backend (may be fallback)
  local backend = self.recordingBackends[self.recordingBackendFallback and "sox" or self.recordingBackend]
  if not backend then
    self.logger:error("Unknown recording backend", true)
    return self
  end

  -- Check if recording
  if not backend:isRecording() then
    self.logger:warn("No recording in progress", true)
    return self
  end

  -- Stop recording backend
  local success, err = backend:stopRecording()
  if not success then
    self.logger:error("Failed to stop recording: " .. tostring(err), true)
  end

  -- Stop recording session UI
  stopRecordingSession()

  -- Note: Chunks will be transcribed via handleRecordingEvent callbacks
  -- Final concatenation happens in checkIfTranscriptionComplete()

  -- Note: With 2-way TCP communication, server sends all events before exiting
  -- recording_stopped event handler will trigger checkIfTranscriptionComplete()
  -- No need to scan for missed chunks anymore!

  return self
end

--- Toggle transcription with optional callback or auto-paste flag.
-- @param callbackOrPaste (function|boolean|nil): If function, uses callback. If true, enables auto-paste. If nil/false, clipboard only.
-- @return self
function obj:toggleTranscribe(callbackOrPaste)
  -- Check if any backend is currently recording
  local isRecording = false
  for _, backend in pairs(self.recordingBackends) do
    if backend:isRecording() then
      isRecording = true
      break
    end
  end

  if not isRecording then
    self:beginTranscribe(callbackOrPaste)
  else
    self:endTranscribe()
  end
  return self
end

--- Show a chooser with recent recordings and re-transcribe the selected one.
-- @param callback (function|nil): Optional callback receiving transcribed text. If nil, copies to clipboard.
-- @return self
function obj:transcribeLatestAgain(callback)
  showRetranscribeChooser(callback)
  return self
end

function obj:start()
  obj.logger:info("Starting WhisperDictation")
  local errorSuffix = " WhisperDictation not started"

  -- Set up Python stream backend script path
  obj.recordingBackends.pythonstream.config.scriptPath = spoonPath .. "whisper_stream.py"

  -- Apply pythonstream config if this backend is selected
  if obj.recordingBackend == "pythonstream" then
    obj.recordingBackends.pythonstream.config.port = obj.pythonstreamConfig.port
    obj.recordingBackends.pythonstream.config.host = obj.pythonstreamConfig.host
    obj.recordingBackends.pythonstream.config.serverStartupTimeout = obj.pythonstreamConfig.serverStartupTimeout
  end

  -- Validate recording backend
  local backend = obj.recordingBackends[obj.recordingBackend]
  if not backend then
    obj.logger:error("Unknown recording backend: " .. obj.recordingBackend .. errorSuffix, true)
    return
  end

  local backendValid, backendErr = backend:validate()
  if not backendValid then
    -- Recording backend validation failed
    obj.logger:warn("⚠️  " .. backend.displayName .. " validation failed: " .. tostring(backendErr))

    -- If not sox, try to fall back to sox
    if obj.recordingBackend ~= "sox" then
      obj.logger:warn("⚠️  Will attempt to use Sox as fallback when recording starts")
      -- Don't fail startup - we'll try fallback when recording starts
    else
      -- Sox itself failed - can't proceed
      obj.logger:error("Sox validation failed: " .. tostring(backendErr) .. errorSuffix, true)
      return
    end
  else
    obj.logger:info("Recording backend: " .. backend.displayName)
  end

  -- Validate transcription method
  local method = obj.transcriptionMethods[obj.transcriptionMethod]
  if not method then
    obj.logger:error("Unknown transcription method: " .. obj.transcriptionMethod .. errorSuffix, true)
    return
  end

  if not method:validate() then
    -- Build appropriate error message based on method type
    local details = method.config.cmd or obj.serverConfig.executable
    obj.logger:error(method.displayName .. " not found: " .. details .. errorSuffix, true)
    return
  end

  ensureDir(obj.tempDir)

  if not obj.menubar then
    obj.menubar = hs.menubar.new()
    obj.menubar:setClickCallback(function() obj:toggleTranscribe() end)
  end

  -- Start server if using whisperserver method
  if obj.transcriptionMethod == "whisperserver" then
    obj.logger:info("Starting whisper server...")
    local started, err = obj:startServer()
    if not started then
      obj.logger:warn("Server not started: " .. tostring(err) .. " (will retry on first transcription)")
    end
  end

  -- Start persistent Python stream server asynchronously if using pythonstream backend
  if obj.recordingBackend == "pythonstream" then
    obj.logger:info("Starting Python stream server in background...")
    ensureDir(obj.tempDir)

    -- Start server asynchronously to avoid blocking Hammerspoon startup
    -- Store timer to prevent garbage collection
    obj.serverStartupTimer = hs.timer.doAfter(0.5, function()
      obj.logger:info("[ASYNC] Server startup callback executing...")
      local ok, err = pcall(function()
        local backend = obj.recordingBackends.pythonstream
        obj.logger:info("[ASYNC] Calling backend:startServer()...")
        local started, startErr = backend:startServer(obj.tempDir, currentLang())
        obj.logger:info("[ASYNC] startServer returned: " .. tostring(started))
        if not started then
          local errorMsg = tostring(startErr)
          obj.logger:warn("Python stream server not started: " .. errorMsg .. " (will start on first recording)")
          -- Show alert for port conflicts (user needs to know immediately)
          if errorMsg:match("Port.*in use") or errorMsg:match("already in use") then
            hs.alert.show("⚠️ Python stream server: " .. errorMsg, 5)
          end
        else
          obj.logger:info("Python stream server ready")
        end
      end)
      if not ok then
        obj.logger:error("Python stream server async startup failed: " .. tostring(err))
        hs.alert.show("⚠️ Python stream server failed\nSee console for details", 3)
      end
      obj.logger:info("[ASYNC] Server startup callback complete")
    end)
  end

  resetMenuToIdle()
  obj.logger:info("WhisperDictation ready using " .. method.displayName .. " (" .. currentLang() .. ")", true)
end

function obj:stop()
  obj.logger:info("Stopping WhisperDictation")

  -- Stop the whisper server if running
  obj:stopServer()

  -- Stop Python stream server if running
  if obj.recordingBackend == "pythonstream" then
    local backend = obj.recordingBackends.pythonstream
    if backend:isServerRunning() then
      obj.logger:info("Stopping Python stream server...")
      backend:stopServer()
    end
  end

  if obj.menubar then
    obj.menubar:delete()
    obj.menubar = nil
  end
  for _, hk in pairs(obj.hotkeys) do hk:delete() end
  obj.hotkeys = {}
  stopRecordingSession()
  obj.logger:info("WhisperDictation stopped", true)
end

function obj:bindHotKeys(mapping)
  obj.logger:debug("Binding hotkeys")
  local map = hs.fnutils.copy(mapping or obj.defaultHotkeys)
  for name, spec in pairs(map) do
    if obj.hotkeys[name] then obj.hotkeys[name]:delete() end
    if name == "toggle" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], "Toggle whisper transcription [Audio]", function() obj:toggleTranscribe() end)
      obj.logger:debug("Bound hotkey: toggle to " .. table.concat(spec[1], "+") .. "+" .. spec[2])
    elseif name == "togglePaste" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], "Toggle whisper transcription with auto-paste [Audio]", function() obj:toggleTranscribe(true) end)
      obj.logger:debug("Bound hotkey: togglePaste to " .. table.concat(spec[1], "+") .. "+" .. spec[2])
    elseif name == "nextLang" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], "Select whisper language for transcription [Audio]", showLanguageChooser)
      obj.logger:debug("Bound hotkey: nextLang to " .. table.concat(spec[1], "+") .. "+" .. spec[2])
    elseif name == "retranscribe" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], "Retranscribe latest audio [Audio]", function() obj:transcribeLatestAgain() end)
      obj.logger:debug("Bound hotkey: retranscribe to " .. table.concat(spec[1], "+") .. "+" .. spec[2])
    end
  end
  return self
end

return obj
