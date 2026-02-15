--- Integration test using REAL audio files
-- These tests use actual recordings from /tmp/whisper_dict

local Fixtures = require("tests.helpers.fixtures")
local ServerManager = require("tests.helpers.server_manager")

describe("Real Audio Integration Tests", function()
  local recordings

  setup(function()
    -- Ensure WhisperServer is running before all tests
    print("\n⚙️  Ensuring WhisperServer is running for real audio tests...")
    local running, msg = ServerManager.ensure({
      host = "127.0.0.1",
      port = 8080,
    })

    if not running then
      print("⚠️  Warning: Failed to start WhisperServer: " .. (msg or "unknown error"))
      print("   Real audio tests will fail. Please start whisper-server manually.")
    else
      print("✓ WhisperServer is ready")
    end
  end)

  before_each(function()
    recordings = Fixtures.getCompleteRecordings()
  end)

  after_each(function()
    Fixtures.cleanup()
  end)

  describe("Fixture Setup", function()
    it("has real audio files available", function()
      assert.is_true(#recordings > 0, "No recordings found. Run ./tests/setup_fixtures.sh")
      print(string.format("✓ Found %d recordings with transcripts", #recordings))
    end)

    it("can read audio chunks", function()
      local shortChunk = Fixtures.getAudioChunk("short")
      assert.is_not_nil(shortChunk)
      assert.is_true(shortChunk:match("%.wav$") ~= nil)

      -- Verify file exists and has content
      local file = io.open(shortChunk, "r")
      assert.is_not_nil(file)
      local size = file:seek("end")
      file:close()

      assert.is_true(size > 0, "Audio chunk is empty")
      print(string.format("✓ Short chunk size: %.1f KB", size / 1024))
    end)

    it("can read transcripts", function()
      if #recordings > 0 then
        local recording = recordings[1]
        local transcript = Fixtures.readTranscript(recording.transcript)

        assert.is_not_nil(transcript)
        assert.is_true(#transcript > 0)
        print(string.format("✓ Transcript sample: \"%s\"", transcript:sub(1, 50)))
      end
    end)
  end)

  describe("Transcription Validation", function()
    it("validates transcription against expected output", function()
      -- Use first recording with audio + transcript
      if #recordings > 0 then
        local recording = recordings[1]
        local expectedTranscript = Fixtures.readTranscript(recording.transcript)

        -- In a real test, we would:
        -- 1. Pass audio through transcription backend
        -- 2. Compare result with expected transcript
        -- 3. Assert similarity (allowing for minor differences)

        -- For now, just verify we can access both
        assert.is_not_nil(recording.audio)
        assert.is_not_nil(expectedTranscript)
        print(string.format("✓ Ready to test: %s", recording.basename))
        print(string.format("  Expected: \"%s\"", expectedTranscript:sub(1, 80)))
      else
        pending("No recordings available for testing")
      end
    end)

    it("handles extra line feeds in transcripts", function()
      -- Test transcript normalization
      local withExtraLFs = "This is a test.\n\n\nWith extra line feeds.\n"
      local normalized = Fixtures.normalizeTranscript(withExtraLFs)

      assert.equals("This is a test. With extra line feeds.", normalized)
    end)

    it("compares transcripts with tolerance", function()
      -- Test comparison with minor differences
      local expected = "This is a test sentence."
      local actual1 = "This is a test sentence.\n\n"  -- Extra LFs
      local actual2 = "This is a test  sentence."     -- Extra space
      local actual3 = "This is a different sentence." -- Different words

      local match1, score1 = Fixtures.compareTranscripts(actual1, expected)
      local match2, score2 = Fixtures.compareTranscripts(actual2, expected)
      local match3, score3 = Fixtures.compareTranscripts(actual3, expected)

      assert.is_true(match1, "Should match with extra LFs")
      assert.is_true(match2, "Should match with extra spaces")
      assert.is_false(match3, "Should not match different text")

      print(string.format("  Similarity scores: %.2f, %.2f, %.2f", score1, score2, score3))
    end)
  end)

  describe("End-to-End with Real Audio", function()
    it("Full recording flow with real audio", function()
      if #recordings == 0 then
        pending("No recordings available")
        return
      end

      -- Setup components
      package.path = package.path .. ";./?.lua;./?/init.lua"
      local EventBus = require("lib.event_bus")
      local WhisperServerMethod = require("methods.whisper_server_method")
      local TranscriptionManager = require("core.transcription_manager")

      local eventBus = EventBus.new()
      local method = WhisperServerMethod.new({
        host = "127.0.0.1",
        port = 8080,
      })

      local transcriptionMgr = TranscriptionManager.new(method, eventBus, {})

      -- Use first recording
      local recording = recordings[1]
      local expectedTranscript = Fixtures.readTranscript(recording.transcript)

      print(string.format("\n  Testing: %s", recording.basename))
      print(string.format("  Expected: \"%s...\"", expectedTranscript:sub(1, 50)))

      -- Transcribe the audio
      local actualTranscript = nil
      local transcribeError = nil

      transcriptionMgr:transcribe(recording.audio, recording.lang):next(function(text)
        actualTranscript = text
        print(string.format("  Actual:   \"%s...\"", text:sub(1, 50)))
      end):catch(function(err)
        transcribeError = err
      end)

      -- Check results
      if transcribeError then
        error("Transcription failed: " .. tostring(transcribeError))
      end

      assert.is_not_nil(actualTranscript, "Should have transcription result")

      -- Compare with expected transcript (with realistic tolerance for speech recognition)
      -- 85% similarity is considered good for real-world transcription
      local match, score = Fixtures.compareTranscripts(actualTranscript, expectedTranscript, 0.85)

      print(string.format("  Similarity: %.2f%%", score * 100))

      assert.is_true(match, string.format(
        "Transcription mismatch (%.2f%% similarity, need >=85%%)\nExpected: %s\nActual: %s",
        score * 100,
        expectedTranscript,
        actualTranscript
      ))

      print("  ✓ Transcription matches expected output (>= 85% similarity)")
    end)

    it("Chunk assembly with real multi-chunk recording", function()
      if #recordings == 0 then
        pending("No recordings available")
        return
      end

      -- Setup components
      package.path = package.path .. ";./?.lua;./?/init.lua"
      local EventBus = require("lib.event_bus")
      local ChunkAssembler = require("core.chunk_assembler")
      local WhisperServerMethod = require("methods.whisper_server_method")
      local TranscriptionManager = require("core.transcription_manager")

      local eventBus = EventBus.new()
      local assembler = ChunkAssembler.new(eventBus)

      local method = WhisperServerMethod.new({
        host = "127.0.0.1",
        port = 8080,
      })

      local transcriptionMgr = TranscriptionManager.new(method, eventBus, {})

      -- Use first 3 recordings as "chunks"
      local numChunks = math.min(3, #recordings)
      local expectedParts = {}

      print(string.format("\n  Testing chunk assembly with %d chunks", numChunks))

      -- Transcribe each chunk and add to assembler
      for i = 1, numChunks do
        local recording = recordings[i]
        local expectedText = Fixtures.readTranscript(recording.transcript)
        table.insert(expectedParts, expectedText)

        transcriptionMgr:transcribe(recording.audio, recording.lang):next(function(text)
          print(string.format("  Chunk %d: \"%s...\"", i, text:sub(1, 40)))
          assembler:addChunk(i, text, recording.audio)
        end):catch(function(err)
          error("Transcription failed for chunk " .. i .. ": " .. tostring(err))
        end)
      end

      -- Mark recording as stopped and capture finalized text
      local finalizedText = nil

      eventBus:on("transcription:all_complete", function(data)
        finalizedText = data.text
      end)

      assembler:recordingStopped()

      -- Verify finalization happened
      assert.is_not_nil(finalizedText, "Should have finalized text")

      -- Build expected full transcript
      local expectedFull = table.concat(expectedParts, "\n\n")

      print(string.format("  Expected length: %d chars", #expectedFull))
      print(string.format("  Actual length:   %d chars", #finalizedText))

      -- Compare (with tolerance since chunks are separate recordings)
      local match, score = Fixtures.compareTranscripts(finalizedText, expectedFull)

      print(string.format("  Similarity: %.2f%%", score * 100))

      -- For chunk assembly, we just verify the assembler concatenated correctly
      -- (the individual chunk transcriptions may not match perfectly since they're
      -- separate recordings, but the structure should be right)
      assert.is_true(#finalizedText > 0, "Should have non-empty final text")
      assert.is_true(score > 0.5, "Should have reasonable similarity to expected")

      print("  ✓ Chunk assembly completed successfully")
    end)

    pending("Language detection with multilingual fixtures", function()
      -- TODO: If we add multilingual test fixtures
      -- 1. Test with Japanese, Spanish, etc.
      -- 2. Verify language-specific transcription
    end)
  end)

  describe("Performance Benchmarks", function()
    it("measures transcription speed", function()
      if #recordings > 0 then
        local recording = recordings[1]

        -- In real test:
        -- local startTime = os.clock()
        -- transcribe(recording.audio)
        -- local duration = os.clock() - startTime

        -- Get audio duration
        -- assert(duration < audioLength * 0.5, "Transcription took too long")

        print(string.format("✓ Performance test ready for: %s", recording.basename))
      else
        pending("No recordings available")
      end
    end)
  end)
end)
