--- Test Fixtures Helper
-- Provides access to real audio files and transcripts for testing

local Fixtures = {}

-- Get path to fixtures directory
local function getFixturesDir()
  local scriptPath = debug.getinfo(1, "S").source:sub(2)
  local testDir = scriptPath:match("(.*/tests/)")
  return testDir .. "fixtures/"
end

-- Get path to data directory (permanent test data)
local function getDataDir()
  local scriptPath = debug.getinfo(1, "S").source:sub(2)
  local testDir = scriptPath:match("(.*/tests/)")
  return testDir .. "data/"
end

Fixtures.dir = getFixturesDir()
Fixtures.dataDir = getDataDir()

--- Load fixture manifest
function Fixtures.loadManifest()
  local manifestPath = Fixtures.dir .. "manifest.json"
  local file = io.open(manifestPath, "r")
  if not file then
    error("Fixture manifest not found. Run ./tests/setup_fixtures.sh first")
  end

  local content = file:read("*a")
  file:close()

  -- Parse JSON (simplified - in real test we'd use hs.json or dkjson)
  return require("dkjson").decode(content)
end

--- Get path to audio chunk fixture
-- @param size (string): "short", "medium", or "long"
-- @return (string): Absolute path to audio file
function Fixtures.getAudioChunk(size)
  size = size or "short"
  local path = Fixtures.dir .. "audio/chunks/chunk_" .. size .. ".wav"

  -- Verify file exists
  local file = io.open(path, "r")
  if not file then
    error("Audio chunk not found: " .. path)
  end
  file:close()

  return path
end

--- Get all complete audio files with transcripts
-- Scans both fixtures/ and data/ directories
-- @return (table): Array of {audio = path, transcript = path, basename = name, lang = lang}
function Fixtures.getCompleteRecordings()
  local recordings = {}

  -- Helper to scan a directory
  local function scanDirectory(audioDir, transcriptsDir)
    local handle = io.popen("ls " .. transcriptsDir .. "*.txt 2>/dev/null")

    if handle then
      for filename in handle:lines() do
        local basename = filename:match("([^/]+)%.txt$")
        if basename then
          local audioPath = audioDir .. basename .. ".wav"
          local transcriptPath = transcriptsDir .. basename .. ".txt"

          -- Check if audio file exists
          local audioFile = io.open(audioPath, "r")
          if audioFile then
            audioFile:close()

            -- Extract language from basename (format: lang-YYYYMMDD-HHMMSS)
            local lang = basename:match("^([^-]+)%-") or "en"

            table.insert(recordings, {
              audio = audioPath,
              transcript = transcriptPath,
              basename = basename,
              lang = lang,
            })
          end
        end
      end
      handle:close()
    end
  end

  -- Scan fixtures directory (original test fixtures)
  scanDirectory(
    Fixtures.dir .. "audio/complete/",
    Fixtures.dir .. "transcripts/"
  )

  -- Scan data directory (permanent recordings from actual usage)
  scanDirectory(
    Fixtures.dataDir .. "audio/recordings/",
    Fixtures.dataDir .. "transcripts/"
  )

  return recordings
end

--- Read transcript file
-- @param path (string): Path to transcript file
-- @return (string): Transcript content
function Fixtures.readTranscript(path)
  local file = io.open(path, "r")
  if not file then
    error("Transcript not found: " .. path)
  end

  local content = file:read("*a")
  file:close()

  return content
end

--- Get a random recording (for fuzz testing)
-- @return (table): {audio = path, transcript = path, basename = name}
function Fixtures.getRandomRecording()
  local recordings = Fixtures.getCompleteRecordings()
  if #recordings == 0 then
    error("No recordings found in fixtures")
  end

  math.randomseed(os.time())
  local index = math.random(1, #recordings)
  return recordings[index]
end

--- Create temporary copy of audio file (for tests that modify files)
-- @param sourcePath (string): Path to source audio file
-- @return (string): Path to temporary copy
function Fixtures.createTempCopy(sourcePath)
  local tmpDir = "/tmp/whisper_test_" .. os.time()
  os.execute("mkdir -p " .. tmpDir)

  local filename = sourcePath:match("([^/]+)$")
  local destPath = tmpDir .. "/" .. filename

  os.execute("cp " .. sourcePath .. " " .. destPath)

  return destPath
end

--- Clean up temporary files created by tests
function Fixtures.cleanup()
  os.execute("rm -rf /tmp/whisper_test_*")
end

--- Get expected transcript for an audio file
-- @param audioPath (string): Path to audio file
-- @return (string|nil): Expected transcript or nil if not found
function Fixtures.getExpectedTranscript(audioPath)
  local basename = audioPath:match("([^/]+)%.wav$")
  if not basename then return nil end

  local transcriptPath = Fixtures.dir .. "transcripts/" .. basename .. ".txt"
  local file = io.open(transcriptPath, "r")
  if not file then return nil end

  local content = file:read("*a")
  file:close()

  return content
end

--- Normalize transcript text for comparison
-- Handles extra line feeds and whitespace variations
-- @param text (string): Raw transcript text
-- @return (string): Normalized text
function Fixtures.normalizeTranscript(text)
  if not text then return "" end

  -- Remove leading/trailing whitespace
  text = text:match("^%s*(.-)%s*$")

  -- Collapse multiple newlines into single space
  text = text:gsub("\n+", " ")

  -- Collapse multiple spaces into single space
  text = text:gsub("%s+", " ")

  -- Remove leading/trailing spaces again
  text = text:match("^%s*(.-)%s*$")

  return text
end

--- Compare two transcripts for similarity
-- Accounts for transcription variations (extra LFs, spacing, etc.)
-- @param actual (string): Actual transcript
-- @param expected (string): Expected transcript
-- @param tolerance (number): Similarity threshold (0.0-1.0), default 0.9
-- @return (boolean, number): match, similarity score
function Fixtures.compareTranscripts(actual, expected, tolerance)
  tolerance = tolerance or 0.9

  -- Normalize both
  local normActual = Fixtures.normalizeTranscript(actual)
  local normExpected = Fixtures.normalizeTranscript(expected)

  -- Exact match after normalization
  if normActual == normExpected then
    return true, 1.0
  end

  -- Calculate Levenshtein distance for similarity
  local similarity = Fixtures._calculateSimilarity(normActual, normExpected)

  return similarity >= tolerance, similarity
end

--- Calculate similarity using Levenshtein distance
-- @param s1 (string): First string
-- @param s2 (string): Second string
-- @return (number): Similarity score (0.0-1.0)
function Fixtures._calculateSimilarity(s1, s2)
  local len1, len2 = #s1, #s2

  if len1 == 0 then return len2 == 0 and 1.0 or 0.0 end
  if len2 == 0 then return 0.0 end

  -- Create distance matrix
  local matrix = {}
  for i = 0, len1 do
    matrix[i] = {[0] = i}
  end
  for j = 0, len2 do
    matrix[0][j] = j
  end

  -- Fill matrix
  for i = 1, len1 do
    for j = 1, len2 do
      local cost = (s1:sub(i, i) == s2:sub(j, j)) and 0 or 1
      matrix[i][j] = math.min(
        matrix[i-1][j] + 1,      -- deletion
        matrix[i][j-1] + 1,      -- insertion
        matrix[i-1][j-1] + cost  -- substitution
      )
    end
  end

  -- Convert distance to similarity score
  local distance = matrix[len1][len2]
  local maxLen = math.max(len1, len2)
  local similarity = 1.0 - (distance / maxLen)

  return similarity
end

return Fixtures
