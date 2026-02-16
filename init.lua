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
-- wd.recordingBackend = "pythonstream"  -- or "sox" for simple recording
-- wd.transcriptionMethod = "whisperkitcli"  -- or "whispercli", "whisperserver", "groq"
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
  recorder = "sox",  -- "sox" or "streaming" (streaming not implemented yet)
  transcriber = "whispercli",  -- "whispercli", "whisperkit", or "whisperserver"

  -- Recorder-specific configs
  sox = {
    soxCmd = "/opt/homebrew/bin/sox",
    audioInputDevice = nil,  -- nil = default device, or "BlackHole 2ch" for tests
    tempDir = nil,  -- nil = use obj.tempDir
  },

  -- Transcriber-specific configs
  whispercli = {
    executable = "/opt/homebrew/bin/whisper-cli",
    modelPath = "/usr/local/whisper/ggml-large-v3.bin",
  },
}

-- OLD ARCHITECTURE (kept as reference, not used)
-- Recording backend selection
obj.recordingBackend = "pythonstream"  -- "sox" or "pythonstream"

-- Transcription method selection
obj.transcriptionMethod = "whisperserver"  -- "whisperkitcli", "whispercli", "whisperserver", "groq"

-- UI settings
obj.showRecordingIndicator = true
obj.chunkAlertDuration = 5.0

-- Auto-stop settings
obj.timeoutSeconds = 1800  -- Auto-stop recording after 30 minutes. Set to nil to disable.

-- Activity monitoring (prevents auto-paste if user was active during recording)
obj.monitorUserActivity = false
obj.autoPasteDelay = 0.1
obj.pasteWithEmacsYank = false

-- Retranscription settings
obj.retranscribeMethod = "whisperkitcli"
obj.retranscribeCount = 10

-- Default hotkeys
obj.defaultHotkeys = {
  toggle = {{"ctrl", "cmd"}, "d"},
  nextLang = {{"ctrl", "cmd"}, "l"},
}

-- ============================================================================
-- === Backend-specific Configuration ===
-- ============================================================================

-- Sox backend (simple recording)
obj.soxConfig = {
  cmd = "/opt/homebrew/bin/sox",
}

-- Python stream backend (continuous recording with VAD)
obj.pythonstreamConfig = {
  pythonExecutable = os.getenv("HOME") .. "/.config/dmg/python3.12/bin/python3",
  port = 12342,
  host = "127.0.0.1",
  serverStartupTimeout = 5.0,
  silenceThreshold = 2.0,
  minChunkDuration = 3.0,
  maxChunkDuration = 600.0,
}

-- Backward compatibility: old code accessed wd.recordingBackends.pythonstream.config.*
obj.recordingBackends = {
  pythonstream = {
    config = obj.pythonstreamConfig,  -- Point to the same config
  },
}

-- ============================================================================
-- === Method-specific Configuration ===
-- ============================================================================

-- WhisperKit CLI method
obj.whisperkitConfig = {
  cmd = "/opt/homebrew/bin/whisperkit-cli",
  model = "large-v3",
}

-- Whisper CLI method (whisper.cpp)
obj.whispercliConfig = {
  cmd = "/opt/homebrew/bin/whisper-cli",
  modelPath = "/usr/local/whisper/ggml-large-v3.bin",
}

-- Whisper Server method
obj.whisperserverConfig = {
  executable = "/path/to/whisper-server",
  modelPath = "/usr/local/whisper/ggml-model.bin",
  host = "127.0.0.1",
  port = "8080",
  startupTimeout = 10,
  curlCmd = "/usr/bin/curl",
}
obj.serverConfig = obj.whisperserverConfig  -- Backward compatibility alias

