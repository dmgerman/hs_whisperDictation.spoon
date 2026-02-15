--- ChunkAssembler Unit Tests

describe("ChunkAssembler", function()
  local ChunkAssembler
  local EventBus
  local assembler, eventBus

  before_each(function()
    -- Create test directory if needed
    package.path = package.path .. ";./?.lua"

    EventBus = require("lib.event_bus")
    ChunkAssembler = require("core.chunk_assembler")

    eventBus = EventBus.new()
    assembler = ChunkAssembler.new(eventBus)
  end)

  describe("initialization", function()
    it("creates a new ChunkAssembler instance", function()
      assert.is_not_nil(assembler)
      assert.is_table(assembler)
    end)

    it("starts with no chunks", function()
      assert.equals(0, assembler:getChunkCount())
    end)
  end)

  describe("addChunk()", function()
    it("adds a chunk", function()
      assembler:addChunk(1, "First chunk", "/tmp/chunk1.wav")

      assert.equals(1, assembler:getChunkCount())
    end)

    it("stores chunk text and audio file", function()
      assembler:addChunk(1, "Test text", "/tmp/test.wav")

      local chunk = assembler:getChunk(1)
      assert.equals("Test text", chunk.text)
      assert.equals("/tmp/test.wav", chunk.audioFile)
    end)

    it("handles multiple chunks", function()
      assembler:addChunk(1, "First", "/tmp/1.wav")
      assembler:addChunk(2, "Second", "/tmp/2.wav")
      assembler:addChunk(3, "Third", "/tmp/3.wav")

      assert.equals(3, assembler:getChunkCount())
    end)

    it("handles out-of-order chunks", function()
      assembler:addChunk(3, "Third", "/tmp/3.wav")
      assembler:addChunk(1, "First", "/tmp/1.wav")
      assembler:addChunk(2, "Second", "/tmp/2.wav")

      assert.equals(3, assembler:getChunkCount())
    end)

    it("overwrites duplicate chunk numbers", function()
      assembler:addChunk(1, "Original", "/tmp/1.wav")
      assembler:addChunk(1, "Updated", "/tmp/1-new.wav")

      local chunk = assembler:getChunk(1)
      assert.equals("Updated", chunk.text)
    end)
  end)

  describe("recordingStopped()", function()
    it("marks recording as stopped", function()
      assembler:recordingStopped()

      assert.is_true(assembler:isRecordingStopped())
    end)

    it("finalizes if all chunks received", function()
      local finalized = false

      eventBus:on("transcription:all_complete", function()
        finalized = true
      end)

      assembler:addChunk(1, "Only chunk", "/tmp/1.wav")
      assembler:recordingStopped()

      assert.is_true(finalized)
    end)

    it("waits for missing chunks before finalizing", function()
      local finalized = false

      eventBus:on("transcription:all_complete", function()
        finalized = true
      end)

      assembler:addChunk(1, "First", "/tmp/1.wav")
      assembler:addChunk(3, "Third", "/tmp/3.wav")
      assembler:recordingStopped()

      assert.is_false(finalized, "Should not finalize with missing chunk 2")

      -- Now add missing chunk
      assembler:addChunk(2, "Second", "/tmp/2.wav")

      assert.is_true(finalized, "Should finalize after all chunks received")
    end)
  end)

  describe("concatenation", function()
    it("concatenates chunks in order", function()
      local result = nil

      eventBus:on("transcription:all_complete", function(data)
        result = data.text
      end)

      assembler:addChunk(1, "First chunk", "/tmp/1.wav")
      assembler:addChunk(2, "Second chunk", "/tmp/2.wav")
      assembler:addChunk(3, "Third chunk", "/tmp/3.wav")
      assembler:recordingStopped()

      assert.equals("First chunk\n\nSecond chunk\n\nThird chunk", result)
    end)

    it("concatenates out-of-order chunks correctly", function()
      local result = nil

      eventBus:on("transcription:all_complete", function(data)
        result = data.text
      end)

      assembler:addChunk(3, "Third", "/tmp/3.wav")
      assembler:addChunk(1, "First", "/tmp/1.wav")
      assembler:addChunk(2, "Second", "/tmp/2.wav")
      assembler:recordingStopped()

      assert.equals("First\n\nSecond\n\nThird", result)
    end)

    it("emits event with chunk count", function()
      local chunkCount = nil

      eventBus:on("transcription:all_complete", function(data)
        chunkCount = data.chunkCount
      end)

      assembler:addChunk(1, "One", "/tmp/1.wav")
      assembler:addChunk(2, "Two", "/tmp/2.wav")
      assembler:recordingStopped()

      assert.equals(2, chunkCount)
    end)

    it("handles single chunk", function()
      local result = nil

      eventBus:on("transcription:all_complete", function(data)
        result = data.text
      end)

      assembler:addChunk(1, "Only chunk", "/tmp/1.wav")
      assembler:recordingStopped()

      assert.equals("Only chunk", result)
    end)
  end)

  describe("reset()", function()
    it("clears all chunks", function()
      assembler:addChunk(1, "First", "/tmp/1.wav")
      assembler:addChunk(2, "Second", "/tmp/2.wav")

      assembler:reset()

      assert.equals(0, assembler:getChunkCount())
    end)

    it("resets recording stopped flag", function()
      assembler:recordingStopped()
      assembler:reset()

      assert.is_false(assembler:isRecordingStopped())
    end)

    it("allows reuse after reset", function()
      local count = 0

      eventBus:on("transcription:all_complete", function()
        count = count + 1
      end)

      -- First recording
      assembler:addChunk(1, "First", "/tmp/1.wav")
      assembler:recordingStopped()

      assert.equals(1, count)

      -- Reset and second recording
      assembler:reset()
      assembler:addChunk(1, "Second", "/tmp/2.wav")
      assembler:recordingStopped()

      assert.equals(2, count)
    end)
  end)

  describe("edge cases", function()
    it("handles empty chunks (no text)", function()
      local result = nil

      eventBus:on("transcription:all_complete", function(data)
        result = data.text
      end)

      assembler:addChunk(1, "", "/tmp/1.wav")
      assembler:recordingStopped()

      assert.equals("", result)
    end)

    it("handles chunks with newlines in text", function()
      local result = nil

      eventBus:on("transcription:all_complete", function(data)
        result = data.text
      end)

      assembler:addChunk(1, "Line one\nLine two", "/tmp/1.wav")
      assembler:addChunk(2, "Line three", "/tmp/2.wav")
      assembler:recordingStopped()

      assert.equals("Line one\nLine two\n\nLine three", result)
    end)

    it("handles very large chunk numbers", function()
      assembler:addChunk(100, "Chunk 100", "/tmp/100.wav")

      assert.equals(1, assembler:getChunkCount())
    end)

    it("finalizes automatically when last chunk arrives after recording stopped", function()
      local finalized = false

      eventBus:on("transcription:all_complete", function()
        finalized = true
      end)

      -- Add chunks 1 and 3 (missing 2)
      assembler:addChunk(1, "First", "/tmp/1.wav")
      assembler:addChunk(3, "Third", "/tmp/3.wav")
      assembler:recordingStopped()  -- Recording stopped, but missing chunk 2

      assert.is_false(finalized, "Should not finalize with missing chunk 2")

      -- This should trigger finalization
      assembler:addChunk(2, "Second", "/tmp/2.wav")

      assert.is_true(finalized, "Should finalize after all chunks received")
    end)
  end)

  describe("allChunksReceived()", function()
    it("returns false with no chunks", function()
      assert.is_false(assembler:allChunksReceived())
    end)

    it("returns true when all sequential chunks received", function()
      assembler:addChunk(1, "One", "/tmp/1.wav")
      assembler:addChunk(2, "Two", "/tmp/2.wav")
      assembler:addChunk(3, "Three", "/tmp/3.wav")

      assert.is_true(assembler:allChunksReceived())
    end)

    it("returns false with missing chunks", function()
      assembler:addChunk(1, "One", "/tmp/1.wav")
      assembler:addChunk(3, "Three", "/tmp/3.wav")  -- Missing 2

      assert.is_false(assembler:allChunksReceived())
    end)

    it("handles non-sequential but complete chunks", function()
      assembler:addChunk(5, "Five", "/tmp/5.wav")
      assembler:addChunk(3, "Three", "/tmp/3.wav")
      assembler:addChunk(1, "One", "/tmp/1.wav")
      assembler:addChunk(4, "Four", "/tmp/4.wav")
      assembler:addChunk(2, "Two", "/tmp/2.wav")

      assert.is_true(assembler:allChunksReceived())
    end)
  end)
end)
