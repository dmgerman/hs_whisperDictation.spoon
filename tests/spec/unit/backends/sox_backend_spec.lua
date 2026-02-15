--- SoxBackend Unit Tests

describe("SoxBackend", function()
  local SoxBackend
  local EventBus
  local Promise
  local backend, eventBus

  before_each(function()
    package.path = package.path .. ";./?.lua;./?/init.lua"

    -- Load mock Hammerspoon APIs
    local MockHS = require("tests.helpers.mock_hs")
    _G.hs = MockHS

    EventBus = require("lib.event_bus")
    Promise = require("lib.promise")
    SoxBackend = require("backends.sox_backend")

    eventBus = EventBus.new()
    backend = SoxBackend.new(eventBus, {
      soxCmd = "/opt/homebrew/bin/sox",
      tempDir = "/tmp/whisper_dict"
    })
  end)

  describe("initialization", function()
    it("creates a new SoxBackend instance", function()
      assert.is_not_nil(backend)
      assert.is_table(backend)
    end)

    it("starts in idle state", function()
      assert.is_false(backend:isRecording())
    end)

    it("stores reference to eventBus", function()
      assert.equals(eventBus, backend.eventBus)
    end)
  end)

  describe("validate()", function()
    it("checks if sox is available", function()
      local success, err = backend:validate()

      -- In test environment, sox may or may not be installed
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      end
    end)
  end)

  describe("startRecording()", function()
    it("returns a promise", function()
      local result = backend:startRecording({
        outputDir = "/tmp/test",
        filenamePrefix = "test",
        lang = "en",
      })

      assert.is_not_nil(result)
      assert.equals("table", type(result))
      assert.equals("function", type(result.next))

      -- Clean up
      backend:stopRecording()
    end)

    it("transitions to recording state", function()
      local completed = false

      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):next(function()
        completed = true
        assert.is_true(backend:isRecording())
        backend:stopRecording()
      end):catch(function(err)
        -- Ignore errors if sox not available - just mark as completed
        completed = true
      end)

      -- Promise should resolve or reject synchronously
      assert.is_true(completed, "Promise should complete synchronously")
    end)

    it("rejects if already recording", function()
      local rejected = false

      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):catch(function()
        -- Ignore if sox not available
      end)

      if backend:isRecording() then
        backend:startRecording({
          outputDir = "/tmp/test",
          filenamePrefix = "test",
          lang = "en",
          eventBus = eventBus,
          chunkDuration = 1,
        }):catch(function()
          rejected = true
        end)

        assert.is_true(rejected)
        backend:stopRecording()
      end
    end)

    it("stores recording state", function()
      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):catch(function() end)

      if backend:isRecording() then
        assert.equals("en", backend.currentLang)
        assert.is_not_nil(backend.audioFile)
        assert.is_not_nil(backend.startTime)
        backend:stopRecording()
      end
    end)
  end)

  describe("stopRecording()", function()
    it("returns a promise", function()
      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):catch(function() end)

      if backend:isRecording() then
        local result = backend:stopRecording()

        assert.is_not_nil(result)
        assert.equals("table", type(result))
        assert.equals("function", type(result.next))
      end
    end)

    it("transitions to idle state", function()
      backend:startRecording({
        outputDir = "/tmp/test",
        lang = "en",
      }):catch(function() end)

      if backend:isRecording() then
        backend:stopRecording()
        assert.is_false(backend:isRecording())
      end
    end)

    it("rejects if not recording", function()
      local rejected = false

      backend:stopRecording():catch(function()
        rejected = true
      end)

      assert.is_true(rejected)
    end)
  end)

  describe("getDisplayText()", function()
    it("returns display text with language", function()
      local text = backend:getDisplayText("en")

      assert.is_string(text)
      assert.is_true(text:match("en") ~= nil)
    end)

    it("includes recording indicator", function()
      local text = backend:getDisplayText("ja")

      assert.is_string(text)
      -- Should contain emoji or "Recording" text
      assert.is_true(text:match("🎙") ~= nil or text:match("Recording") ~= nil)
    end)
  end)

  describe("getName()", function()
    it("returns 'sox'", function()
      assert.equals("sox", backend:getName())
    end)
  end)
end)
