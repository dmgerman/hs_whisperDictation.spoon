--- === WhisperDictation ===
---
--- Toggle local Whisper-based dictation with menubar indicator.
--- Records from mic via `sox`, transcribes via whisperkit-cli, copies text to clipboard.
---
--- Features:
--- • Dynamic filename with timestamp
--- • Elapsed time indicator in menubar during recording
--- • Multiple languages (--language option to whisperkit-cli)
--- • Clipboard copy and character count summary
---
--- Usage:
-- wd = hs.loadSpoon("hs_whisperDictation")
-- wd.languages = {"en", "ja", "es", "fr"}
-- wd:bindHotKeys({
--    toggle = {dmg_all_keys, "l"},
--    nextLang = {dmg_all_keys, ";"},
-- })
-- wd:start()
--
-- Requirements:
--      sox
--      whisperkit-cli

local obj = {}
obj.__index = obj

obj.name = "WhisperDictation"
obj.version = "0.9"
obj.author = "dmg"
obj.license = "MIT"

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

-- === Config ===
obj.model = "large-v3"
obj.tempDir = "/tmp/whisper_dict"
obj.recordCmd = "/opt/homebrew/bin/sox"
obj.languages = {"en"}
obj.langIndex = 1
obj.defaultHotkeys = {
  toggle = {{"ctrl", "cmd"}, "d"},
  nextLang = {{"ctrl", "cmd"}, "l"},
}

-- === Transcription Methods ===
-- Method-agnostic transcription system. Users select which method to use.
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
    buildCommand = function(self, audioFile, lang)
      local args = {
        "transcribe",
        "--model=" .. self.config.model,
        "--audio-path=" .. audioFile,
        "--language=" .. lang,
      }
      return self.config.cmd, args
    end,
    processOutput = function(self, audioFile, exitCode, stdOut, stdErr)
      if exitCode ~= 0 then
        return false, stdErr or "whisperkit-cli failed"
      end
      local text = stdOut or ""
      if text == "" then
        return false, "Empty transcript output"
      end
      return true, text
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
    buildCommand = function(self, audioFile, lang)
      local args = {
        "-np",
        "--model", self.config.modelPath,
        "--output-txt",
        audioFile,
      }
      return self.config.cmd, args
    end,
    processOutput = function(self, audioFile, exitCode, stdOut, stdErr)
      if exitCode ~= 0 then
        return false, stdErr or "whisper-cli failed"
      end
      -- whisper-cli creates a .txt file with same name as audio (e.g., audio.wav.txt)
      local outputFile = audioFile .. ".txt"
      local f = io.open(outputFile, "r")
      if not f then
        return false, "Could not read transcript file: " .. outputFile
      end
      local text = f:read("*a")
      f:close()
      if not text or text == "" then
        return false, "Empty transcript file"
      end
      return true, text
    end,
  },
}

-- Select active transcription method (default to whispercli)
obj.transcriptionMethod = "whispercli"

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
obj.startTime = nil
obj.currentAudioFile = nil

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
    local elapsed = os.difftime(os.time(), obj.startTime)
    updateMenu(string.format(obj.icons.recording .. " %ds (%s)", elapsed, currentLang()), "Recording...")
  end
end

local function startElapsedTimer()
  obj.startTime = os.time()
  if obj.timer then obj.timer:stop() end
  obj.timer = hs.timer.doEvery(1, updateElapsed)
end

local function stopElapsedTimer()
  if obj.timer then
    obj.timer:stop()
    obj.timer = nil
  end
  obj.startTime = nil
end



