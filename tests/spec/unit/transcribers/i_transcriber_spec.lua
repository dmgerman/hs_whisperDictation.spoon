--- Tests for ITranscriber interface
--- Verifies interface contract and error handling for unimplemented methods

local mock_hs = require("tests.helpers.mock_hs")
_G.hs = mock_hs

local ITranscriber = dofile("transcribers/i_transcriber.lua")

describe("ITranscriber interface", function()
  local transcriber

  before_each(function()
    transcriber = ITranscriber.new()
  end)

  describe("initialization", function()
    it("should create a new instance", function()
      assert.is_not_nil(transcriber)
      assert.is_table(transcriber)
    end)

    it("should have ITranscriber metatable", function()
      assert.equal(ITranscriber, getmetatable(transcriber).__index)
    end)
  end)

  describe("method contracts", function()
    it("should require transcribe to be implemented", function()
      assert.has_error(function()
        transcriber:transcribe("/tmp/audio.wav", "en", function() end, function() end)
      end, "ITranscriber:transcribe() must be implemented by subclass")
    end)

    it("should require validate to be implemented", function()
      assert.has_error(function()
        transcriber:validate()
      end, "ITranscriber:validate() must be implemented by subclass")
    end)

    it("should require getName to be implemented", function()
      assert.has_error(function()
        transcriber:getName()
      end, "ITranscriber:getName() must be implemented by subclass")
    end)

    it("should require supportsLanguage to be implemented", function()
      assert.has_error(function()
        transcriber:supportsLanguage("en")
      end, "ITranscriber:supportsLanguage() must be implemented by subclass")
    end)
  end)

  describe("interface documentation", function()
    it("should define all required methods", function()
      assert.is_function(transcriber.transcribe)
      assert.is_function(transcriber.validate)
      assert.is_function(transcriber.getName)
      assert.is_function(transcriber.supportsLanguage)
    end)
  end)
end)
