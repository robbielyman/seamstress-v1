describe('seamstress.async',
  function()
    local async = require 'seamstress.async'
    it('is callable', function()
      assert.is.callable(async)
    end)
    describe('returns a value', function()
      local fn = async(function() end)
      it('which is callable', function()
        assert.is.callable(fn)
      end)
      it('and calling it returns a Promise', function()
        local b = fn()
        assert.is.userdata(b)
        assert.is(b.__name, 'seamstress.async.Promise')
      end)
    end)
  end)

describe('seamstress.async.Promise', function()
  local Promise = require 'seamstress.async.Promise'
  it('is callable', function()
    assert.is.callable(Promise)
  end)
  it('returns a Promise', function()
    b = Promise(function() end)
    assert.is.userdata(b)
    assert.is(b.__name, 'seamstress.async.Promise')
  end)
  it('can be awaited', function()
    b = Promise(function() end)
    assert.has_no.error(b.await, b)
  end)
  describe('awaiting a Promise', function()
    it('pulls out its value', function()
      local b = Promise(function() return 2 end)
      assert(2 == b:await())
    end)
    it('can throw an error', function()
      local c = Promise(function() error("this is an error!") end)
      assert.has.error(function() return c:await() end, "this is an error!")
    end)
  end)
  it('can be chained with anon', function()
    local b = Promise(function() return 2 end)
    assert.equal(4, b:anon(function(x) return x + 2 end):await())
  end)
  it('has an all method', function()
    local t = {}
    for i = 1, 4 do
      t[i] = Promise(function() return i end)
    end
    local p = Promise.all(table.unpack(t))
    local x = p:anon(function(...)
      local arg = { ... }
      local ret = 0
      for _, i in ipairs(arg) do
        ret = ret + i
      end
      return ret
    end):await()
    assert.equal(10, x)
    t[5] = Promise(function() error('ayo') end)
    p = Promise.all(table.unpack(t))
    local y = p:catch(function(err) return err end):await()
    assert.equal('ayo', y)
  end)
  it('has an any method', function()
    local t = {}
    for i = 1, 4 do
      t[i] = Promise(function() error(i) end)
    end
    local p = Promise.any(table.unpack(t))
    local x = p:catch(function(arg)
      local ret = 0
      for _, i in ipairs(arg) do
        ret = ret + i
      end
      return ret
    end):await()
    assert.equal(10, x)
    t[5] = Promise(function() return 'ayo' end)
    p = Promise.any(table.unpack(t))
    local y = p:anon(function(z) return z end):await()
    assert.equal('ayo', y)
  end)
  it('has a race method', function()
    local async = require 'seamstress.async'
    local a = async(function() error('ayo') end)
    local b = async(function()
      coroutine.yield()
      return 'hey'
    end)
    local x = Promise.race(a(), b()):catch(function(err) return err end):await()
    assert.equal('ayo', x)
    a = async(function()
      coroutine.yield()
      coroutine.yield()
      error('ayo')
    end)
    local y = Promise.race(a(), b()):await()
    assert.equal('hey', y)
  end)
end)
