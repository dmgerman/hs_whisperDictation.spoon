--- ITranscriber - Interface for audio transcription implementations
--- All transcribers must implement this interface
---
--- @module ITranscriber

local ITranscriber = {}
ITranscriber.__index = ITranscriber

--- Create a new ITranscriber instance
--- This is an abstract interface and should not be instantiated directly
---
--- @return table ITranscriber instance
function ITranscriber.new()
  local self = setmetatable({}, ITranscriber)
  return self
end

--- Transcribe an audio file
--- Implementations should call onSuccess with the transcribed text
--- or onError if transcription fails
---
--- @param audioFile string Path to the audio file to transcribe
--- @param lang string Language code (e.g., "en", "es", "fr")
--- @param onSuccess function Callback invoked with transcription: onSuccess(text)
--- @param onError function Callback invoked on error: onError(errorMessage)
--- @return boolean success True if transcription started successfully
--- @return string|nil error Error message if failed, nil if successful
function ITranscriber:transcribe(audioFile, lang, onSuccess, onError)
  error("ITranscriber:transcribe() must be implemented by subclass")
end

--- Validate that this transcriber can be used
--- Checks for required dependencies (whisper executable, API keys, etc.)
---
--- @return boolean success True if transcriber is available
--- @return string|nil error Error message if validation failed, nil if successful
function ITranscriber:validate()
  error("ITranscriber:validate() must be implemented by subclass")
end

--- Get the name of this transcriber
--- Used for logging and debugging
---
--- @return string name Transcriber name (e.g., "WhisperCLITranscriber", "WhisperKitTranscriber")
function ITranscriber:getName()
  error("ITranscriber:getName() must be implemented by subclass")
end

--- Check if this transcriber supports the given language
---
--- @param lang string Language code (e.g., "en", "es", "fr")
--- @return boolean supported True if language is supported
function ITranscriber:supportsLanguage(lang)
  error("ITranscriber:supportsLanguage() must be implemented by subclass")
end

return ITranscriber
