--- ChunkAssembler - Track and concatenate transcription chunks
-- Handles out-of-order chunks and detects when all chunks are received

local ChunkAssembler = {}
ChunkAssembler.__index = ChunkAssembler

--- Create a new ChunkAssembler
-- @param eventBus (EventBus): Event bus for emitting completion events
-- @return (ChunkAssembler): New instance
function ChunkAssembler.new(eventBus)
  local self = setmetatable({}, ChunkAssembler)
  self.eventBus = eventBus
  self.chunks = {}  -- {chunkNum => {text, audioFile}}
  self.isRecordingStoppedFlag = false
  return self
end

--- Add a chunk
-- @param chunkNum (number): Chunk sequence number (1-based)
-- @param text (string): Transcribed text for this chunk
-- @param audioFile (string): Path to audio file for this chunk
function ChunkAssembler:addChunk(chunkNum, text, audioFile)
  self.chunks[chunkNum] = {
    text = text,
    audioFile = audioFile,
  }

  -- Check if this completes the recording
  if self.isRecordingStoppedFlag and self:allChunksReceived() then
    self:_finalize()
  end
end

--- Mark recording as stopped
-- Will finalize if all chunks have been received
function ChunkAssembler:recordingStopped()
  self.isRecordingStoppedFlag = true

  if self:allChunksReceived() then
    self:_finalize()
  end
end

--- Check if recording has been stopped
-- @return (boolean): true if recording stopped
function ChunkAssembler:isRecordingStopped()
  return self.isRecordingStoppedFlag
end

--- Check if all chunks have been received
-- All chunks from 1 to maxChunkNum must be present (no gaps)
-- @return (boolean): true if all chunks received
function ChunkAssembler:allChunksReceived()
  if self:getChunkCount() == 0 then
    return false
  end

  -- Find max chunk number
  local maxChunk = 0
  for chunkNum, _ in pairs(self.chunks) do
    if chunkNum > maxChunk then
      maxChunk = chunkNum
    end
  end

  -- Check all chunks from 1 to max are present
  for i = 1, maxChunk do
    if not self.chunks[i] then
      return false
    end
  end

  return true
end

--- Get number of chunks received
-- @return (number): Count of chunks
function ChunkAssembler:getChunkCount()
  local count = 0
  for _, _ in pairs(self.chunks) do
    count = count + 1
  end
  return count
end

--- Get a specific chunk
-- @param chunkNum (number): Chunk number
-- @return (table|nil): {text, audioFile} or nil if not found
function ChunkAssembler:getChunk(chunkNum)
  return self.chunks[chunkNum]
end

--- Finalize transcription - concatenate all chunks and emit event
function ChunkAssembler:_finalize()
  -- Find max chunk number
  local maxChunk = 0
  for chunkNum, _ in pairs(self.chunks) do
    if chunkNum > maxChunk then
      maxChunk = chunkNum
    end
  end

  -- Concatenate chunks in order
  local parts = {}
  for i = 1, maxChunk do
    if self.chunks[i] then
      table.insert(parts, self.chunks[i].text)
    end
  end

  local fullText = table.concat(parts, "\n\n")

  -- Emit completion event
  self.eventBus:emit("transcription:all_complete", {
    text = fullText,
    chunkCount = maxChunk,
  })

  -- Reset for next recording
  self:reset()
end

--- Reset assembler for new recording
function ChunkAssembler:reset()
  self.chunks = {}
  self.isRecordingStoppedFlag = false
end

return ChunkAssembler
