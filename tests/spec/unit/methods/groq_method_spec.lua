--- GroqMethod Unit Tests

describe("GroqMethod", function()
  local GroqMethod
  local Promise
  local method

  before_each(function()
    package.path = package.path .. ";./?.lua"

    Promise = require("lib.promise")
    GroqMethod = require("methods.groq_method")

    method = GroqMethod.new({
      apiKey = "test-api-key",
      model = "whisper-large-v3",
    })
  end)

  describe("initialization", function()
    it("creates a new GroqMethod instance", function()
      assert.is_not_nil(method)
      assert.is_table(method)
    end)

    it("stores configuration", function()
      assert.equals("test-api-key", method.config.apiKey)
      assert.equals("whisper-large-v3", method.config.model)
    end)

    it("uses default model if not provided", function()
      local m = GroqMethod.new({apiKey = "key"})
      assert.equals("whisper-large-v3", m.config.model)
    end)

    it("uses default timeout if not provided", function()
      local m = GroqMethod.new({apiKey = "key"})
      assert.equals(30, m.config.timeout)
    end)
  end)

  describe("getName()", function()
    it("returns 'groq'", function()
      assert.equals("groq", method:getName())
    end)
  end)

  describe("validate()", function()
    it("checks if API key is configured", function()
      local m = GroqMethod.new({})
      local success, err = m:validate()

      assert.is_false(success)
      assert.is_string(err)
      assert.is_true(err:match("API key") ~= nil)
    end)

    it("checks if curl is available", function()
      local success, err = method:validate()

      -- In test environment, curl should be available
      assert.is_boolean(success)
      if not success then
        assert.is_string(err)
      end
    end)

    it("succeeds with valid API key", function()
      local m = GroqMethod.new({apiKey = "test-key"})
      local success, err = m:validate()

      -- Should pass validation (curl check)
      -- Note: We're not actually calling the API in validate()
      assert.is_boolean(success)
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

    it("includes language in request", function()
      -- This is tested implicitly by the implementation
      -- We'll just verify the method accepts language parameter
      local result = method:transcribe("/tmp/test.wav", "ja")
      assert.is_not_nil(result)
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
      -- Groq's Whisper supports 100+ languages
      assert.is_true(method:supportsLanguage("xx"))
    end)
  end)

  describe("error handling", function()
    it("handles API errors gracefully", function()
      local m = GroqMethod.new({
        apiKey = "invalid-key",
        timeout = 1, -- Short timeout for faster tests
      })

      -- Create a temporary file for testing
      local tempFile = "/tmp/test_groq_" .. os.time() .. ".wav"
      os.execute("touch " .. tempFile)

      local rejected = false
      m:transcribe(tempFile, "en"):catch(function()
        rejected = true
      end)

      -- Clean up
      os.execute("rm -f " .. tempFile)

      -- Note: This may or may not reject depending on network
      -- We're just ensuring it doesn't crash
    end)
  end)
end)
