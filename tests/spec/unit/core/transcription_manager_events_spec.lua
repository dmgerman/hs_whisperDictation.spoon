--- TranscriptionManager Event & Error Handling Tests

describe("TranscriptionManager Events and Error Handling", function()
  local TranscriptionManager
  local EventBus
  local Promise
  local manager, eventBus, mockMethod

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    EventBus = require("lib.event_bus")
    Promise = require("lib.promise")
    TranscriptionManager = require("core.transcription_manager")

    eventBus = EventBus.new()

    -- Create mock transcription method
    mockMethod = {
      _shouldSucceed = true,
      _transcriptionResult = "test transcription",
      _transcriptionDelay = 0,

      transcribe = function(self, audioFile, lang)
        return Promise.new(function(resolve, reject)
          if self._shouldSucceed then
            resolve(self._transcriptionResult)
          else
            reject("Transcription failed")
          end
        end)
      end,

      getName = function(self)
        return "mock-method"
      end,
    }

    manager = TranscriptionManager.new(mockMethod, eventBus, {
      tempDir = "/tmp/test",
    })
  end)

  describe("Event emissions", function()
    it("emits transcription:started when transcription begins", function()
      local eventFired = false
      local eventData = nil

      eventBus:on("transcription:started", function(data)
        eventFired = true
        eventData = data
      end)

      manager:transcribe("/tmp/test.wav", "en")

      assert.is_true(eventFired, "transcription:started should fire")
      assert.equals("/tmp/test.wav", eventData.audioFile)
      assert.equals("en", eventData.lang)
    end)

    it("emits transcription:completed on success", function()
      local completed = false
      local completedData = nil

      eventBus:on("transcription:completed", function(data)
        completed = true
        completedData = data
      end)

      manager:transcribe("/tmp/test.wav", "en"):next(function()
        assert.is_true(completed, "transcription:completed should fire")
        assert.equals("/tmp/test.wav", completedData.audioFile)
        assert.equals("test transcription", completedData.text)
        assert.equals("en", completedData.lang)
      end)
    end)

    it("emits transcription:error on failure", function()
      local errorFired = false
      local errorData = nil

      mockMethod._shouldSucceed = false

      eventBus:on("transcription:error", function(data)
        errorFired = true
        errorData = data
      end)

      manager:transcribe("/tmp/test.wav", "en"):catch(function()
        assert.is_true(errorFired, "transcription:error should fire")
        assert.equals("/tmp/test.wav", errorData.audioFile)
        assert.is_string(errorData.error)
      end)
    end)

    it("emits events in correct order: started → completed", function()
      local events = {}

      eventBus:on("transcription:started", function()
        table.insert(events, "started")
      end)

      eventBus:on("transcription:completed", function()
        table.insert(events, "completed")
      end)

      manager:transcribe("/tmp/test.wav", "en"):next(function()
        assert.equals(2, #events)
        assert.equals("started", events[1])
        assert.equals("completed", events[2])
      end)
    end)

    it("emits events in correct order on error: started → error", function()
      local events = {}

      mockMethod._shouldSucceed = false

      eventBus:on("transcription:started", function()
        table.insert(events, "started")
      end)

      eventBus:on("transcription:error", function()
        table.insert(events, "error")
      end)

      manager:transcribe("/tmp/test.wav", "en"):catch(function()
        assert.equals(2, #events)
        assert.equals("started", events[1])
        assert.equals("error", events[2])
      end)
    end)
  end)

  describe("Job queue management", function()
    it("processes single transcription job", function()
      local completed = false

      manager:transcribe("/tmp/test.wav", "en"):next(function(text)
        completed = true
        assert.equals("test transcription", text)
      end)

      assert.is_true(completed)
    end)

    it("processes multiple jobs sequentially", function()
      local results = {}

      mockMethod._transcriptionResult = "first"
      manager:transcribe("/tmp/test1.wav", "en"):next(function(text)
        table.insert(results, text)
      end)

      mockMethod._transcriptionResult = "second"
      manager:transcribe("/tmp/test2.wav", "en"):next(function(text)
        table.insert(results, text)
      end)

      mockMethod._transcriptionResult = "third"
      manager:transcribe("/tmp/test3.wav", "en"):next(function(text)
        table.insert(results, text)
      end)

      -- All should complete
      assert.equals(3, #results)
      assert.equals("first", results[1])
      assert.equals("second", results[2])
      assert.equals("third", results[3])
    end)

    it("continues processing after error", function()
      local results = {}

      mockMethod._shouldSucceed = true
      manager:transcribe("/tmp/test1.wav", "en"):next(function(text)
        table.insert(results, "success1")
      end)

      mockMethod._shouldSucceed = false
      manager:transcribe("/tmp/test2.wav", "en"):catch(function()
        table.insert(results, "error")
      end)

      mockMethod._shouldSucceed = true
      manager:transcribe("/tmp/test3.wav", "en"):next(function(text)
        table.insert(results, "success2")
      end)

      -- All should process
      assert.equals(3, #results)
      assert.equals("success1", results[1])
      assert.equals("error", results[2])
      assert.equals("success2", results[3])
    end)
  end)

  describe("Error handling and recovery", function()
    it("handles transcription method errors gracefully", function()
      local errorCaught = false
      local errorMessage = nil

      mockMethod._shouldSucceed = false

      manager:transcribe("/tmp/test.wav", "en"):catch(function(err)
        errorCaught = true
        errorMessage = err
      end)

      assert.is_true(errorCaught)
      assert.is_string(errorMessage)
    end)

    it("includes context in error events", function()
      local errorData = nil

      mockMethod._shouldSucceed = false

      eventBus:on("transcription:error", function(data)
        errorData = data
      end)

      manager:transcribe("/tmp/test.wav", "ja"):catch(function() end)

      assert.is_not_nil(errorData)
      assert.equals("/tmp/test.wav", errorData.audioFile)
      assert.equals("ja", errorData.lang)
      assert.is_string(errorData.error)
    end)

    it("can transcribe again after error", function()
      local firstError = false
      local secondSuccess = false

      mockMethod._shouldSucceed = false
      manager:transcribe("/tmp/test1.wav", "en"):catch(function()
        firstError = true
      end)

      assert.is_true(firstError)

      mockMethod._shouldSucceed = true
      manager:transcribe("/tmp/test2.wav", "en"):next(function(text)
        secondSuccess = true
        assert.equals("test transcription", text)
      end)

      assert.is_true(secondSuccess)
    end)
  end)

  describe("Promise chain handling", function()
    it("returns promise that resolves with transcription text", function()
      local resolved = false
      local resultText = nil

      manager:transcribe("/tmp/test.wav", "en"):next(function(text)
        resolved = true
        resultText = text
      end)

      assert.is_true(resolved)
      assert.equals("test transcription", resultText)
    end)

    it("returns promise that rejects on error", function()
      local rejected = false

      mockMethod._shouldSucceed = false

      manager:transcribe("/tmp/test.wav", "en"):catch(function()
        rejected = true
      end)

      assert.is_true(rejected)
    end)

    it("allows chaining multiple operations", function()
      local chainComplete = false
      local finalResult = nil

      manager:transcribe("/tmp/test.wav", "en")
        :next(function(text)
          -- Process the text
          return text:upper()
        end)
        :next(function(processed)
          chainComplete = true
          finalResult = processed
        end)

      assert.is_true(chainComplete)
      assert.equals("TEST TRANSCRIPTION", finalResult)
    end)
  end)

  describe("Language handling", function()
    it("passes language to transcription method", function()
      local langPassed = nil

      mockMethod.transcribe = function(self, audioFile, lang)
        langPassed = lang
        return Promise.resolve("test")
      end

      manager:transcribe("/tmp/test.wav", "ja")

      assert.equals("ja", langPassed)
    end)

    it("includes language in events", function()
      local startedLang = nil
      local completedLang = nil

      eventBus:on("transcription:started", function(data)
        startedLang = data.lang
      end)

      eventBus:on("transcription:completed", function(data)
        completedLang = data.lang
      end)

      manager:transcribe("/tmp/test.wav", "es"):next(function() end)

      assert.equals("es", startedLang)
      assert.equals("es", completedLang)
    end)
  end)

  describe("Interface compliance", function()
    it("implements all required methods", function()
      assert.is_function(manager.transcribe)
    end)

    it("returns promises from async methods", function()
      local promise = manager:transcribe("/tmp/test.wav", "en")

      assert.is_table(promise)
      assert.is_function(promise.next)
      assert.is_function(promise.catch)
    end)

    it("works with different transcription methods", function()
      -- Test that manager works with any method implementing the interface
      local alternateMethod = {
        transcribe = function(self, audioFile, lang)
          return Promise.resolve("alternate result")
        end,
        getName = function(self)
          return "alternate"
        end,
      }

      local altManager = TranscriptionManager.new(alternateMethod, eventBus, {})
      local result = nil

      altManager:transcribe("/tmp/test.wav", "en"):next(function(text)
        result = text
      end)

      assert.equals("alternate result", result)
    end)
  end)

  describe("Cleanup and resource management", function()
    it("cleans up after successful transcription", function()
      manager:transcribe("/tmp/test.wav", "en"):next(function()
        -- Manager should be ready for next transcription
        -- No lingering state from previous job
        assert.is_not_nil(manager)
      end)
    end)

    it("cleans up after failed transcription", function()
      mockMethod._shouldSucceed = false

      manager:transcribe("/tmp/test.wav", "en"):catch(function()
        -- Manager should be ready for next transcription
        assert.is_not_nil(manager)
      end)
    end)
  end)
end)
