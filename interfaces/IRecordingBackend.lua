--- IRecordingBackend Interface
-- All recording backends must implement this interface
--
-- Recording backends handle audio capture and chunk generation.
-- They must emit events through the eventBus for chunk availability.

local IRecordingBackend = {}

--- Start recording audio
-- @param config (table): Recording configuration
--   - outputDir (string): Directory to save audio chunks
--   - filenamePrefix (string): Prefix for chunk filenames
--   - lang (string): Language code (e.g., "en", "ja")
--   - eventBus (EventBus): Event bus for emitting events
--   - chunkDuration (number): Duration of each chunk in seconds (optional)
-- @return (Promise): Resolves when recording starts, rejects on error
function IRecordingBackend:startRecording(config)
  error("Not implemented: startRecording")
end

--- Stop recording audio
-- @return (Promise): Resolves when recording stops, rejects on error
function IRecordingBackend:stopRecording()
  error("Not implemented: stopRecording")
end

--- Check if currently recording
-- @return (boolean): true if recording
function IRecordingBackend:isRecording()
  error("Not implemented: isRecording")
end

--- Get display text for menubar
-- @param lang (string): Language code
-- @return (string): Display text (e.g., "🎙️ Recording (en)")
function IRecordingBackend:getDisplayText(lang)
  error("Not implemented: getDisplayText")
end

--- Validate backend is available and configured
-- @return (boolean, string?): success, error message if failed
function IRecordingBackend:validate()
  error("Not implemented: validate")
end

--[[
Events that backends MUST emit:

1. "audio:chunk_ready" - When a new audio chunk is available
   Data: {
     chunkNum = number,      -- Sequential chunk number starting at 1
     audioFile = string,     -- Path to the audio file
     lang = string,          -- Language code
   }

2. "audio:chunk_error" - When chunk recording fails
   Data: {
     chunkNum = number,      -- Chunk number that failed
     error = string,         -- Error message
   }
]]

return IRecordingBackend
