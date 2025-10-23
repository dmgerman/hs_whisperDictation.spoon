--- === WhisperDictation ===
---
--- Toggle local Whisper-based dictation with menubar indicator.
--- Records from mic via `sox`, transcribes via whisper-cli, copies text to clipboard.
---
--- Features:
--- • Dynamic filename with timestamp
--- • Elapsed time indicator in menubar during recording
--- • Multiple languages (--language option to whisper-cli)
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
--      whisper-cli
--      a local model for whisper-cli

local obj = {}
obj.__index = obj

obj.name = "WhisperDictation"
obj.version = "0.9"
obj.author = "dmg"
obj.license = "MIT"

-- === Config ===
obj.model = "large-v3"
obj.tempDir = "/tmp/whisper_dict"
obj.transcriptFile = obj.tempDir .. "/transcript"
obj.recordCmd = "/opt/homebrew/bin/sox"
obj.whisperCmd = "/opt/homebrew/bin/whisperkit-cli"
obj.languages = {"en"}
obj.langIndex = 1
obj.defaultHotkeys = {
  toggle = {{"ctrl", "cmd"}, "d"},
  nextLang = {{"ctrl", "cmd"}, "l"},
}

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
    local icon = level == self.levels.ERROR and "❌" or "ℹ️"
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

local function updateElapsed()
  if obj.startTime then
    local elapsed = os.difftime(os.time(), obj.startTime)
    updateMenu(string.format("🎙️ %ds (%s)", elapsed, currentLang()), "Recording...")
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



local function transcribe(audioFile)
  obj.logger:info("⏳ Transcribing (" .. currentLang() .. ")...", true)
  updateMenu("💤", "Idle")

  local args = {
    "transcribe",
    "--model=" .. obj.model,
    "--audio-path=" .. audioFile,
    "--language=" .. currentLang(),
  }

  obj.logger:debug("Running command: " .. obj.whisperCmd .. " " .. table.concat(args, " "))

  local task = hs.task.new(obj.whisperCmd, function(exitCode, stdOut, stdErr)
    obj.logger:debug("whisperkit-cli exit code: " .. tostring(exitCode))
    if stdErr and #stdErr > 0 then
      obj.logger:warn("whisperkit-cli stderr:\n" .. stdErr)
    end

    if exitCode ~= 0 then
      obj.logger:error("whisperkit-cli failed (exit " .. tostring(exitCode) .. ")", true)
      return
    end

    local text = stdOut or ""
    if text == "" then
      obj.logger:error("Empty transcript output", true)
      return
    end

    -- Write transcript to file with same name but .txt extension
    local outputFile = audioFile:gsub("%.wav$", ".txt")
    local f, err = io.open(outputFile, "w")
    if not f then
      obj.logger:error("Could not open transcript file for writing: " .. tostring(err), true)
      return
    end

    f:write(text)
    f:close()
    obj.logger:debug("Transcript written to file: " .. outputFile)

    local ok, errPB = pcall(hs.pasteboard.setContents, text)
    if not ok then
      obj.logger:error("Failed to copy to clipboard: " .. tostring(errPB), true)
      return
    end

    obj.logger:info("📋 Copied to clipboard (" .. #text .. " chars)", true)
  end, args)

  if not task then
    obj.logger:error("Failed to create hs.task for whisperkit-cli", true)
    return
  end

  local ok, err = pcall(function() task:start() end)
  if not ok then
    obj.logger:error("Failed to start whisperkit-cli: " .. tostring(err), true)
  end
end

local function toggleRecord()
  if obj.recTask == nil then
    ensureDir(obj.tempDir)
    local audioFile = timestampedFile(obj.tempDir, currentLang(), "wav")
    obj.logger:info("🎙️ Recording started (" .. currentLang() .. ")", true)
    obj.logger:debug("Recording to file: " .. audioFile)
    obj.recTask = hs.task.new(obj.recordCmd, nil, {"-d", audioFile})
    obj.recTask:start()
    obj.currentAudioFile = audioFile
    startElapsedTimer()
  else
    obj.logger:info("🛑 Recording stopped")
    obj.recTask:terminate()
    obj.recTask = nil
    stopElapsedTimer()
    updateMenu("💤", "Idle (" .. currentLang() .. ")")
    if obj.currentAudioFile then
      obj.logger:info("Processing audio file: " .. obj.currentAudioFile)
      transcribe(obj.currentAudioFile)
      obj.currentAudioFile = nil
    end
  end
end

local function nextLanguage()
  obj.langIndex = (obj.langIndex % #obj.languages) + 1
  local lang = currentLang()
  obj.logger:info("🌐 Language switched to: " .. lang, true)
  updateMenu("💤", "Idle (" .. lang .. ")")
end

-- === Public API ===
function obj:start()
  obj.logger:info("Starting WhisperDictation")
  local errorSuffix = " whisperDictation not started"
  if not hs.fs.attributes(obj.whisperCmd) then
    obj.logger:error("whisperkit-cli not found: " .. obj.whisperCmd .. errorSuffix, true)
    return
  end
  if not hs.fs.attributes(obj.recordCmd) then
    obj.logger:error("recording command not found: " .. obj.recordCmd .. errorSuffix, true)
    return
  end

  ensureDir(obj.tempDir)

  if not obj.menubar then
    obj.menubar = hs.menubar.new()
    obj.menubar:setClickCallback(toggleRecord)
  end

  updateMenu("💤", "Idle (" .. currentLang() .. ")")
  obj.logger:info("WhisperDictation ready (" .. currentLang() .. ")", true)
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
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], nextLanguage)
      obj.logger:debug("Bound hotkey: nextLang to " .. table.concat(spec[1], "+") .. "+" .. spec[2])
    end
  end
  return self
end

return obj
