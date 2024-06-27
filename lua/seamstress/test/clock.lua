local busted = require 'busted'

busted.describe('seamstress.clock', function()
  busted.it('has fields', function()
    busted.assert.same(true, seamstress.clock.is_playing)
    busted.assert.same('number', type(seamstress.clock.tempo))
    busted.assert.same('number', type(seamstress.clock.beat))
    busted.assert.same('number', type(seamstress.clock.time))
    busted.assert.same('internal', seamstress.clock.source)
    busted.assert.same('number', type(seamstress.clock.link_quantum))
  end)

  busted.it('works', function()
    local done = 0
    seamstress.clock.run(function()
      seamstress.clock.sleep(0.25)
      done = done + 1
    end)
    seamstress.clock.run(function()
      seamstress.clock.sync(1)
      done = done + 1
    end)
    local c = seamstress.clock.run(function()
      seamstress.clock.sleep(0.25)
      done = done + 1
    end)
    busted.assert.truthy(c.id)
    busted.assert.truthy(c.coro)
    seamstress.clock.cancel(c)
    repeat
      coroutine.yield()
    until done == 2
  end)
end)