-- Groq API method
obj.groqConfig = {
  apiKey = nil,  -- Set to your API key or use GROQ_API_KEY env var
  model = "whisper-large-v3",
  timeout = 30,
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

-- NEW ARCHITECTURE components (created in start())
obj.manager = nil  -- Manager instance (replaces recordingManager + transcriptionManager)
obj.recorder = nil  -- IRecorder instance
obj.transcriber = nil  -- ITranscriber instance

-- OLD ARCHITECTURE components (kept as reference, not used)
obj.eventBus = nil
obj.backendInstance = nil
obj.methodInstance = nil
obj.recordingManager = nil
obj.transcriptionManager = nil
obj.chunkAssembler = nil

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

-- Server state (for whisperserver method)
obj.serverProcess = nil
obj.serverStarting = false

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
-- === Event Handlers ===
-- ============================================================================

local function setupEventHandlers()
  -- When audio chunk is ready from backend, start transcription
  obj.eventBus:on("audio:chunk_ready", function(data)
    obj.logger:debug(string.format("Chunk %d ready: %s", data.chunkNum or 1, data.audioFile))
    hs.alert.show(string.format("Chunk %d recorded, transcribing...", data.chunkNum or 1), 2.0)

    -- Start transcription via TranscriptionManager
    obj.transcriptionManager:transcribe(data.audioFile, data.lang)
      :catch(function(err)
        obj.logger:error("Transcription failed: " .. tostring(err))
      end)
  end)

  -- When transcription completes, add to chunk assembler
  obj.eventBus:on("transcription:completed", function(data)
    obj.logger:info("🔥 TRANSCRIPTION COMPLETED EVENT FIRED 🔥")
    obj.logger:info("  audioFile: " .. (data.audioFile or "NIL"))
    obj.logger:info("  text: " .. (data.text or "NIL"))
    obj.logger:info("  lang: " .. (data.lang or "NIL"))

    if not data.audioFile then
      obj.logger:error("❌ CRITICAL: audioFile is nil in transcription:completed event!", true)
      hs.alert.show("❌ BUG: No audioFile in transcription event", 10.0)
      return
    end

    if not data.text then
      obj.logger:error("❌ CRITICAL: text is nil in transcription:completed event!", true)
      hs.alert.show("❌ BUG: No text in transcription event", 10.0)
      return
    end

    -- Extract chunk number from audio file
    local chunkNum = data.audioFile:match("_chunk_(%d+)%.wav$")
    chunkNum = chunkNum and tonumber(chunkNum) or 1

    obj.logger:info(string.format("  Extracted chunk number: %d", chunkNum))
    obj.logger:info(string.format("  Adding to ChunkAssembler: chunk %d, %d chars", chunkNum, #data.text))

    hs.alert.show(string.format("Chunk %d: %s", chunkNum, data.text:sub(1, 100)), obj.chunkAlertDuration)

    obj.chunkAssembler:addChunk(chunkNum, data.text, data.audioFile)

    obj.logger:info(string.format("  ChunkAssembler now has %d chunks", obj.chunkAssembler:getChunkCount()))
  end)

  -- When recording stops, notify chunk assembler
  obj.eventBus:on("recording:stopped", function()
    obj.logger:debug("Recording stopped event received")
    obj.chunkAssembler:recordingStopped()
    stopRecordingSession()
  end)

  -- When all transcriptions complete, handle final text
  obj.eventBus:on("transcription:all_complete", function(data)
    local fullText = data.text
    local charCount = #fullText
    local chunkCount = data.chunkCount or 1

    obj.logger:info(string.format("🎉 All transcriptions complete: %d chunks, %d chars", chunkCount, charCount), true)
    hs.alert.show(string.format("✓ Transcription complete: %d chars", charCount), 5.0)

    -- Save to .txt file (find most recent .wav file)
    local recordings = getRecentRecordings(1)
    if #recordings > 0 then
      local txtFile = recordings[1].path:gsub("%.wav$", ".txt")
      local f, err = io.open(txtFile, "w")
      if f then
        f:write(fullText)
        f:close()
        obj.logger:debug("Transcript written to file: " .. txtFile)
      else
        obj.logger:warn("Failed to save transcription file: " .. tostring(err))
      end
    end

    -- Handle callback if provided
    if obj.transcriptionCallback then
      local ok, callbackErr = pcall(obj.transcriptionCallback, fullText)
      if not ok then
        obj.logger:error("Callback error: " .. tostring(callbackErr))
      end
      obj.transcriptionCallback = nil

      local message = chunkCount == 1
        and string.format("Transcription complete: %d characters", charCount)
        or string.format("Transcription complete: %d chunks, %d characters", chunkCount, charCount)
      hs.alert.show(message, 5.0)
      obj.logger:info(message)
      resetMenuToIdle()
      return
    end

    -- Copy to clipboard
    local ok, err = pcall(hs.pasteboard.setContents, fullText)
    if not ok then
      obj.logger:error("Failed to copy to clipboard: " .. tostring(err), true)
      resetMenuToIdle()
      return
    end

    local message = chunkCount == 1
      and string.format("Transcription complete: %d characters", charCount)
      or string.format("Transcription complete: %d chunks, %d characters", chunkCount, charCount)

    -- Handle auto-paste if enabled
    if obj.shouldPaste then
      local c = obj.activityCounts
      local hasActivity = (c.keys >= 2) or (c.clicks >= 1) or (c.appSwitches >= 1)

      if obj.monitorUserActivity and hasActivity then
        local summary = getActivitySummary()
        local msg = "⚠️ Auto-paste blocked: User activity detected (" .. summary .. ")\nText is in clipboard - paste manually (⌘V)"
        obj.logger:warn(msg, true)
        hs.alert.show(msg, 10.0)  -- SHOW ALERT - not silent!
      elseif obj.monitorUserActivity and not isSameAppFocused() then
        local msg = "⚠️ Auto-paste blocked: Application changed during recording\nText is in clipboard - paste manually (⌘V)"
        obj.logger:warn(msg, true)
        hs.alert.show(msg, 10.0)  -- SHOW ALERT - not silent!
      else
        obj.logger:info(obj.icons.clipboard .. " Copied to clipboard (" .. charCount .. " chars) - pasting...", true)
        hs.timer.doAfter(obj.autoPasteDelay, function()
          local pasteOk, pasteErr = pcall(smartPaste)
          if not pasteOk then
            local errMsg = "❌ Paste failed: " .. tostring(pasteErr) .. "\nText is in clipboard - paste manually (⌘V)"
            obj.logger:error(errMsg, true)
            hs.alert.show(errMsg, 10.0)
          else
            hs.alert.show("✓ Pasted " .. charCount .. " chars", 3.0)
          end
        end)
      end
      obj.shouldPaste = false
    else
      obj.logger:info(obj.icons.clipboard .. " Copied to clipboard (" .. charCount .. " chars)", true)
    end

    hs.alert.show(message, 5.0)
    obj.logger:info(message)
    resetMenuToIdle()
  end)

  -- Handle recording errors
  obj.eventBus:on("recording:error", function(data)
    obj.logger:error("Recording error: " .. tostring(data.error), true)

    -- Only stop recording if error occurred DURING recording
    -- Don't stop if error was from trying to start when already running
    if data.context ~= "start" then
      stopRecordingSession()
      resetMenuToIdle()
    end
    -- For start errors, just log - don't disrupt active recording
  end)

  -- Handle transcription errors
  obj.eventBus:on("transcription:error", function(data)
    local errorMsg = "❌ Transcription error: " .. tostring(data.error)
    obj.logger:error(errorMsg)
    hs.alert.show(errorMsg, 10.0)  -- Show prominently for 10 seconds
  end)
end

-- ============================================================================
-- === Recent Recordings ===
-- ============================================================================

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
-- === Retranscribe ===
-- ============================================================================

local function retranscribe(audioFile, lang, callback)
  -- Create temporary method instance for retranscription
  local MethodFactory = dofile(spoonPath .. "lib/method_factory.lua")

  local methodConfig = {}
  if obj.retranscribeMethod == "whisperkitcli" then
    methodConfig = obj.whisperkitConfig
  elseif obj.retranscribeMethod == "whispercli" then
    methodConfig = obj.whispercliConfig
  elseif obj.retranscribeMethod == "whisperserver" then
    methodConfig = obj.whisperserverConfig
  elseif obj.retranscribeMethod == "groq" then
    methodConfig = obj.groqConfig
  end

  local retransMethod, err = MethodFactory.create(obj.retranscribeMethod, methodConfig, spoonPath)

  if not retransMethod then
    obj.logger:error("Failed to create retranscription method: " .. tostring(err), true)
    return
  end

  obj.logger:info(obj.icons.transcribing .. " Re-transcribing with " .. obj.retranscribeMethod .. " (" .. lang .. ")...", true)
  updateMenu(obj.icons.idle .. " (" .. lang .. " T)", "Re-transcribing...")

  retransMethod:transcribe(audioFile, lang)
    :andThen(
      function(text)
        -- Save to .txt file
        local txtFile = audioFile:gsub("%.wav$", ".txt")
        local f = io.open(txtFile, "w")
        if f then
          f:write(text)
          f:close()
        end

        if callback then
          local ok, callbackErr = pcall(callback, text)
          if not ok then
            obj.logger:error("Callback error: " .. tostring(callbackErr))
          end
          hs.alert.show(string.format("Re-transcription complete: %d characters", #text), 5.0)
        else
          pcall(hs.pasteboard.setContents, text)
          obj.logger:info(obj.icons.clipboard .. " Re-transcription copied to clipboard (" .. #text .. " chars)", true)
        end

        resetMenuToIdle()
      end,
      function(err)
        obj.logger:error("Re-transcription failed: " .. tostring(err), true)
        resetMenuToIdle()
      end
    )
end

local function showRetranscribeChooser(callback)
  local recordings = getRecentRecordings(obj.retranscribeCount)
  if #recordings == 0 then
    obj.logger:warn("No recent recordings found in " .. obj.tempDir, true)
    return
  end

  local choices = {}
  for _, rec in ipairs(recordings) do
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

-- ============================================================================
-- === Whisper Server Management (for whisperserver method) ===
-- ============================================================================

local function getServerModelPath()
  if hs.fs.attributes(obj.whisperserverConfig.modelPath) then
    return obj.whisperserverConfig.modelPath
  end
  return nil
end

function obj:isServerRunning()
  local serverUrl = string.format("http://%s:%s", obj.whisperserverConfig.host, obj.whisperserverConfig.port)
  local ok = os.execute(string.format(
    "%s -s -o /dev/null --connect-timeout 1 %s 2>/dev/null",
    obj.whisperserverConfig.curlCmd, serverUrl
  ))
  if ok ~= true and obj.serverProcess then
    if not obj.serverProcess:isRunning() then
      obj.serverProcess = nil
    end
  end
  return ok == true
end

function obj:startServer(callback)
  if self:isServerRunning() then
    if self.serverProcess then
      self.logger:info("Whisper server already running (managed by this spoon)")
    else
      self.logger:info("Whisper server already running (external process)")
    end
    if callback then callback(true, nil) end
    return true, nil
  end

  if self.serverStarting then
    hs.alert.show("Server already starting...")
    self.logger:info("Server startup already in progress")
    return false, "Server already starting"
  end

  local modelPath = getServerModelPath()
  if not modelPath then
    local err = "Whisper model not found at " .. obj.whisperserverConfig.modelPath
    self.logger:error(err, true)
    if callback then callback(false, err) end
    return false, err
  end

  if not hs.fs.attributes(obj.whisperserverConfig.executable) then
    local err = "Whisper server executable not found at " .. obj.whisperserverConfig.executable
    self.logger:error(err, true)
    if callback then callback(false, err) end
    return false, err
  end

  local args = {
    "-m", modelPath,
    "--host", obj.whisperserverConfig.host,
    "--port", obj.whisperserverConfig.port,
  }

  self.logger:info("Starting whisper server with model " .. modelPath)
  self.serverProcess = hs.task.new(obj.whisperserverConfig.executable, function(exitCode, stdOut, stdErr)
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

  self.serverStarting = true
  hs.alert.show("Starting whisper server...")

  local pollInterval = 0.5
  local maxAttempts = math.ceil(obj.whisperserverConfig.startupTimeout / pollInterval)
  local attempts = 0

  local pollTimer
  pollTimer = hs.timer.doEvery(pollInterval, function()
    attempts = attempts + 1
    if self:isServerRunning() then
      pollTimer:stop()
      self.serverStarting = false
      self.logger:info("Whisper server ready")
      hs.alert.show("Whisper server ready")
      if callback then callback(true, nil) end
    elseif attempts >= maxAttempts then
      pollTimer:stop()
      self.serverStarting = false
      local errMsg = "Server failed to start after " .. obj.whisperserverConfig.startupTimeout .. " seconds"
      self.logger:error(errMsg, true)
      if callback then callback(false, errMsg) end
    elseif not self.serverProcess or not self.serverProcess:isRunning() then
      pollTimer:stop()
      self.serverStarting = false
      local errMsg = "Server process exited unexpectedly"
      self.logger:error(errMsg, true)
      if callback then callback(false, errMsg) end
    end
  end)

  return true, nil
end

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

function obj:transcribeLatestAgain(callback)
  showRetranscribeChooser(callback)
  return self
end

-- ============================================================================
-- === Start/Stop ===
-- ============================================================================

function obj:start()
  obj.logger:info("Starting WhisperDictation v2 (New Architecture)")

  -- Load new architecture components
  local Manager = dofile(spoonPath .. "core_v2/manager.lua")
  local Notifier = dofile(spoonPath .. "lib/notifier.lua")

  -- Create recorder based on config
  local recorderType = obj.config.recorder or "sox"
  if recorderType == "sox" then
    local SoxRecorder = dofile(spoonPath .. "recorders/sox_recorder.lua")
    local soxConfig = obj.config.sox or {}
    soxConfig.tempDir = soxConfig.tempDir or obj.tempDir
    obj.recorder = SoxRecorder.new(soxConfig)
  else
    local errorMsg = "Unknown recorder type: " .. recorderType
    obj.logger:error(errorMsg, true)
    Notifier.show("init", "error", errorMsg)
    return false
  end

  -- Create transcriber based on config
  local transcriberType = obj.config.transcriber or "whispercli"
  if transcriberType == "whispercli" then
    local WhisperCLITranscriber = dofile(spoonPath .. "transcribers/whispercli_transcriber.lua")
    local cliConfig = obj.config.whispercli or {}
    obj.transcriber = WhisperCLITranscriber.new(cliConfig)
  elseif transcriberType == "whisperkit" then
    local WhisperKitTranscriber = dofile(spoonPath .. "transcribers/whisperkit_transcriber.lua")
    local kitConfig = obj.config.whisperkit or {}
    obj.transcriber = WhisperKitTranscriber.new(kitConfig)
  elseif transcriberType == "whisperserver" then
    local WhisperServerTranscriber = dofile(spoonPath .. "transcribers/whisperserver_transcriber.lua")
    local serverConfig = obj.config.whisperserver or {}
    obj.transcriber = WhisperServerTranscriber.new(serverConfig)
  else
    local errorMsg = "Unknown transcriber type: " .. transcriberType
    obj.logger:error(errorMsg, true)
    Notifier.show("init", "error", errorMsg)
    return false
  end

  -- Validate recorder
  local ok, err = obj.recorder:validate()
  if not ok then
    local errorMsg = "Recorder validation failed: " .. tostring(err)
    obj.logger:error(errorMsg, true)
    Notifier.show("init", "error", errorMsg)
    return false
  end
  obj.logger:info("✓ Recorder: " .. obj.recorder:getName())

  -- Validate transcriber
  ok, err = obj.transcriber:validate()
  if not ok then
    local errorMsg = "Transcriber validation failed: " .. tostring(err)
    obj.logger:error(errorMsg, true)
    Notifier.show("init", "error", errorMsg)
    return false
  end
  obj.logger:info("✓ Transcriber: " .. obj.transcriber:getName())

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
    elseif name == "retranscribe" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], "Retranscribe latest audio [Audio]", function() obj:transcribeLatestAgain() end)
      obj.logger:debug("Bound hotkey: retranscribe to " .. table.concat(spec[1], "+") .. "+" .. spec[2])
    end
  end
  return self
end

return obj
