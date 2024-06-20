local busted = require 'busted'

busted.describe('seamstress.Timer', function()
  busted.it('wait one second', function()
    local done = false
    local del = 0
    local t = seamstress.Timer(function(self, dt)
      del = dt
      busted.assert.same(1, self.stage)
      done = true
    end, 1, 1)
    busted.assert.same(true, t.running)
    repeat coroutine.yield() until done
    busted.assert(del > 0)
  end)
  busted.it('number go up', function()
    local done = 0
    local t = seamstress.Timer(function(self) done = self.stage end, 0.001, 5)
    repeat coroutine.yield() until done >= 5
    busted.assert.same(false, t.running)
  end)
  busted.it('can start dead', function()
    local done = false
    local t = seamstress.Timer(function() done = true end, 0.001, nil, nil, false)
    busted.assert.same(false, t.running)
    t.running = true
    repeat coroutine.yield() until done
  end)
end)
