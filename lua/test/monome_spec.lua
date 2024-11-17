local monome = require 'seamstress.monome'
describe('seamstress.monome', function()
  local m
  it('is callable', function()
    assert.is.callable(monome)
  end)
  m = monome(8888)
  it('calling it returns a table', function()
    assert.is.table(m)
    assert.has(m, 'serialosc')
    assert.has(m, 'Grid')
    assert.has(m, 'Arc')
  end)
  local dev_waiting = true
  local p = seamstress.async.Promise(function()
    repeat coroutine.yield() until dev_waiting == false
  end)
  seamstress.Timer(function(self)
    if #m.Grid > 0 or self.stage >= 3 then
      dev_waiting = false
      self.running = false
    end
  end)
  p:await()
  if #m.Grid > 0 then
    describe('Grid', function()
      local g = m.Grid.connect()
      it('has predefined fields', function()
        assert.has(g, 'id')
        assert.has(g, 'type')
        assert.has(g, 'destination')
        assert.has(g, 'rotation')
        assert.has(g, 'rows')
        assert.has(g, 'cols')
        assert.has(g, 'quads')
      end)
      it(':all()', function()
        local done = false
        seamstress.Timer(function(self)
          if self.stage >= 32 then
            done = true
            self.running = false
          end
          local level = self.stage <= 16 and self.stage - 1 or 32 - self.stage
          g:all(level)
          g:refresh()
        end, 1 / 32)
        repeat coroutine.yield() until done
      end)
      it(':led() and .key()', function()
        local done = false
        local blink = true
        seamstress.Timer(function(self)
          g:led(4, 4, blink and 15 or 0)
          g:refresh()
          blink = not blink
          if done then self.running = false end
        end, 1 / 4)
        g.key = function(x, y, z)
          if x == 4 and y == 4 and z == 0 then done = true end
        end
        repeat coroutine.yield() until done
      end)
    end)
  else
    pending('Grid: not connected!')
  end
  dev_waiting = true
  p = seamstress.async.Promise(function()
    repeat coroutine.yield() until dev_waiting == false
  end)
  seamstress.Timer(function(self)
    if #m.Arc > 0 or self.stage >= 3 then
      dev_waiting = false
      self.running = false
    end
  end)
  p:await()
  if #m.Arc > 0 then
    describe('Arc', function()
      local a = m.Arc.connect()
      it('has predefined fields', function()
        assert.has(a, 'id')
        assert.has(a, 'type')
        assert.has(a, 'destination')
      end)
      it(':all()', function()
        local done = false
        seamstress.Timer(function(self)
          if self.stage >= 32 then
            done = true
            self.running = false
          end
          local level = self.stage <= 16 and self.stage - 1 or 32 - self.stage
          a:all(level)
          a:refresh()
        end, 1 / 32)
        repeat coroutine.yield() until done
      end)
      it(':led() and .delta()', function()
        local done = false
        local blink = true
        seamstress.Timer(function(self)
          for i = 1, 15 do
            a:led(1, i, blink and 15 or 0)
          end
          a:refresh()
          blink = not blink
          if done then self.running = false end
        end, 1 / 4)
        a.delta = function(n, d)
          if n == 1 and d > 0 then done = true end
        end
        repeat coroutine.yield() until done
      end)
    end)
  else
    pending('Arc: not connected!')
  end
end)
