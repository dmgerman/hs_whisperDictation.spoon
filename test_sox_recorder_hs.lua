-- Test SoxRecorder in Hammerspoon
-- Run with: hs test_sox_recorder_hs.lua

local spoonPath = "/Users/dmg/.hammerspoon/Spoons/hs_whisperDictation.spoon/"

-- Change to spoon directory so relative paths work
local oldDir = hs.execute("pwd"):gsub("\n", "")
os.execute("cd " .. spoonPath)

-- Load components
local SoxRecorder = dofile(spoonPath .. "recorders/sox_recorder.lua")
local MockTranscriber = dofile(spoonPath .. "tests/mocks/mock_transcriber.lua")
local Manager = dofile(spoonPath .. "core_v2/manager.lua")

print("\n=== Testing SoxRecorder in Hammerspoon ===\n")

-- Test 1: Basic loading
print("Test 1: SoxRecorder loads")
local recorder = SoxRecorder.new({
  soxCmd = "/opt/homebrew/bin/sox",
  tempDir = "/tmp/test_whisper"
})
print("  ✓ SoxRecorder created")
print("  Name:", recorder:getName())
print("  isRecording:", recorder:isRecording())

-- Test 2: Validation
print("\nTest 2: Validation")
local success, err = recorder:validate()
if success then
  print("  ✓ Sox validated successfully")
else
  print("  ✗ Sox validation failed:", err)
end

-- Test 3: Integration with Manager
print("\nTest 3: Manager integration")
local transcriber = MockTranscriber.new()
local manager = Manager.new(recorder, transcriber, {
  language = "en",
  tempDir = "/tmp/test_whisper"
})
print("  ✓ Manager created")
print("  Manager state:", manager.state)

-- Test 4: Start recording (brief test)
print("\nTest 4: Start recording (will auto-stop after 2 seconds)")
success, err = manager:startRecording("en")
if success then
  print("  ✓ Recording started")
  print("  Manager state:", manager.state)
  print("  Recorder isRecording:", recorder:isRecording())

  -- Wait 2 seconds then stop
  hs.timer.doAfter(2, function()
    print("\nTest 5: Stop recording")
    local stopSuccess, stopErr = manager:stopRecording()
    if stopSuccess then
      print("  ✓ Recording stopped")
      print("  Manager state:", manager.state)

      -- Wait a bit for transcription to complete
      hs.timer.doAfter(1, function()
        print("\nTest 6: Check results")
        print("  Manager state:", manager.state)
        print("  Pending transcriptions:", manager.pendingTranscriptions)

        -- Check clipboard
        local clipboard = hs.pasteboard.getContents()
        if clipboard and clipboard:match("Transcribed:") then
          print("  ✓ Clipboard contains transcription:", clipboard)
        else
          print("  Clipboard:", clipboard or "empty")
        end

        print("\n=== All tests completed ===\n")
      end)
    else
      print("  ✗ Failed to stop:", stopErr)
    end
  end)
else
  print("  ✗ Failed to start:", err)
end

print("\n(Waiting for async operations to complete...)\n")
