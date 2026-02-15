#!/usr/bin/env lua
--- Generate transcripts for audio files in tests/data
-- Uses WhisperServer to transcribe audio and save results

package.path = package.path .. ";./?.lua;./?/init.lua"

local ServerManager = require("tests.helpers.server_manager")
local WhisperServerMethod = require("methods.whisper_server_method")
local Promise = require("lib.promise")

-- Configuration
local dataDir = "tests/data"
local audioDir = dataDir .. "/audio/recordings"
local transcriptDir = dataDir .. "/transcripts"

-- Ensure transcript directory exists
os.execute("mkdir -p " .. transcriptDir)

-- Ensure server is running
print("Checking WhisperServer...")
local running, msg = ServerManager.ensure()
if not running then
  print("ERROR: " .. (msg or "Failed to start WhisperServer"))
  print("Please start whisper-server manually and try again")
  os.exit(1)
end

print("✓ WhisperServer is running")

-- Create transcription method
local method = WhisperServerMethod.new({
  host = "127.0.0.1",
  port = 8080,
})

-- Get all audio files
print("\nScanning for audio files in " .. audioDir .. "...")
local handle = io.popen("ls " .. audioDir .. "/*.wav 2>/dev/null")
if not handle then
  print("ERROR: Failed to scan audio directory")
  os.exit(1)
end

local audioFiles = {}
for file in handle:lines() do
  table.insert(audioFiles, file)
end
handle:close()

if #audioFiles == 0 then
  print("No audio files found in " .. audioDir)
  os.exit(0)
end

print(string.format("Found %d audio files", #audioFiles))

-- Transcribe each file
local transcribed = 0
local failed = 0

for i, audioFile in ipairs(audioFiles) do
  local basename = audioFile:match("([^/]+)%.wav$")
  local transcriptFile = transcriptDir .. "/" .. basename .. ".txt"

  -- Check if transcript already exists
  local exists = io.open(transcriptFile, "r")
  if exists then
    exists:close()
    print(string.format("[%d/%d] SKIP %s (transcript exists)", i, #audioFiles, basename))
  else
    print(string.format("[%d/%d] Transcribing %s...", i, #audioFiles, basename))

    -- Extract language from filename
    local lang = basename:match("^([^-]+)%-") or "en"

    -- Transcribe
    local success = false
    local text = nil

    method:transcribe(audioFile, lang):next(function(result)
      success = true
      text = result
    end):catch(function(err)
      success = false
      print("  ERROR: " .. tostring(err))
    end)

    if success and text then
      -- Save transcript
      local f = io.open(transcriptFile, "w")
      if f then
        f:write(text)
        f:close()
        print("  ✓ Saved transcript (" .. #text .. " chars)")
        transcribed = transcribed + 1
      else
        print("  ERROR: Failed to write transcript file")
        failed = failed + 1
      end
    else
      failed = failed + 1
    end
  end
end

print(string.format("\nDone! Transcribed: %d, Failed: %d, Skipped: %d",
  transcribed,
  failed,
  #audioFiles - transcribed - failed
))

os.exit(failed > 0 and 1 or 0)
