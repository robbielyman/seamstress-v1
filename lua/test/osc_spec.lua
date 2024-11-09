local osc = require 'seamstress.osc'
describe('seamstress.osc.Message', function()
  it('is callable', function()
    assert.is.callable(osc.Message)
  end)
  describe('returns a value', function()
    local m = osc.Message()
    it('which is a Message', function()
      assert.is.userdata(m)
      assert.is(m.__name, 'seamstress.osc.Message')
    end)
    it('which has a path', function()
      assert.are.same(m.path, nil)
      m.path = "/an/osc/path"
      assert.are.same(m.path, "/an/osc/path")
    end)
    it('arguments can be added and changed', function()
      assert.are.same(#m, 0)
      m[1] = 15
      assert.are.same('i', m.types)
      m[2] = 1.5
      m[3] = "string"
      assert.are.same('ifs', m.types)
      m[3] = true
      assert.are.same('ifT', m.types)
    end)
    it('can be converted to bytes', function()
      local bytes = m:bytes()
      assert.are.same(#bytes % 4, 0)
    end)
    it('can be iterated over', function()
      local expected = { 15, 1.5, true }
      assert.are.same(#expected, #m)
      for i, data in ipairs(m) do
        assert.are.same(expected[i], data)
      end
    end)
  end)
  describe('may be called with a table', function()
    it('with a type tag string', function()
      local m = osc.Message({
        path = "/an/osc/path",
        types = "ifSsh",
        -56,
        3.1415,
        "symbol",
        "string",
        78
      })
      local expected = { -56, 3.1415, "symbol", "string", 78 }
      assert.are.same(#expected, #m)
      for i, data in ipairs(m) do
        if type(data) == 'number' then
          assert.are.near(expected[i], data, 0.00001)
        else
          assert.are.same(expected[i], data)
        end
      end
    end)
    it('without a type tag string', function()
      local m = osc.Message({
        path = "/an/osc/path",
        -56,
        3.1415,
        "symbol",
        "string",
        78
      })
      local expected = { -56, 3.1415, "symbol", "string", 78 }
      for i, data in ipairs(m) do
        if type(data) == 'number' then
          assert.are.near(expected[i], data, 0.00001)
        else
          assert.are.same(expected[i], data)
        end
      end
    end)
  end)
end)

describe('seamstress.osc.Client', function()
  it('is callable', function()
    assert.is.callable(osc.Client)
  end)
  describe('returns a value', function()
    local sum = 0
    local c = osc.Client {
      address = 1881,
      ["/test/path"] = function(_, _, msg)
        for i, data in ipairs(msg) do
          sum = sum + (data * i)
        end
        assert.are.same(17, sum)
        return false
      end,
    }
    it('which is a Client', function()
      assert.is.userdata(c)
      assert.is(c.__name, 'seamstress.osc.Client')
    end)
    it('can dispatch messages', function()
      c:dispatch(nil, {
        path = "/test/path",
        2,
        3,
        3,
      })
    end)
  end)
end)

describe('seamstress.osc.Server', function()
  it('is callable', function()
    assert.is.callable(osc.Server)
  end)
  describe('returns a value', function()
    local s = osc.Server(1991)
    it('which is a Server', function()
      assert.is.userdata(s)
      assert.is(s.__name, 'seamstress.osc.Server')
    end)
    it('which has an address', function()
      local expected = { host = "127.0.0.1", port = 1991 }
      assert.are.same(expected, s.address)
    end)
    it('can send messages', function()
      s:send(1881, {
        path = "/some/osc/path",
        500,
        "message_string",
      })
    end)
    it('can dispatch messages', function()
      s:dispatch(1881, {
        path = "/some/osc/path",
        500,
        "message_string",
      })
    end)
    it('starts running', function()
      assert.are.same(true, s.running)
    end)
    it('can be stopped', function()
      s.running = false
      assert.are.same(false, s.running)
    end)
  end)
end)
