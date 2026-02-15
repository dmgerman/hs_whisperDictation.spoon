--- ITranscriptionMethod Interface
-- All transcription methods must implement this interface
--
-- Transcription methods convert audio files to text using various
-- backends (local whisper, remote APIs like Groq, etc.)

local ITranscriptionMethod = {}

--- Transcribe an audio file
-- @param audioFile (string): Path to the audio file
-- @param lang (string): Language code (e.g., "en", "ja")
-- @return (Promise): Promise that resolves with transcribed text string
function ITranscriptionMethod:transcribe(audioFile, lang)
  error("Not implemented: transcribe")
end

--- Validate method is available and configured
-- @return (boolean, string?): success, error message if failed
function ITranscriptionMethod:validate()
  error("Not implemented: validate")
end

--- Get the name of this transcription method
-- @return (string): Method name (e.g., "whisper", "groq")
function ITranscriptionMethod:getName()
  error("Not implemented: getName")
end

--- Check if this method supports a given language
-- @param lang (string): Language code
-- @return (boolean): true if language is supported
function ITranscriptionMethod:supportsLanguage(lang)
  -- Default implementation: support all languages
  return true
end

return ITranscriptionMethod
