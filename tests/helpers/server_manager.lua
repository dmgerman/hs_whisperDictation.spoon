--- Server Manager - Start/stop WhisperServer for testing
-- Manages whisper.cpp server lifecycle during tests

local ServerManager = {}

--- Check if WhisperServer is running
-- @param host (string): Server host (default: "127.0.0.1")
-- @param port (number): Server port (default: 8080)
-- @return (boolean): true if server is running
function ServerManager.isRunning(host, port)
  host = host or "127.0.0.1"
  port = port or 8080

  local cmd = string.format(
    "curl -s --connect-timeout 2 http://%s:%s/health 2>/dev/null",
    host,
    port
  )

  local result = os.execute(cmd)
  return result == 0 or result == true
end

--- Start WhisperServer in background
-- @param config (table): Configuration
--   - host (string): Server host (default: "127.0.0.1")
--   - port (number): Server port (default: 8080)
--   - model (string): Path to whisper model (optional)
--   - serverCmd (string): Path to whisper-server binary (optional)
-- @return (boolean, string?): success, error message
function ServerManager.start(config)
  config = config or {}
  local host = config.host or "127.0.0.1"
  local port = config.port or 8080

  -- Check if already running
  if ServerManager.isRunning(host, port) then
    return true, "Server already running"
  end

  -- Find whisper-server binary
  local serverCmd = config.serverCmd
  if not serverCmd then
    -- Try common locations
    local locations = {
      "/opt/homebrew/bin/whisper-server",
      "/usr/local/bin/whisper-server",
      "./whisper-server",
    }

    for _, loc in ipairs(locations) do
      local check = io.popen("test -f " .. loc .. " && echo found")
      local result = check:read("*a")
      check:close()

      if result:match("found") then
        serverCmd = loc
        break
      end
    end
  end

  if not serverCmd then
    return false, "whisper-server binary not found"
  end

  -- Find model file
  local modelPath = config.model
  if not modelPath then
    -- Try common locations for base model
    local modelLocations = {
      "/opt/homebrew/share/whisper/models/ggml-base.en.bin",
      "~/.whisper/models/ggml-base.en.bin",
      "./models/ggml-base.en.bin",
    }

    for _, loc in ipairs(modelLocations) do
      local expandedLoc = loc:gsub("^~", os.getenv("HOME"))
      local check = io.popen("test -f " .. expandedLoc .. " && echo found")
      local result = check:read("*a")
      check:close()

      if result:match("found") then
        modelPath = expandedLoc
        break
      end
    end
  end

  if not modelPath then
    return false, "Whisper model not found"
  end

  -- Start server in background
  local cmd = string.format(
    "%s --host %s --port %s --model %s > /tmp/whisper_server_test.log 2>&1 &",
    serverCmd,
    host,
    port,
    modelPath
  )

  os.execute(cmd)

  -- Wait for server to start (max 10 seconds)
  for i = 1, 20 do
    os.execute("sleep 0.5")
    if ServerManager.isRunning(host, port) then
      return true, "Server started successfully"
    end
  end

  return false, "Server failed to start (timeout)"
end

--- Stop WhisperServer
-- @param host (string): Server host (default: "127.0.0.1")
-- @param port (number): Server port (default: 8080)
-- @return (boolean): success
function ServerManager.stop(host, port)
  host = host or "127.0.0.1"
  port = port or 8080

  -- Find and kill the server process
  local cmd = string.format(
    "lsof -ti tcp:%s | xargs kill 2>/dev/null",
    port
  )

  os.execute(cmd)

  -- Wait for server to stop (max 5 seconds)
  for i = 1, 10 do
    os.execute("sleep 0.5")
    if not ServerManager.isRunning(host, port) then
      return true
    end
  end

  -- Force kill if still running
  os.execute(cmd:gsub("kill", "kill -9"))

  return true
end

--- Ensure server is running (start if needed)
-- @param config (table): Configuration (see start())
-- @return (boolean, string?): success, error message
function ServerManager.ensure(config)
  config = config or {}
  local host = config.host or "127.0.0.1"
  local port = config.port or 8080

  if ServerManager.isRunning(host, port) then
    return true, "Server already running"
  end

  return ServerManager.start(config)
end

--- Get server info
-- @param host (string): Server host (default: "127.0.0.1")
-- @param port (number): Server port (default: 8080)
-- @return (table|nil): Server info {running, url, ...}
function ServerManager.getInfo(host, port)
  host = host or "127.0.0.1"
  port = port or 8080

  local running = ServerManager.isRunning(host, port)

  return {
    running = running,
    host = host,
    port = port,
    url = string.format("http://%s:%s", host, port),
  }
end

return ServerManager
