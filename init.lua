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

local obj = {}
obj.__index = obj

-- === Config ===
obj.modelPath = "/usr/local/whisper/ggml-large-v3.bin"
obj.tempDir = "/tmp/whisper_dict"
obj.transcriptFile = obj.tempDir .. "/transcript"
obj.recordCmd = "/opt/homebrew/bin/sox"
obj.whisperCmd = "/opt/homebrew/bin/whisper-cli"
obj.languages = {"en"}
obj.langIndex = 1
obj.defaultHotkeys = {
  toggle = {{"ctrl", "cmd"}, "d"},
  nextLang = {{"ctrl", "cmd"}, "l"},
}

-- === Internal ===
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

-- Utility method: show alert and print to console
function obj:message(msg, isError)
  if isError then
    hs.alert.show("❌ " .. msg)
    print("[WhisperDictation][ERROR] " .. msg)
  else
    hs.alert.show(msg)
    print("[WhisperDictation] " .. msg)
  end
end


local function transcribe(audioFile)
  obj:message("⏳ Transcribing (" .. currentLang() .. ")...")
  updateMenu("💤", "Idle")

  -- Sanity checks

  local args = {
    "--model", obj.modelPath,
    "--file", audioFile,
    "--output-txt", 
    "--output-file", obj.transcriptFile,
    "--language", currentLang(),
  }

  print("[WhisperDictation] Running command:", obj.whisperCmd, table.concat(args, " "))

  local task = hs.task.new(obj.whisperCmd, function(exitCode, stdOut, stdErr)
    print("[WhisperDictation] whisper-cli exit code:", exitCode)
    if stdErr and #stdErr > 0 then
      print("[WhisperDictation] stderr:\n" .. stdErr)
    end

    if exitCode ~= 0 then
      obj:message("whisper-cli failed (exit " .. tostring(exitCode) .. ")", true)
      return
    end

    local f, err = io.open(obj.transcriptFile .. ".txt", "r")
    if not f then
      obj:message("Could not open transcript file: " .. tostring(err), true)
      return
    end

    local text = f:read("*a") or ""
    f:close()

    if text == "" then
      obj:message("Empty transcript output", true)
      return
    end

    local ok, errPB = pcall(hs.pasteboard.setContents, text)
    if not ok then
      obj:message("Failed to copy to clipboard: " .. tostring(errPB), true)
      return
    end

    obj:message("📋 Copied to clipboard (" .. #text .. " chars)")
  end, args)

  if not task then
    obj:message("Failed to create hs.task for whisper-cli", true)
    return
  end

  local ok, err = pcall(function() task:start() end)
  if not ok then
    obj:message("Failed to start whisper-cli: " .. tostring(err), true)
  end
end

local function toggleRecord()
  if obj.recTask == nil then
    ensureDir(obj.tempDir)
    local audioFile = timestampedFile(obj.tempDir, currentLang(), "wav")
    hs.alert.show("🎙️ Recording (" .. currentLang() .. ")")
    obj.recTask = hs.task.new(obj.recordCmd, nil, {"-d", audioFile})
    obj.recTask:start()
    obj.currentAudioFile = audioFile
    startElapsedTimer()
  else
    hs.alert.show("🛑 Stopped")
    obj.recTask:terminate()
    obj.recTask = nil
    stopElapsedTimer()
    updateMenu("💤", "Idle (" .. currentLang() .. ")")
    if obj.currentAudioFile then
      transcribe(obj.currentAudioFile)
      obj.currentAudioFile = nil
    end
  end
end

local function nextLanguage()
  obj.langIndex = (obj.langIndex % #obj.languages) + 1
  local lang = currentLang()
  hs.alert.show("🌐 Language: " .. lang)
  updateMenu("💤", "Idle (" .. lang .. ")")
end

-- === Public API ===
function obj:start()
  errorSuffix = " whisperDictation not started"
  if not hs.fs.attributes(obj.modelPath) then
    obj:message("Model not found: " .. obj.modelPath .. errorSuffix, true)
    return
  end

  if not hs.fs.attributes(obj.whisperCmd) then
    obj:message("whisper-cli not found: " .. obj.whisperCmd .. errorSuffix, true)
    return
  end
  if not hs.fs.attributes(obj.recordCmd) then
    obj:message("recording command not found: " .. obj.recordCmd .. errorSuffix, true)
    return
  end

  ensureDir(obj.tempDir)
  
  if not obj.menubar then
    obj.menubar = hs.menubar.new()
    obj.menubar:setClickCallback(toggleRecord)
  end

  updateMenu("💤", "Idle (" .. currentLang() .. ")")
  hs.alert.show("WhisperDictation ready (" .. currentLang() .. ")")
end

function obj:stop()
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
  hs.alert.show("WhisperDictation stopped")
end

function obj:bindHotKeys(mapping)
  local map = hs.fnutils.copy(mapping or obj.defaultHotkeys)
  for name, spec in pairs(map) do
    if obj.hotkeys[name] then obj.hotkeys[name]:delete() end
    if name == "toggle" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], toggleRecord)
    elseif name == "nextLang" then
      obj.hotkeys[name] = hs.hotkey.bind(spec[1], spec[2], nextLanguage)
    end
  end
  return self
end

return obj
