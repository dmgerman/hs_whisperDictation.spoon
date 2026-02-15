--- Helper script to load new architecture components for integration tests
--- Usage: dofile('/path/to/spoon/tests/helpers/load_new_architecture.lua')
---
--- This creates global variables: SoxRecorder, MockTranscriber, Manager, etc.

-- Get spoon path (two directories up from this file)
local scriptPath = debug.getinfo(1, "S").source:match("^@(.*)$")
local testsPath = scriptPath:match("^(.*/tests/)") or "./"
local spoonPath = testsPath:match("^(.*/)[^/]+/$") or "./"

-- Add to package path
package.path = package.path .. ";" .. spoonPath .. "?.lua;" .. spoonPath .. "?/init.lua"

-- Load components with absolute paths (dofile with relative paths from current working dir)
-- Since we can't rely on current directory, we'll save current dir, change to spoon, load, restore

local function loadComponent(relativePath)
  local fullPath = spoonPath .. relativePath
  return dofile(fullPath)
end

-- Load new architecture components
SoxRecorder = loadComponent("recorders/sox_recorder.lua")
MockTranscriber = loadComponent("tests/mocks/mock_transcriber.lua")
MockRecorder = loadComponent("tests/mocks/mock_recorder.lua")
Manager = loadComponent("core_v2/manager.lua")
Notifier = loadComponent("lib/notifier.lua")

-- Return success indicator
return {
  SoxRecorder = SoxRecorder,
  MockTranscriber = MockTranscriber,
  MockRecorder = MockRecorder,
  Manager = Manager,
  Notifier = Notifier,
}
