--- Sanity test to verify busted is working

describe("Busted Test Framework", function()
  it("can run tests", function()
    assert.is_true(true)
  end)

  it("can do assertions", function()
    assert.equals(2, 1 + 1)
  end)

  it("can handle strings", function()
    assert.equals("hello world", "hello" .. " " .. "world")
  end)
end)
