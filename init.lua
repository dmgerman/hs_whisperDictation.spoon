--- === WhisperDictation ===
---
--- Toggle local Whisper-based dictation with menubar indicator.
--- Records from mic, transcribes via multiple backends, shows chunks in real-time.
---
--- Features:
--- • Multiple recording backends: sox (simple), pythonstream (continuous with Silero VAD)
--- • Continuous recording with auto-chunking (VAD-based silence detection)
--- • Real-time chunk display with hs.alert
--- • Multiple transcription backends: whisperkitcli, whispercli, whisperserver, groq
--- • Chunk-by-chunk transcription with ordered display
--- • Final concatenation to clipboard with chunk count summary
--- • Multiple languages support
--- • Optional activity monitoring
--- • Microphone off detection (perfect silence warning)
---
--- Usage:
-- wd = hs.loadSpoon("hs_whisperDictation")
-- wd.languages = {"en", "ja", "es", "fr"}
-- wd.config = {
--   recorder = "streaming",  -- "sox" or "streaming"
--   transcriber = "whisperkit",  -- "whispercli", "whisperkit", or "whisperserver"
-- }
-- wd:bindHotKeys({
--    toggle = {dmg_all_keys, "l"},
--    nextLang = {dmg_all_keys, ";"},
-- })
-- wd:start()
--
-- Requirements: see readme.md

local obj = {}
obj.__index = obj

obj.name = "WhisperDictation"
obj.version = "2.0"
obj.author = "dmg"
obj.license = "MIT"

-- ============================================================================
-- === Path Setup ===
-- ============================================================================

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

-- Fallback for when loaded via dofile() in tests
if not spoonPath then
  spoonPath = "./"
end

-- Add spoon path to package.path for require() calls
local parentPath = spoonPath:match("(.*/)Spoons/.-%.spoon/") or spoonPath:match("(.*/)")
if spoonPath and spoonPath ~= "./" then
  package.path = package.path .. ";" .. spoonPath .. "?.lua;" .. spoonPath .. "?/init.lua"
end
if parentPath then
  package.path = package.path .. ";" .. parentPath .. "?.lua;" .. parentPath .. "?/init.lua"
end

-- ============================================================================
-- === Icons ===
-- ============================================================================

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

-- ============================================================================
-- === Recording Indicator Style ===
-- ============================================================================

obj.recordingIndicatorStyle = {
  fillColor = {red = 1, green = 0, blue = 0, alpha = 0.7},
  strokeColor = {red = 1, green = 0, blue = 0, alpha = 1},
  strokeWidth = 2,
}

-- ============================================================================
-- === Configuration Properties (Public API) ===
-- ============================================================================

-- Basic settings
obj.tempDir = "/tmp/whisper_dict"
obj.languages = {"en"}
obj.langIndex = 1

-- NEW ARCHITECTURE CONFIGURATION
-- Configuration for new architecture (callback-based, no EventBus/Promises)
obj.config = {
  recorder = "sox",  -- "sox" or "streaming"
  transcriber = "whispercli",  -- "whispercli", "whisperkit", or "whisperserver"

  -- Recorder-specific configs
  sox = {
    soxCmd = "/opt/homebrew/bin/sox",
    audioInputDevice = nil,  -- nil = default device, or "BlackHole 2ch" for tests
    tempDir = nil,  -- nil = use obj.tempDir
  },

  streaming = {
    pythonPath = os.getenv("HOME") .. "/.config/dmg/python3.12/bin/python3",
    serverScript = nil,  -- nil = auto-detect from spoon directory
    tcpPort = 12341,
    audioInputDevice = nil,  -- nil = default device, or "BlackHole 2ch" for tests
    silenceThreshold = 2.0,  -- seconds of silence to trigger chunk boundary
    minChunkDuration = 3.0,  -- minimum chunk duration in seconds
    maxChunkDuration = 600.0,  -- maximum chunk duration (10 minutes)
    perfectSilenceDuration = 0,  -- seconds of perfect silence to detect mic off (0 = disabled, 2.0 for testing)
    tempDir = nil,  -- nil = use obj.tempDir
  },

  -- Transcriber-specific configs
  whispercli = {
    executable = "/opt/homebrew/bin/whisper-cli",
    modelPath = "/usr/local/whisper/ggml-large-v3.bin",
  },

  whisperkit = {
    cmd = "/opt/homebrew/bin/whisperkit-cli",
    model = "large-v3",
  },

  whisperserver = {
    host = "127.0.0.1",
    port = "8080",
    curlCmd = "/usr/bin/curl",
  },
}

