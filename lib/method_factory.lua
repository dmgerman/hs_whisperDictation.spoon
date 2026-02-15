--- Method Factory
-- Creates transcription method instances from string-based configuration
-- Supports: groq, whisperkitcli, whispercli, whisperserver

local MethodFactory = {}

--- Create a transcription method from configuration
-- @param methodName (string): The method name ("groq", "whisperkitcli", etc.)
-- @param config (table): Method-specific configuration
-- @param spoonPath (string): Path to spoon directory
-- @return (ITranscriptionMethod, string?): Method instance or (nil, error message)
function MethodFactory.create(methodName, config, spoonPath)
  if methodName == "groq" then
    local GroqMethod = dofile(spoonPath .. "methods/groq_method.lua")
    local apiKey = config.apiKey or os.getenv("GROQ_API_KEY")
    if not apiKey then
      return nil, "Groq API key not configured (set obj.groqApiKey or GROQ_API_KEY env var)"
    end
    return GroqMethod.new({
      apiKey = apiKey,
      model = config.model or "whisper-large-v3",
      timeout = config.timeout or 30,
    })

  elseif methodName == "whisperkitcli" then
    local WhisperKitMethod = dofile(spoonPath .. "methods/whisperkit_method.lua")
    return WhisperKitMethod.new({
      executable = config.cmd or "/opt/homebrew/bin/whisperkit-cli",
      model = config.model or "large-v3",
    })

  elseif methodName == "whispercli" then
    local WhisperMethod = dofile(spoonPath .. "methods/whisper_method.lua")
    return WhisperMethod.new({
      executable = config.cmd or "/opt/homebrew/bin/whisper-cli",
      modelPath = config.modelPath or "/usr/local/whisper/ggml-large-v3.bin",
    })

  elseif methodName == "whisperserver" then
    local WhisperServerMethod = dofile(spoonPath .. "methods/whisper_server_method.lua")
    return WhisperServerMethod.new({
      host = config.host or "127.0.0.1",
      port = config.port or "8080",
      curlCmd = config.curlCmd or "/usr/bin/curl",
    })

  else
    return nil, "Unknown transcription method: " .. methodName
  end
end

return MethodFactory
