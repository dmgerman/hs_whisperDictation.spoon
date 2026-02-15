--- Tests for IRecorder interface
--- Verifies interface contract and error handling for unimplemented methods

local mock_hs = require("tests.helpers.mock_hs")
_G.hs = mock_hs

local IRecorder = dofile("recorders/i_recorder.lua")

describe("IRecorder interface", function()
  local recorder

  before_each(function()
    recorder = IRecorder.new()
  end)

  describe("initialization", function()
    it("should create a new instance", function()
      assert.is_not_nil(recorder)
      assert.is_table(recorder)
    end)

    it("should have IRecorder metatable", function()
      assert.equal(IRecorder, getmetatable(recorder).__index)
    end)
  end)

  describe("method contracts", function()
    it("should require startRecording to be implemented", function()
      assert.has_error(function()
        recorder:startRecording({}, function() end, function() end)
      end, "IRecorder:startRecording() must be implemented by subclass")
    end)

    it("should require stopRecording to be implemented", function()
      assert.has_error(function()
        recorder:stopRecording(function() end, function() end)
      end, "IRecorder:stopRecording() must be implemented by subclass")
    end)

    it("should require validate to be implemented", function()
      assert.has_error(function()
        recorder:validate()
      end, "IRecorder:validate() must be implemented by subclass")
    end)

    it("should require isRecording to be implemented", function()
      assert.has_error(function()
        recorder:isRecording()
      end, "IRecorder:isRecording() must be implemented by subclass")
    end)

    it("should require getName to be implemented", function()
      assert.has_error(function()
        recorder:getName()
      end, "IRecorder:getName() must be implemented by subclass")
    end)
  end)

  describe("interface documentation", function()
    it("should define all required methods", function()
      assert.is_function(recorder.startRecording)
      assert.is_function(recorder.stopRecording)
      assert.is_function(recorder.validate)
      assert.is_function(recorder.isRecording)
      assert.is_function(recorder.getName)
    end)
  end)
end)