-- UI settings
obj.showRecordingIndicator = true

-- Auto-stop settings
obj.timeoutSeconds = 1800  -- Auto-stop recording after 30 minutes. Set to nil to disable.

-- Activity monitoring (prevents auto-paste if user was active during recording)
obj.monitorUserActivity = false
obj.autoPasteDelay = 0.1
obj.pasteWithEmacsYank = false

-- Default hotkeys
obj.defaultHotkeys = {
  toggle = {{"ctrl", "cmd"}, "d"},
  nextLang = {{"ctrl", "cmd"}, "l"},
}

-- ============================================================================
-- === Logger ===
-- ============================================================================

local Logger = {}
Logger.__index = Logger

function Logger.new()
  local self = setmetatable({}, Logger)
  self.logFile = os.getenv("HOME") .. "/.hammerspoon/Spoons/hs_whisperDictation/whisper.log"
  self.levels = {DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3}
  self.levelNames = {[0] = "DEBUG", [1] = "INFO", [2] = "WARN", [3] = "ERROR"}
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
  if level < self.currentLevel then return end

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

function Logger:debug(msg) self:_log(self.levels.DEBUG, msg, false) end
function Logger:info(msg, showAlert) self:_log(self.levels.INFO, msg, showAlert or false) end
function Logger:warn(msg, showAlert) self:_log(self.levels.WARN, msg, showAlert or true) end
function Logger:error(msg, showAlert) self:_log(self.levels.ERROR, msg, showAlert or true) end

function Logger:setLevel(level)
  if self.levels[level] then
    self.currentLevel = self.levels[level]
  end
end

-- ============================================================================
-- === Internal State ===
-- ============================================================================

obj.logger = Logger.new()

-- Architecture components (created in start())
obj.manager = nil  -- Manager instance
obj.recorder = nil  -- IRecorder instance
obj.transcriber = nil  -- ITranscriber instance

-- UI state
obj.menubar = nil
obj.hotkeys = {}
obj.timer = nil
obj.timeoutTimer = nil
obj.startTime = nil
obj.recordingIndicator = nil

-- Activity monitoring state
obj.activityWatcher = nil
obj.appWatcher = nil
obj.userActivityDetected = false
obj.activityCounts = {keys = 0, clicks = 0, appSwitches = 0}
obj.startingApp = nil
obj.shouldPaste = false

-- Callback state
obj.transcriptionCallback = nil

-- ============================================================================
-- === Helper Functions ===
-- ============================================================================

local function ensureDir(path)
  hs.fs.mkdir(path)
end

local function currentLang()
  return obj.languages[obj.langIndex]
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
  if obj.manager and obj.manager.state == "RECORDING" then
    local elapsed = obj.startTime and (os.time() - obj.startTime) or 0
    updateMenu(string.format("%s %ds (%s)", obj.icons.recording, elapsed, currentLang()), "Recording...")
  end
end

-- ============================================================================
-- === Recording Indicator ===
-- ============================================================================