local function handleTranscriptionResult(audioFile, exitCode, stdOut, stdErr)
  local method = obj.transcriptionMethods[obj.transcriptionMethod]
  obj.logger:debug(method.displayName .. " exit code: " .. tostring(exitCode))

  if stdErr and #stdErr > 0 then
    obj.logger:warn(method.displayName .. " stderr:\n" .. stdErr)
  end

  -- Use the method's processOutput to handle the result
  local success, text = method:processOutput(audioFile, exitCode, stdOut, stdErr)

  if not success then
    obj.logger:error(text, true)
    resetMenuToIdle()
    return
  end

  -- Save transcript to file (in case method doesn't already create one)
  local outputFile = audioFile:gsub("%.wav$", ".txt")
  local f, err = io.open(outputFile, "w")
  if not f then
    obj.logger:error("Could not open transcript file for writing: " .. tostring(err), true)
    resetMenuToIdle()
    return
  end

  f:write(text)
  f:close()
  obj.logger:debug("Transcript written to file: " .. outputFile)

  local ok, errPB = pcall(hs.pasteboard.setContents, text)
  if not ok then
    obj.logger:error("Failed to copy to clipboard: " .. tostring(errPB), true)
    resetMenuToIdle()
    return
  end

  obj.logger:info(obj.icons.clipboard .. " Copied to clipboard (" .. #text .. " chars)", true)
  resetMenuToIdle()
end

local function transcribe(audioFile)
  local method = obj.transcriptionMethods[obj.transcriptionMethod]
  if not method then
    obj.logger:error("Unknown transcription method: " .. obj.transcriptionMethod, true)
    resetMenuToIdle()
    return
  end

  obj.logger:info(obj.icons.transcribing .. " Transcribing (" .. currentLang() .. ")...", true)
  updateMenu(obj.icons.idle .. " (" .. currentLang() .. " T)", "Transcribing...")

  local cmd, args = method:buildCommand(audioFile, currentLang())
  obj.logger:info("Running: " .. cmd .. " " .. table.concat(args, " "))

  local task = hs.task.new(cmd, function(exitCode, stdOut, stdErr)
    handleTranscriptionResult(audioFile, exitCode, stdOut, stdErr)
  end, args)

  if not task then
    obj.logger:error("Failed to create hs.task for " .. method.displayName, true)
    resetMenuToIdle()
    return
  end

  local ok, err = pcall(function() task:start() end)
  if not ok then
    obj.logger:error("Failed to start " .. method.displayName .. ": " .. tostring(err), true)
    resetMenuToIdle()
  end
end

local function toggleRecord()
  if obj.recTask == nil then
    ensureDir(obj.tempDir)
    local audioFile = timestampedFile(obj.tempDir, currentLang(), "wav")
    obj.logger:info(obj.icons.recording .. " Recording started (" .. currentLang() .. ") - " .. audioFile, true)
    obj.logger:info("Running: " .. obj.recordCmd .. " -d " .. audioFile)
    obj.recTask = hs.task.new(obj.recordCmd, nil, {"-d", audioFile})

    if not obj.recTask then
      obj.logger:error("Failed to create recording task", true)
      resetMenuToIdle()
      return
    end

    local ok, err = pcall(function() obj.recTask:start() end)
    if not ok then
      obj.logger:error("Failed to start recording: " .. tostring(err), true)
      obj.recTask = nil
      resetMenuToIdle()
      return
    end

    obj.currentAudioFile = audioFile
    startElapsedTimer()
  else
    obj.logger:info(obj.icons.stopped .. " Recording stopped")
    obj.recTask:terminate()
    obj.recTask = nil
    stopElapsedTimer()
    resetMenuToIdle()
    if obj.currentAudioFile then
      if not hs.fs.attributes(obj.currentAudioFile) then
        obj.logger:error("Recording file was not created: " .. obj.currentAudioFile, true)
        obj.currentAudioFile = nil
        return
      end
      obj.logger:info("Processing audio file: " .. obj.currentAudioFile)
      transcribe(obj.currentAudioFile)
      obj.currentAudioFile = nil
    end
  end
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

-- === Public API ===
function obj:start()
  obj.logger:info("Starting WhisperDictation")
  local errorSuffix = " WhisperDictation not started"

  -- Validate recording command
  if not hs.fs.attributes(obj.recordCmd) then
    obj.logger:error("recording command not found: " .. obj.recordCmd .. errorSuffix, true)
    return
  end

  -- Validate transcription method
  local method = obj.transcriptionMethods[obj.transcriptionMethod]
  if not method then
    obj.logger:error("Unknown transcription method: " .. obj.transcriptionMethod .. errorSuffix, true)
    return
  end

  if not method:validate() then
    obj.logger:error(method.displayName .. " not found: " .. method.config.cmd .. errorSuffix, true)
    return
  end

  ensureDir(obj.tempDir)

  if not obj.menubar then
    obj.menubar = hs.menubar.new()
    obj.menubar:setClickCallback(toggleRecord)
  end

  resetMenuToIdle()
  obj.logger:info("WhisperDictation ready using " .. method.displayName .. " (" .. currentLang() .. ")", true)
end

function obj:stop()
  obj.logger:info("Stopping WhisperDictation")
  if obj.menubar then
    obj.menubar:delete()
    obj.menubar = nil
  end
  for _, hk in pairs(obj.hotkeys) do hk:delete() end
  obj.hotkeys = {}
  if obj.recTask then
    obj.recTask:terminate()
    obj.recTask = nil
  end
  stopElapsedTimer()
  obj.logger:info("WhisperDictation stopped", true)
end

function obj:bindHotKeys(mapping)
  obj.logger:debug("Binding hotkeys")
  local map = hs.fnutils.copy(mapping or obj.defaultHotkeys)
  for name, spec in pairs(map) do
    if obj.hotkeys[name] then obj.hotkeys[name]:delete() end
    if name == "toggle" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], toggleRecord)
      obj.logger:debug("Bound hotkey: toggle to " .. table.concat(spec[1], "+") .. "+" .. spec[2])
    elseif name == "nextLang" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], showLanguageChooser)
      obj.logger:debug("Bound hotkey: nextLang to " .. table.concat(spec[1], "+") .. "+" .. spec[2])
    end
  end
  return self
end

return obj
