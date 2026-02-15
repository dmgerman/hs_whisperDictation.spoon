--- TranscriptionManager - Manage transcription jobs and queue
-- Tracks pending/completed transcriptions and emits events

local TranscriptionManager = {}
TranscriptionManager.__index = TranscriptionManager

--- Create a new TranscriptionManager
-- @param method (ITranscriptionMethod): Transcription method implementation
-- @param eventBus (EventBus): Event bus for communication
-- @param config (table): Configuration
-- @return (TranscriptionManager): New instance
function TranscriptionManager.new(method, eventBus, config)
  local self = setmetatable({}, TranscriptionManager)
  self.method = method
  self.eventBus = eventBus
  self.config = config
  self.pending = {}  -- {jobId => job}
  self.completed = {}  -- Array of completed jobs
  self.failed = {}  -- Array of failed jobs
  self.nextJobId = 1
  return self
end

--- Generate unique job ID
-- @return (string): Unique job ID
function TranscriptionManager:_generateJobId()
  local jobId = "job_" .. self.nextJobId
  self.nextJobId = self.nextJobId + 1
  return jobId
end

--- Transcribe an audio file
-- @param audioFile (string): Path to audio file
-- @param lang (string): Language code
-- @return (Promise): Promise that resolves with transcribed text
function TranscriptionManager:transcribe(audioFile, lang)
  local Promise = require("lib.promise")

  -- CRITICAL: Validate parameters
  if not audioFile or audioFile == "" then
    return Promise.reject("Audio file parameter is required and cannot be empty")
  end

  if not lang or lang == "" then
    return Promise.reject("Language parameter is required and cannot be empty")
  end

  local jobId = self:_generateJobId()
  local startTime = os.time()

  local job = {
    jobId = jobId,
    audioFile = audioFile,
    lang = lang,
    startTime = startTime,
    status = "pending",
  }

  self.pending[jobId] = job

  -- Emit started event
  self.eventBus:emit("transcription:started", {
    jobId = jobId,
    audioFile = audioFile,
    lang = lang,
  })

  -- Start transcription
  return self.method:transcribe(audioFile, lang)
    :next(function(text)
      -- Success
      local duration = os.time() - startTime
      self.pending[jobId] = nil

      job.status = "completed"
      job.text = text
      job.duration = duration
      table.insert(self.completed, job)

      self.eventBus:emit("transcription:completed", {
        jobId = jobId,
        audioFile = audioFile,
        text = text,
        lang = lang,  -- Include language
        duration = duration,
      })

      return text
    end)
    :catch(function(err)
      -- Error - clean up and emit event, but don't break promise chain
      local duration = os.time() - startTime
      self.pending[jobId] = nil

      job.status = "failed"
      job.error = err
      job.duration = duration
      table.insert(self.failed, job)

      self.eventBus:emit("transcription:error", {
        jobId = jobId,
        audioFile = audioFile,
        lang = lang,  -- Include language
        error = tostring(err),
        duration = duration,
      })

      -- Re-throw error to propagate to caller
      return Promise.reject(err)
    end)
end

--- Get count of pending transcriptions
-- @return (number): Number of pending jobs
function TranscriptionManager:getPendingCount()
  local count = 0
  for _, _ in pairs(self.pending) do
    count = count + 1
  end
  return count
end

--- Get list of pending jobs
-- @return (table): Array of pending jobs
function TranscriptionManager:getPendingJobs()
  local jobs = {}
  for _, job in pairs(self.pending) do
    table.insert(jobs, job)
  end
  return jobs
end

--- Get list of completed jobs
-- @return (table): Array of completed jobs
function TranscriptionManager:getCompletedJobs()
  return self.completed
end

--- Get list of failed jobs
-- @return (table): Array of failed jobs
function TranscriptionManager:getFailedJobs()
  return self.failed
end

--- Get current status
-- @return (table): Status information
function TranscriptionManager:getStatus()
  return {
    pending = self:getPendingCount(),
    completed = #self.completed,
    failed = #self.failed,
  }
end

return TranscriptionManager
