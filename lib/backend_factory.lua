--- Backend Factory
-- Creates recording backend instances from string-based configuration
-- Supports: sox, pythonstream

local BackendFactory = {}

--- Create a recording backend from configuration
-- @param backendName (string): The backend name ("sox", "pythonstream")
-- @param eventBus (EventBus): Event bus for emitting events
-- @param config (table): Backend-specific configuration
-- @param spoonPath (string): Path to spoon directory
-- @return (IRecordingBackend, string?): Backend instance or (nil, error message)
function BackendFactory.create(backendName, eventBus, config, spoonPath)
  if backendName == "sox" then
    local SoxBackend = dofile(spoonPath .. "backends/sox_backend.lua")
    return SoxBackend.new(eventBus, {
      soxCmd = config.soxCmd or "/opt/homebrew/bin/sox",
      tempDir = config.tempDir or "/tmp/whisper_dict",
    })

  elseif backendName == "pythonstream" then
    local StreamingBackend = dofile(spoonPath .. "backends/streaming_backend.lua")
    return StreamingBackend.new(eventBus, {
      pythonExecutable = config.pythonExecutable or "python3",
      serverScript = config.serverScript or (spoonPath .. "whisper_stream.py"),
      tcpPort = config.tcpPort or 12341,
      silenceThreshold = config.silenceThreshold or 2.0,
      minChunkDuration = config.minChunkDuration or 3.0,
      maxChunkDuration = config.maxChunkDuration or 600.0,
    })

  else
    return nil, "Unknown backend: " .. backendName
  end
end

return BackendFactory
