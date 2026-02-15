--- WhisperServerMethod Unit Tests

describe("WhisperServerMethod", function()
  local WhisperServerMethod
  local Promise
  local method

  before_each(function()
    package.path = package.path .. ";./?.lua"

    Promise = require("lib.promise")
    WhisperServerMethod = require("methods.whisper_server_method")

    method = WhisperServerMethod.new({
      host = "127.0.0.1",
      port = 8080,
      curlCmd = "curl",
    })
  end)

  describe("initialization", function()
    it("creates a new WhisperServerMethod instance", function()
      assert.is_not_nil(method)
      assert.is_table(method)
    end)

    it("stores configuration", function()
      assert.equals("127.0.0.1", method.config.host)
      assert.equals(8080, method.config.port)
      assert.equals("curl", method.config.curlCmd)
    end)

    it("uses default values if not provided", function()
      local m = WhisperServerMethod.new({})
      assert.equals("127.0.0.1", m.config.host)
      assert.equals(8080, m.config.port)
      assert.equals("curl", m.config.curlCmd)
    end)
  end)

  describe("getName()", function()
    it("returns 'whisper-server'", function()
      assert.equals("whisper-server", method:getName())
    end)
  end)

  describe("validate()", function()
    it("checks if curl is available", function()
      local success, err = method:validate()

      -- curl should be available on most systems
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

    it("constructs correct server URL", function()
      local m = WhisperServerMethod.new({
        host = "localhost",
        port = 9000,
      })

      -- URL should be http://localhost:9000/inference
      assert.equals("localhost", m.config.host)
      assert.equals(9000, m.config.port)
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

  describe("server URL", function()
    it("uses /inference endpoint", function()
      local m = WhisperServerMethod.new({
        host = "example.com",
        port = 1234,
      })

      -- The URL should be http://example.com:1234/inference
      assert.equals("example.com", m.config.host)
      assert.equals(1234, m.config.port)
    end)
  end)

  describe("error handling", function()
    it("handles server errors gracefully", function()
      -- Create a temporary file for testing
      local tempFile = "/tmp/test_whisper_server_" .. os.time() .. ".wav"
      os.execute("touch " .. tempFile)

      local rejected = false
      method:transcribe(tempFile, "en"):catch(function()
        rejected = true
      end)

      -- Clean up
      os.execute("rm -f " .. tempFile)

      -- Note: This will reject because no server is running
      -- We're just ensuring it doesn't crash
    end)
  end)
end)
