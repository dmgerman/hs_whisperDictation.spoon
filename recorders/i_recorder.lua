--- IRecorder - Interface for audio recording implementations
--- All recorders must implement this interface
---
--- @module IRecorder

local IRecorder = {}
IRecorder.__index = IRecorder

--- Create a new IRecorder instance
--- This is an abstract interface and should not be instantiated directly
---
--- @return table IRecorder instance
function IRecorder.new()
  local self = setmetatable({}, IRecorder)
  return self
end

--- Start recording audio
--- Implementations should call onChunk for each audio chunk produced
--- and onError if an error occurs during recording
---
--- @param config table Configuration for recording (outputDir, lang, etc.)
--- @param onChunk function Callback invoked for each chunk: onChunk(audioFile, chunkNum, isFinal)
--- @param onError function Callback invoked on error: onError(errorMessage)
--- @return boolean success True if recording started successfully
--- @return string|nil error Error message if failed, nil if successful
function IRecorder:startRecording(config, onChunk, onError)
  error("IRecorder:startRecording() must be implemented by subclass")
end

--- Stop recording audio
--- Implementations should finalize recording and call onComplete when done
--- or onError if an error occurs during stop
---
--- @param onComplete function Callback invoked when stop completes: onComplete()
--- @param onError function Callback invoked on error: onError(errorMessage)
--- @return boolean success True if stop initiated successfully
--- @return string|nil error Error message if failed, nil if successful
function IRecorder:stopRecording(onComplete, onError)
  error("IRecorder:stopRecording() must be implemented by subclass")
end

--- Validate that this recorder can be used
--- Checks for required dependencies (sox, Python, etc.)
---
--- @return boolean success True if recorder is available
--- @return string|nil error Error message if validation failed, nil if successful
function IRecorder:validate()
  error("IRecorder:validate() must be implemented by subclass")
end

--- Check if currently recording
---
--- @return boolean isRecording True if recording is in progress
function IRecorder:isRecording()
  error("IRecorder:isRecording() must be implemented by subclass")
end

--- Get the name of this recorder
--- Used for logging and debugging
---
--- @return string name Recorder name (e.g., "SoxRecorder", "StreamingRecorder")
function IRecorder:getName()
  error("IRecorder:getName() must be implemented by subclass")
end

return IRecorder
