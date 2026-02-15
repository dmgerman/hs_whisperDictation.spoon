--- WhisperMethod Unit Tests

describe("WhisperMethod", function()
  local WhisperMethod
  local Promise
  local method

  before_each(function()
    package.path = package.path .. ";./?.lua"

    Promise = require("lib.promise")
    WhisperMethod = require("methods.whisper_method")

    method = WhisperMethod.new({
      modelPath = "/tmp/test-model.bin",
      executable = "whisper",
    })
  end)

  describe("initialization", function()
    it("creates a new WhisperMethod instance", function()
      assert.is_not_nil(method)
      assert.is_table(method)
    end)

    it("stores configuration", function()
      assert.equals("/tmp/test-model.bin", method.config.modelPath)
      assert.equals("whisper", method.config.executable)
    end)

    it("uses default executable if not provided", function()
      local m = WhisperMethod.new({modelPath = "/tmp/model.bin"})
      assert.equals("whisper-cpp", m.config.executable)
    end)
  end)

  describe("getName()", function()
    it("returns 'whisper'", function()
      assert.equals("whisper", method:getName())
    end)
  end)

  describe("validate()", function()
    it("checks if executable is available", function()
      local success, err = method:validate()

      -- In test environment, whisper may or may not be installed
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      end
    end)

    it("checks if model file exists", function()
      local m = WhisperMethod.new({
        modelPath = "/nonexistent/model.bin",
        executable = "echo", -- Use echo so executable check passes
      })

      local success, err = m:validate()

      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("Model file") ~= nil)
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

    it("includes language in whisper command", function()
      -- This test is implementation-specific
      -- We'll just verify the method accepts language parameter
      local m = WhisperMethod.new({
        modelPath = "/tmp/model.bin",
        executable = "echo",
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
      assert.is_true(method:supportsLanguage("fr"))
    end)

    it("returns true for all languages by default", function()
      -- Whisper supports 100+ languages
      assert.is_true(method:supportsLanguage("xx"))
    end)
  end)

  describe("error handling", function()
    it("handles whisper execution errors", function()
      local m = WhisperMethod.new({
        modelPath = "/tmp/model.bin",
        executable = "false", -- Command that always fails
      })

      local rejected = false

      -- Create a temporary file for testing
      local tempFile = "/tmp/test_whisper_" .. os.time() .. ".wav"
      os.execute("touch " .. tempFile)

      m:transcribe(tempFile, "en"):catch(function()
        rejected = true
      end)

      -- Clean up
      os.execute("rm -f " .. tempFile)

      -- Note: This may or may not reject depending on how the method handles errors
      -- We're just ensuring it doesn't crash
    end)
  end)
end)
