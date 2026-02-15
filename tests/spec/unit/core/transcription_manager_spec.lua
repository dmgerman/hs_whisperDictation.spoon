--- TranscriptionManager Unit Tests

describe("TranscriptionManager", function()
  local TranscriptionManager
  local EventBus
  local Promise
  local manager, eventBus, mockMethod

  -- Create a mock transcription method for testing
  local function createMockMethod()
    return {
      name = "mock",
      _transcriptionDelay = 0,

      transcribe = function(self, audioFile, lang)
        return Promise.new(function(resolve, reject)
          if audioFile:match("error") then
            reject("Mock transcription error")
          else
            -- Simulate transcription
            local text = "Transcribed: " .. audioFile
            resolve(text)
          end
        end)
      end,

      validate = function(self)
        return true, nil
      end,
    }
  end

  before_each(function()
    package.path = package.path .. ";./?.lua"

    EventBus = require("lib.event_bus")
    Promise = require("lib.promise")
    TranscriptionManager = require("core.transcription_manager")

    eventBus = EventBus.new()
    mockMethod = createMockMethod()

    manager = TranscriptionManager.new(mockMethod, eventBus, {})
  end)

  describe("initialization", function()
    it("creates a new TranscriptionManager instance", function()
      assert.is_not_nil(manager)
      assert.is_table(manager)
    end)

    it("stores references to dependencies", function()
      assert.equals(mockMethod, manager.method)
      assert.equals(eventBus, manager.eventBus)
    end)

    it("starts with no pending jobs", function()
      assert.equals(0, manager:getPendingCount())
    end)
  end)

  describe("transcribe()", function()
    it("transcribes an audio file", function()
      local result = nil

      manager:transcribe("/tmp/test.wav", "en"):andThen(function(text)
        result = text
      end)

      assert.is_not_nil(result)
      assert.is_true(result:match("Transcribed") ~= nil)
    end)

    it("emits transcription:started event", function()
      local eventData = nil

      eventBus:on("transcription:started", function(data)
        eventData = data
      end)

      manager:transcribe("/tmp/test.wav", "en")

      assert.is_not_nil(eventData)
      assert.equals("/tmp/test.wav", eventData.audioFile)
      assert.equals("en", eventData.lang)
    end)

    it("emits transcription:completed event", function()
      local eventData = nil

      eventBus:on("transcription:completed", function(data)
        eventData = data
      end)

      manager:transcribe("/tmp/test.wav", "en")

      assert.is_not_nil(eventData)
      assert.equals("/tmp/test.wav", eventData.audioFile)
      assert.is_not_nil(eventData.text)
    end)

    it("generates unique job IDs", function()
      local jobIds = {}

      eventBus:on("transcription:started", function(data)
        table.insert(jobIds, data.jobId)
      end)

      manager:transcribe("/tmp/test1.wav", "en")
      manager:transcribe("/tmp/test2.wav", "en")

      assert.equals(2, #jobIds)
      assert.are_not.equal(jobIds[1], jobIds[2])
    end)

    it("tracks pending jobs", function()
      -- Create a slow mock method
      mockMethod.transcribe = function(self, audioFile, lang)
        return Promise.new(function(resolve, reject)
          -- Don't resolve immediately
        end)
      end

      manager:transcribe("/tmp/test.wav", "en")

      assert.equals(1, manager:getPendingCount())
    end)

    it("removes job from pending when complete", function()
      manager:transcribe("/tmp/test.wav", "en")

      -- Job completes synchronously in mock
      assert.equals(0, manager:getPendingCount())
    end)

    it("handles transcription errors", function()
      local errorMsg = nil

      eventBus:on("transcription:error", function(data)
        errorMsg = data.error
      end)

      manager:transcribe("/tmp/error.wav", "en")

      assert.is_not_nil(errorMsg)
    end)

    it("returns promise that resolves with text", function()
      local resolved = false
      local text = nil

      manager:transcribe("/tmp/test.wav", "en"):andThen(function(result)
        resolved = true
        text = result
      end)

      assert.is_true(resolved)
      assert.is_not_nil(text)
    end)

    it("returns promise that rejects on error", function()
      local errorEmitted = false

      eventBus:on("transcription:error", function()
        errorEmitted = true
      end)

      manager:transcribe("/tmp/error.wav", "en"):catch(function()
        -- Error handled
      end)

      assert.is_true(errorEmitted)
    end)
  end)

  describe("getStatus()", function()
    it("returns current status", function()
      local status = manager:getStatus()

      assert.equals(0, status.pending)
      assert.equals(0, status.completed)
      assert.equals(0, status.failed)
    end)

    it("tracks completed transcriptions", function()
      manager:transcribe("/tmp/test1.wav", "en")
      manager:transcribe("/tmp/test2.wav", "en")

      local status = manager:getStatus()

      assert.equals(2, status.completed)
    end)

    it("tracks failed transcriptions", function()
      manager:transcribe("/tmp/error.wav", "en")

      local status = manager:getStatus()

      assert.equals(1, status.failed)
    end)
  end)

  describe("getPendingJobs()", function()
    it("returns empty list when no jobs", function()
      local jobs = manager:getPendingJobs()

      assert.same({}, jobs)
    end)

    it("returns pending jobs", function()
      -- Create slow method
      mockMethod.transcribe = function(self, audioFile, lang)
        return Promise.new(function(resolve, reject)
          -- Don't resolve
        end)
      end

      local capturedJobId = nil
      eventBus:on("transcription:started", function(data)
        capturedJobId = data.jobId
      end)

      manager:transcribe("/tmp/test.wav", "en")
      local jobs = manager:getPendingJobs()

      assert.equals(1, #jobs)
      assert.equals(capturedJobId, jobs[1].jobId)
      assert.equals("/tmp/test.wav", jobs[1].audioFile)
    end)
  end)

  describe("parallel transcriptions", function()
    it("handles multiple transcriptions in parallel", function()
      local results = {}

      manager:transcribe("/tmp/test1.wav", "en"):andThen(function(text)
        table.insert(results, text)
      end)

      manager:transcribe("/tmp/test2.wav", "en"):andThen(function(text)
        table.insert(results, text)
      end)

      manager:transcribe("/tmp/test3.wav", "en"):andThen(function(text)
        table.insert(results, text)
      end)

      assert.equals(3, #results)
    end)

    it("tracks multiple pending jobs", function()
      mockMethod.transcribe = function(self, audioFile, lang)
        return Promise.new(function(resolve, reject)
          -- Don't resolve
        end)
      end

      manager:transcribe("/tmp/test1.wav", "en")
      manager:transcribe("/tmp/test2.wav", "en")
      manager:transcribe("/tmp/test3.wav", "en")

      assert.equals(3, manager:getPendingCount())
    end)

    it("emits events for each transcription", function()
      local startEvents = 0
      local completeEvents = 0

      eventBus:on("transcription:started", function()
        startEvents = startEvents + 1
      end)

      eventBus:on("transcription:completed", function()
        completeEvents = completeEvents + 1
      end)

      manager:transcribe("/tmp/test1.wav", "en")
      manager:transcribe("/tmp/test2.wav", "en")

      assert.equals(2, startEvents)
      assert.equals(2, completeEvents)
    end)
  end)

  describe("job metadata", function()
    it("includes job start time", function()
      local capturedJobId = nil
      eventBus:on("transcription:started", function(data)
        capturedJobId = data.jobId
      end)

      manager:transcribe("/tmp/test.wav", "en")
      local jobs = manager:getCompletedJobs()

      -- Find the job
      local job = nil
      for _, j in ipairs(jobs) do
        if j.jobId == capturedJobId then
          job = j
          break
        end
      end

      assert.is_not_nil(job)
      assert.is_not_nil(job.startTime)
    end)

    it("includes transcription duration", function()
      local capturedJobId = nil
      eventBus:on("transcription:started", function(data)
        capturedJobId = data.jobId
      end)

      manager:transcribe("/tmp/test.wav", "en")
      local jobs = manager:getCompletedJobs()

      local job = nil
      for _, j in ipairs(jobs) do
        if j.jobId == capturedJobId then
          job = j
          break
        end
      end

      assert.is_not_nil(job)
      assert.is_number(job.duration)
    end)
  end)

  describe("integration with method", function()
    it("passes correct parameters to method", function()
      local capturedAudioFile = nil
      local capturedLang = nil

      mockMethod.transcribe = function(self, audioFile, lang)
        capturedAudioFile = audioFile
        capturedLang = lang
        return Promise.resolve("test")
      end

      manager:transcribe("/tmp/test.wav", "ja")

      assert.equals("/tmp/test.wav", capturedAudioFile)
      assert.equals("ja", capturedLang)
    end)

    it("handles method errors gracefully", function()
      mockMethod.transcribe = function(self, audioFile, lang)
        return Promise.reject("Method failed")
      end

      local errorEmitted = false
      eventBus:on("transcription:error", function()
        errorEmitted = true
      end)

      manager:transcribe("/tmp/test.wav", "en")

      assert.is_true(errorEmitted)
    end)
  end)
end)
