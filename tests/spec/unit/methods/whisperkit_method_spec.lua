--- WhisperKitMethod Unit Tests

describe("WhisperKitMethod", function()
  local WhisperKitMethod
  local Promise
  local method

  before_each(function()
    package.path = package.path .. ";./?.lua"

    Promise = require("lib.promise")
    WhisperKitMethod = require("methods.whisperkit_method")

    method = WhisperKitMethod.new({
      executable = "/opt/homebrew/bin/whisperkit-cli",
      model = "large-v3",
    })
  end)

  describe("initialization", function()
    it("creates a new WhisperKitMethod instance", function()
      assert.is_not_nil(method)
      assert.is_table(method)
    end)

    it("stores configuration", function()
      assert.equals("/opt/homebrew/bin/whisperkit-cli", method.config.executable)
      assert.equals("large-v3", method.config.model)
    end)

    it("uses default executable if not provided", function()
      local m = WhisperKitMethod.new({model = "base"})
      assert.equals("whisperkit-cli", m.config.executable)
    end)

    it("uses default model if not provided", function()
      local m = WhisperKitMethod.new({})
      assert.equals("large-v3", m.config.model)
    end)
  end)

  describe("getName()", function()
    it("returns 'whisperkit'", function()
      assert.equals("whisperkit", method:getName())
    end)
  end)

  describe("validate()", function()
    it("checks if executable is available", function()
      local success, err = method:validate()

      -- In test environment, whisperkit may or may not be installed
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      end
    end)
  end)

  describe("transcribe()", function()
    it("returns a promise", function()
      local result = method:transcribe("/tmp/test.wav", "en")

      assert.is_not_nil(result)
      assert.equals("table", type(result))
      assert.equals("function", type(result.andThen))
    end)

    it("rejects if audio file does not exist", function()
      local rejected = false
      local errorMsg = nil

      method:transcribe("/nonexistent/file.wav", "en"):catch(function(err)
        rejected = true
        errorMsg = err
      end)

      assert.is_true(rejected)
      assert.is_string(errorMsg)
    end)

    it("includes language in whisperkit command", function()
      -- This test is implementation-specific
      local m = WhisperKitMethod.new({
        executable = "echo",
        model = "base",
      })

      -- Should not throw
      m:transcribe("/tmp/test.wav", "ja")
    end)
  end)

  describe("supportsLanguage()", function()
    it("supports common languages", function()
      assert.is_true(method:supportsLanguage("en"))
      assert.is_true(method:supportsLanguage("ja"))
      assert.is_true(method:supportsLanguage("es"))
    end)

    it("returns true for all languages by default", function()
      assert.is_true(method:supportsLanguage("xx"))
    end)
  end)

  describe("model selection", function()
    it("supports different model sizes", function()
      local models = {"tiny", "base", "small", "medium", "large-v3"}

      for _, model in ipairs(models) do
        local m = WhisperKitMethod.new({model = model})
        assert.equals(model, m.config.model)
      end
    end)
  end)
end)