local function showRecordingIndicator()
  if obj.recordingIndicator then return end

  local focusedWindow = hs.window.focusedWindow()
  local screen = focusedWindow and focusedWindow:screen() or hs.screen.mainScreen()
  local frame = screen:frame()
  local centerX = frame.x + frame.w / 2
  local centerY = frame.y + frame.h / 2
  local radius = frame.h / 20

  obj.recordingIndicator = hs.drawing.circle(
    hs.geometry.rect(centerX - radius, centerY - radius, radius * 2, radius * 2)
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

-- ============================================================================
-- === Activity Monitoring ===
-- ============================================================================

local function isModifierKey(keyCode)
  local modifiers = {
    [54] = true, [55] = true,  -- Cmd
    [56] = true, [60] = true,  -- Shift
    [58] = true, [61] = true,  -- Alt/Option
    [59] = true, [62] = true,  -- Ctrl
    [63] = true,               -- Fn
  }
  return modifiers[keyCode] == true
end

local function startActivityMonitoring()
  obj.userActivityDetected = false
  obj.activityCounts = {keys = 0, clicks = 0, appSwitches = 0}

  local focusedWindow = hs.window.focusedWindow()
  obj.startingApp = focusedWindow and focusedWindow:application()

  local events = {
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.rightMouseDown,
    hs.eventtap.event.types.otherMouseDown,
  }

  obj.activityWatcher = hs.eventtap.new(events, function(event)
    local eventType = event:getType()

    if eventType == hs.eventtap.event.types.keyDown then
      local keyCode = event:getKeyCode()
      if not isModifierKey(keyCode) then
        obj.activityCounts.keys = obj.activityCounts.keys + 1
        obj.userActivityDetected = true
      end
    else
      obj.activityCounts.clicks = obj.activityCounts.clicks + 1
      obj.userActivityDetected = true
    end

    return false
  end)

  obj.activityWatcher:start()

  obj.appWatcher = hs.application.watcher.new(function(appName, eventType, app)
    if eventType == hs.application.watcher.activated then
      if obj.startingApp and app and app:bundleID() ~= obj.startingApp:bundleID() then
        obj.activityCounts.appSwitches = obj.activityCounts.appSwitches + 1
        obj.userActivityDetected = true
      end
    end
  end)

  obj.appWatcher:start()
  obj.logger:debug("Activity monitoring started")
end

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

local function isSameAppFocused()
  if not obj.startingApp then return false end

  local focusedWindow = hs.window.focusedWindow()
  local currentApp = focusedWindow and focusedWindow:application()

  if not currentApp then return false end

  return currentApp:bundleID() == obj.startingApp:bundleID()
end

-- Get recent recordings sorted by modification time
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

local function smartPaste()
  obj.logger:info("smartPaste() called - attempting to paste")

  if obj.pasteWithEmacsYank then
    local focusedWindow = hs.window.focusedWindow()
    local currentApp = focusedWindow and focusedWindow:application()
    if currentApp and currentApp:bundleID() == "org.gnu.Emacs" then
      obj.logger:info("Using Emacs yank (Ctrl+Y)")
      local ok, err = pcall(hs.eventtap.keyStroke, {"ctrl"}, "y")
      if not ok then
        error("Emacs yank failed: " .. tostring(err))
      end
      return
    end
  end

  obj.logger:info("Using standard paste (Cmd+V)")
  local ok, err = pcall(hs.eventtap.keyStroke, {"cmd"}, "v")
  if not ok then
    error("Paste keystroke failed: " .. tostring(err))
  end
  obj.logger:info("Paste keystroke sent successfully")
end

-- ============================================================================
-- === Recording Session Management ===
-- ============================================================================

local function startRecordingSession()
  obj.startTime = os.time()
  if obj.timer then obj.timer:stop() end
  obj.timer = hs.timer.doEvery(1, updateElapsed)

  if obj.timeoutSeconds and obj.timeoutSeconds > 0 then
    if obj.timeoutTimer then obj.timeoutTimer:stop() end
    obj.timeoutTimer = hs.timer.doAfter(obj.timeoutSeconds, function()
      if obj.manager and obj.manager.state == "RECORDING" then
        obj.logger:warn(obj.icons.stopped .. " Recording auto-stopped due to timeout (" .. obj.timeoutSeconds .. "s)", true)
        obj:toggleTranscribe()
      end
    end)
  end

  if obj.showRecordingIndicator then
    showRecordingIndicator()
  end

  if obj.monitorUserActivity and not obj.transcriptionCallback then
    startActivityMonitoring()
  end
end

local function stopRecordingSession()
  obj.logger:info(obj.icons.stopped .. " Recording stopped")

  if obj.timer then
    obj.timer:stop()
    obj.timer = nil
  end
  obj.startTime = nil

  if obj.timeoutTimer then
    obj.timeoutTimer:stop()
    obj.timeoutTimer = nil
  end

  hideRecordingIndicator()

  if obj.monitorUserActivity and (obj.activityWatcher or obj.appWatcher) then
    stopActivityMonitoring()
  end

  resetMenuToIdle()
end

-- ============================================================================
-- === Language Chooser ===
-- ============================================================================

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

  chooser:choices(choices)
  chooser:show()
end

-- ============================================================================
-- === Public API ===
-- ============================================================================

function obj:beginTranscribe(callbackOrPaste)
  if not self.manager then
    self.logger:error("Manager not initialized. Call start() first.", true)
    return self
  end

  if self.manager.state ~= "IDLE" then
    self.logger:warn("Recording already in progress (state: " .. self.manager.state .. ")", true)
    return self
  end

  -- Parse callback/paste option (for future auto-paste support)
  if type(callbackOrPaste) == "function" then
    self.transcriptionCallback = callbackOrPaste
    self.shouldPaste = false
  elseif type(callbackOrPaste) == "boolean" then
    self.transcriptionCallback = nil
    self.shouldPaste = callbackOrPaste
  else
    self.transcriptionCallback = nil
    self.shouldPaste = false
  end

  -- Ensure temp directory exists
  ensureDir(self.tempDir)

  -- Start recording via Manager (callback-based, no promises)
  local ok, err = self.manager:startRecording(currentLang())

  if ok then
    self.logger:info(self.icons.recording .. " Recording started (" .. currentLang() .. ")", true)
    startRecordingSession()
  else
    local errorMsg = "❌ Recording failed: " .. tostring(err)
    self.logger:error(errorMsg, true)
    hs.alert.show(errorMsg, 10.0)
    resetMenuToIdle()
  end

  return self
end

function obj:endTranscribe()
  if not self.manager then
    self.logger:error("Manager not initialized", true)
    return self
  end

  if self.manager.state ~= "RECORDING" then
    self.logger:warn("No recording in progress (state: " .. self.manager.state .. ")", true)
    return self
  end

  -- Stop recording via Manager (callback-based, no promises)
  local ok, err = self.manager:stopRecording()

  if ok then
    self.logger:info("Recording stopped, transcribing...")
    -- Note: stopRecordingSession() will be called by Manager's state transitions
  else
    self.logger:error("Failed to stop recording: " .. tostring(err), true)
    stopRecordingSession()
  end

  return self
end

function obj:toggleTranscribe(callbackOrPaste)
  if not self.manager then
    self.logger:error("Manager not initialized. Call start() first.", true)
    return self
  end

  if self.manager.state == "IDLE" or self.manager.state == "ERROR" then
    self:beginTranscribe(callbackOrPaste)
  elseif self.manager.state == "RECORDING" then
    self:endTranscribe()
  else
    self.logger:warn("Cannot toggle in state: " .. self.manager.state, true)
  end
  return self
end

-- Alias for backwards compatibility and convenience
function obj:toggle(callbackOrPaste)
  return self:toggleTranscribe(callbackOrPaste)
end

function obj:isRecording()
  return self.manager and self.manager.state == "RECORDING" or false
end

-- ============================================================================
-- === Start/Stop ===
-- ============================================================================

function obj:start()
  obj.logger:info("Starting WhisperDictation v2")

  -- Load new architecture components
  local Manager = dofile(spoonPath .. "core_v2/manager.lua")
  local Notifier = dofile(spoonPath .. "lib/notifier.lua")

  -- ============================================================================
  -- === RECORDER - with fallback logic ===
  -- ============================================================================
  local recorderType = obj.config.recorder or "sox"
  local recorderCreated = false

  -- Try primary recorder
  if recorderType == "streaming" then
    local StreamingRecorder = dofile(spoonPath .. "recorders/streaming/streaming_recorder.lua")
    local streamingConfig = obj.config.streaming or {}
    streamingConfig.tempDir = streamingConfig.tempDir or obj.tempDir
    streamingConfig.serverScript = streamingConfig.serverScript or (spoonPath .. "recorders/streaming/whisper_stream.py")
    obj.recorder = StreamingRecorder.new(streamingConfig)

    local ok, err = obj.recorder:validate()
    if ok then
      obj.logger:info("✓ Recorder: " .. obj.recorder:getName())
      recorderCreated = true
    else
      -- Streaming failed, try sox fallback
      Notifier.show("init", "warning", "StreamingRecorder unavailable: " .. tostring(err) .. ", using SoxRecorder as fallback")
      obj.logger:warn("StreamingRecorder validation failed: " .. tostring(err) .. ", falling back to Sox")

      local SoxRecorder = dofile(spoonPath .. "recorders/sox_recorder.lua")
      local soxConfig = obj.config.sox or {}
      soxConfig.tempDir = soxConfig.tempDir or obj.tempDir
      obj.recorder = SoxRecorder.new(soxConfig)

      ok, err = obj.recorder:validate()
      if ok then
        obj.logger:info("✓ Fallback Recorder: " .. obj.recorder:getName())
        recorderCreated = true
      else
        Notifier.show("init", "error", "No working recorders found: " .. tostring(err))
        obj.logger:error("Sox fallback validation failed: " .. tostring(err), true)
        return false
      end
    end
  elseif recorderType == "sox" then
    local SoxRecorder = dofile(spoonPath .. "recorders/sox_recorder.lua")
    local soxConfig = obj.config.sox or {}
    soxConfig.tempDir = soxConfig.tempDir or obj.tempDir
    obj.recorder = SoxRecorder.new(soxConfig)

    local ok, err = obj.recorder:validate()
    if ok then
      obj.logger:info("✓ Recorder: " .. obj.recorder:getName())
      recorderCreated = true
    else
      Notifier.show("init", "error", "Recorder validation failed: " .. tostring(err))
      obj.logger:error("SoxRecorder validation failed: " .. tostring(err), true)
      return false
    end
  else
    Notifier.show("init", "error", "Unknown recorder type: " .. recorderType)
    obj.logger:error("Unknown recorder type: " .. recorderType, true)
    return false
  end

  if not recorderCreated then
    Notifier.show("init", "error", "Failed to create recorder")
    obj.logger:error("Failed to create recorder", true)
    return false
  end

  -- ============================================================================
  -- === TRANSCRIBER - with fallback logic ===
  -- ============================================================================
  local transcriberType = obj.config.transcriber or "whispercli"
  local transcriberCreated = false

  -- Try primary transcriber
  if transcriberType == "whisperkit" then
    local WhisperKitTranscriber = dofile(spoonPath .. "transcribers/whisperkit_transcriber.lua")
    local kitConfig = obj.config.whisperkit or {}
    obj.transcriber = WhisperKitTranscriber.new(kitConfig)

    local ok, err = obj.transcriber:validate()
    if ok then
      obj.logger:info("✓ Transcriber: " .. obj.transcriber:getName())
      transcriberCreated = true
    else
      -- WhisperKit failed, try whispercli fallback
      Notifier.show("init", "warning", "WhisperKit unavailable: " .. tostring(err) .. ", using WhisperCLI as fallback")
      obj.logger:warn("WhisperKit validation failed: " .. tostring(err) .. ", falling back to WhisperCLI")

      local WhisperCLITranscriber = dofile(spoonPath .. "transcribers/whispercli_transcriber.lua")
      local cliConfig = obj.config.whispercli or {}
      obj.transcriber = WhisperCLITranscriber.new(cliConfig)

      ok, err = obj.transcriber:validate()
      if ok then
        obj.logger:info("✓ Fallback Transcriber: " .. obj.transcriber:getName())
        transcriberCreated = true
      else
        Notifier.show("init", "error", "No working transcribers found: " .. tostring(err))
        obj.logger:error("WhisperCLI fallback validation failed: " .. tostring(err), true)
        return false
      end
    end
  elseif transcriberType == "whisperserver" then
    local WhisperServerTranscriber = dofile(spoonPath .. "transcribers/whisperserver_transcriber.lua")
    local serverConfig = obj.config.whisperserver or {}
    obj.transcriber = WhisperServerTranscriber.new(serverConfig)

    local ok, err = obj.transcriber:validate()
    if ok then
      obj.logger:info("✓ Transcriber: " .. obj.transcriber:getName())
      transcriberCreated = true
    else
      -- WhisperServer failed, try whispercli fallback
      Notifier.show("init", "warning", "WhisperServer unavailable: " .. tostring(err) .. ", using WhisperCLI as fallback")
      obj.logger:warn("WhisperServer validation failed: " .. tostring(err) .. ", falling back to WhisperCLI")

      local WhisperCLITranscriber = dofile(spoonPath .. "transcribers/whispercli_transcriber.lua")
      local cliConfig = obj.config.whispercli or {}
      obj.transcriber = WhisperCLITranscriber.new(cliConfig)

      ok, err = obj.transcriber:validate()
      if ok then
        obj.logger:info("✓ Fallback Transcriber: " .. obj.transcriber:getName())
        transcriberCreated = true
      else
        Notifier.show("init", "error", "No working transcribers found: " .. tostring(err))
        obj.logger:error("WhisperCLI fallback validation failed: " .. tostring(err), true)
        return false
      end
    end
  elseif transcriberType == "whispercli" then
    local WhisperCLITranscriber = dofile(spoonPath .. "transcribers/whispercli_transcriber.lua")
    local cliConfig = obj.config.whispercli or {}
    obj.transcriber = WhisperCLITranscriber.new(cliConfig)

    local ok, err = obj.transcriber:validate()
    if ok then
      obj.logger:info("✓ Transcriber: " .. obj.transcriber:getName())
      transcriberCreated = true
    else
      Notifier.show("init", "error", "Transcriber validation failed: " .. tostring(err))
      obj.logger:error("WhisperCLI validation failed: " .. tostring(err), true)
      return false
    end
  else
    Notifier.show("init", "error", "Unknown transcriber type: " .. transcriberType)
    obj.logger:error("Unknown transcriber type: " .. transcriberType, true)
    return false
  end

  if not transcriberCreated then
    Notifier.show("init", "error", "Failed to create transcriber")
    obj.logger:error("Failed to create transcriber", true)
    return false
  end

  -- Create Manager
  obj.manager = Manager.new(obj.recorder, obj.transcriber, {
    language = currentLang(),
    tempDir = obj.tempDir,
  })

  -- Set up state change callback for UI updates
  obj.manager.onStateChanged = function(newState, oldState, context)
    if newState == "TRANSCRIBING" then
      -- Entering transcribing state - stop recording session, show transcribing icon
      if obj.timer then obj.timer:stop(); obj.timer = nil; end
      if obj.timeoutTimer then obj.timeoutTimer:stop(); obj.timeoutTimer = nil; end
      obj.startTime = nil
      hideRecordingIndicator()
      updateMenu(obj.icons.transcribing .. " (" .. currentLang() .. ")", "Transcribing...")
    elseif newState == "IDLE" then
      -- Entering idle state - reset everything
      stopRecordingSession()
      resetMenuToIdle()

      -- Handle auto-paste if enabled and we came from TRANSCRIBING (successful completion)
      if oldState == "TRANSCRIBING" and obj.shouldPaste then
        obj.logger:info("Auto-paste enabled, checking conditions...")

        -- Check activity monitoring conditions FIRST (before clipboard check)
        if obj.monitorUserActivity then
          local c = obj.activityCounts
          local hasActivity = (c.keys >= 2) or (c.clicks >= 1) or (c.appSwitches >= 1)

          if hasActivity then
            local summary = getActivitySummary()
            local msg = "⚠️ Auto-paste blocked: User activity detected (" .. summary .. ")\nText is in clipboard - paste manually (⌘V)"
            obj.logger:warn(msg, true)
            hs.alert.show(msg, 10.0)
            obj.shouldPaste = false
            return
          end

          if not isSameAppFocused() then
            local msg = "⚠️ Auto-paste blocked: Application changed during recording\nText is in clipboard - paste manually (⌘V)"
            obj.logger:warn(msg, true)
            hs.alert.show(msg, 10.0)
            obj.shouldPaste = false
            return
          end
        end

        -- All checks passed - perform auto-paste
        -- IMPORTANT: Read clipboard INSIDE timer callback to ensure fresh content
        obj.logger:info("Auto-paste conditions met, pasting...")
        hs.timer.doAfter(obj.autoPasteDelay, function()
          -- Read clipboard NOW (not earlier) to get fresh transcription
          local clipboard = hs.pasteboard.getContents()

          if not clipboard or clipboard == "" then
            obj.logger:warn("No clipboard content to paste")
            return
          end

          local pasteOk, pasteErr = pcall(smartPaste)
          if not pasteOk then
            local errMsg = "❌ Paste failed: " .. tostring(pasteErr) .. "\nText is in clipboard - paste manually (⌘V)"
            obj.logger:error(errMsg, true)
            hs.alert.show(errMsg, 10.0)
          else
            hs.alert.show("✓ Pasted " .. #clipboard .. " chars", 3.0)
          end
        end)

        obj.shouldPaste = false
      end
    end
  end

  -- Ensure temp directory exists
  ensureDir(obj.tempDir)

  -- Create menubar
  if not obj.menubar then
    obj.menubar = hs.menubar.new()
    obj.menubar:setClickCallback(function() obj:toggleTranscribe() end)
  end

  resetMenuToIdle()

  local readyMsg = string.format("WhisperDictation ready: %s + %s",
    obj.recorder:getName(), obj.transcriber:getName())
  obj.logger:info(readyMsg, true)
  Notifier.show("init", "info", readyMsg)

  return true
end

function obj:stop()
  obj.logger:info("Stopping WhisperDictation")

  if obj.menubar then
    obj.menubar:delete()
    obj.menubar = nil
  end
  for _, hk in pairs(obj.hotkeys) do hk:delete() end
  obj.hotkeys = {}
  stopRecordingSession()

  -- Clean up new architecture components
  if obj.recorder and obj.recorder.cleanup then
    obj.recorder:cleanup()
  end
  if obj.transcriber and obj.transcriber.cleanup then
    obj.transcriber:cleanup()
  end
  obj.manager = nil
  obj.recorder = nil
  obj.transcriber = nil

  obj.logger:info("WhisperDictation stopped", true)
end

-- ============================================================================
-- === Hotkey Binding ===
-- ============================================================================

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
    end
  end
  return self
end

return obj
