describe('seamstress.Timer',
  function()
    local Timer = require 'seamstress.Timer'
    it('is callable', function()
      assert.is.callable(Timer)
    end)
    describe('returns a Timer', function()
      local done = false
      local del = 0
      local t = Timer(function(self, dt)
        del = dt
        assert.same(1, self.stage)
        done = true
      end, 1, 1, nil, false)
      it('which can start dead', function()
        assert.same(false, t.running)
      end)
      it('can wait a few milliseconds', function()
        t.delta = 0.005
        t.running = true
        repeat coroutine.yield() until done
        assert(del > 0)
      end)
    end)
  end)
