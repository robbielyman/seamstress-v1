local busted = require 'busted'

busted.describe('seamstress.async',
  function()
    busted.it('is callable', function()
      busted.assert.has('__call', seamstress.async)
    end)
    busted.it('returns a function', function()
      busted.assert.is_function(seamstress.async(function() end))
    end)
    busted.it('the returned function returns a Promise', function()
      local b = seamstress.async(function() end)()
      busted.assert.is_userdata(b)
      busted.assert.is(b.__name, 'seamstress.async.Promise')
    end)
  end)

busted.describe('seamstress.async.Promise', function()
  busted.it('is callable', function()
    busted.assert.has('__call', seamstress.async.Promise)
  end)
  busted.it('returns a Promise', function()
    local b = seamstress.async.Promise(function() end)
    busted.assert.is_userdata(b)
    busted.assert.is(b.__name, 'seamstress.async.Promise')
  end)
  busted.it('can be awaited', function()
    local b = seamstress.async.Promise(function() end)
    busted.assert.has_no_error(b.await, b)
  end)
  busted.it('awaiting a promise pulls out its value', function()
    local b = seamstress.async.Promise(function()
      return 2
    end)
    busted.assert(2 == b:await())
  end)
  busted.it('awaiting can throw an error', function()
    local b = seamstress.async.Promise(function() error("this is an error!") end)
    busted.assert.has_error(function() return b:await() end, "this is an error!")
  end)
  busted.it('can be chained with anon', function()
    local b = seamstress.async.Promise(function()
      return 2
    end)
    busted.assert(4 == b:anon(function(x) return x + 2 end):await())
  end)
  busted.it('tests can await', function()
    local promise = seamstress.async(function()
      busted.assert.falsy(false)
    end)()
    busted.assert.has_no_error(promise.await, promise)
  end)
  busted.it('has an all method', function()
    local t = {}
    for i = 1, 4 do
      t[i] = seamstress.async.Promise(function() return i end)
    end
    local promise = seamstress.async.Promise.all(table.unpack(t))
    local x = promise:anon(function(...)
      local arg = { ... }
      local ret = 0
      for _, i in ipairs(arg) do
        ret = ret + i
      end
      return ret
    end):await()
    busted.assert.equal(10, x)
    t[5] = seamstress.async.Promise(function() error('ayo') end)
    promise = seamstress.async.Promise.all(table.unpack(t))
    local y = promise:catch(function(err) return err end):await()
    busted.assert.equal('ayo', y)
  end)
  busted.it('has an any method', function()
    local t = {}
    for i = 1, 4 do
      t[i] = seamstress.async.Promise(function() error(i) end)
    end
    local promise = seamstress.async.Promise.any(table.unpack(t))
    local x = promise:catch(function(arg)
      local ret = 0
      for _, i in ipairs(arg) do
        ret = ret + i
      end
      return ret
    end):await()
    busted.assert.equal(10, x)
    t[5] = seamstress.async.Promise(function() return 'ayo' end)
    promise = seamstress.async.Promise.any(table.unpack(t))
    local y = promise:anon(function(z) return z end):await()
    busted.assert.equal('ayo', y)
  end)
  busted.it('has a race method', function()
    local a = seamstress.async(function() error('ayo') end)
    local b = seamstress.async(function()
      coroutine.yield()
      return 'hey'
    end)
    local x = seamstress.async.Promise.race(a(), b()):catch(function(err) return err end):await()
    busted.assert.equal('ayo', x)
    a = seamstress.async(function()
      coroutine.yield()
      coroutine.yield()
      error('ayo')
    end)
    local y = seamstress.async.Promise.race(a(), b()):await()
    busted.assert.equal('hey', y)
  end)
end)
