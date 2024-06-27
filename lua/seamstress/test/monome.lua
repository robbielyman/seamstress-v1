local busted = require 'busted'

busted.describe('seamstress.monome.Arc', function()
  local arc = seamstress.monome.Arc.connect()
  local function ifArc(s, f)
    if arc.connected then busted.it(s, f) else busted.pending(s, f) end
  end
  ifArc('can draw to the arc', function()
    local a = 3.0
    local b = 5.0
    local c = 1.0
    local d = 1.1
    local t = 0
    seamstress.update.delta = 1 / 60
    seamstress.update.running = true
    local acc = 0
    local update = seamstress.event.addSubscriber({ 'update' }, function(_, dt)
      acc = acc + dt
      if acc > 1 / 60 then
        t = t + acc
        acc = 0
      else
        return true
      end
      for x = 1, 16 do
        for y = 1, 16 do
          local led = math.abs(math.floor(16 * (math.sin(x / a + t * c) + math.cos(y / b + t * d)))) % 16
          local idx = (x - 1) + (y - 1) * 16
          local r = idx // 64 + 1
          local n = idx % 64 + 1
          arc:led(r, n, led)
        end
      end
      return true, true
    end)
    local draw = seamstress.event.addSubscriber({ 'draw' }, function()
      arc:refresh()
      return true
    end)
    repeat coroutine.yield() until t >= 2
    local done = false
    update:update({
      fn = function()
        arc:all(0)
        return true, true
      end
    })
    draw:update({
      fn = function()
        arc:refresh()
        done = true
        return true
      end
    })
    repeat coroutine.yield() until done
    seamstress.event.removeSubscriber(update.id, { 'update' })
    seamstress.event.removeSubscriber(draw.id, { 'draw' })
  end)
  ifArc('can talk back', function()
    seamstress.update.delta = 1 / 60
    seamstress.update.running = true
    local acc = 0
    local up = true
    local n = 1
    local update = seamstress.event.addSubscriber({ 'update' }, function(_, dt)
      acc = acc + dt
      if acc < 1 / 60 then return true end
      n = n + acc * (up and 4 or -4)
      if n > 64 then
        n = 64
        up = false
      end
      if n < 1 then
        n = 1
        up = true
      end
      acc = 0
      arc:segment(1, 1, n, 15)
      return true, true
    end)
    local draw = seamstress.event.addSubscriber({ 'draw' }, function()
      arc:refresh()
      return true
    end)
    local done = false
    seamstress.event.addSubscriber({ 'monome', 'arc', 'delta' }, function(_, m, d)
      if m == 1 and d > 0 then done = true end
      return true
    end)
    repeat coroutine.yield() until done
    done = false
    update:update { fn = function()
      arc:all(0)
      return true, true
    end }
    draw:update { fn = function()
      arc:refresh()
      done = true
      return true
    end }
    repeat coroutine.yield() until done
    seamstress.event.removeSubscriber(update.id, { 'update' })
    seamstress.event.removeSubscriber(draw.id, { 'draw' })
  end)
end)

busted.describe('seamstress.monome.Grid', function()
  local g = seamstress.monome.Grid.connect()
  local function ifGrid(s, f)
    if g.connected then busted.it(s, f) else busted.pending(s, f) end
  end
  ifGrid('has rows, columns and quads', function()
    local g = seamstress.monome.Grid.connect()
    busted.assert.truthy(g.dev)
    busted.assert(g.connected)
    busted.assert(g.cols > 0)
    busted.assert(g.rows > 0)
    busted.assert(g.quads > 0)
    busted.assert(g.name)
    busted.assert(g.serial)
    busted.assert(g.prefix)
    busted.assert.has_error(function() g.name = "reassigning is not supported" end)
  end)
  ifGrid('can draw to the grid', function()
    local a = 3.0
    local b = 5.0
    local c = 1.0
    local d = 1.1
    local t = 0
    seamstress.update.delta = 1 / 60
    seamstress.update.running = true
    local acc = 0
    local update = seamstress.event.addSubscriber({ 'update' }, function(_, dt)
      acc = acc + dt
      if acc > 1 / 60 then
        t = t + acc
        acc = 0
      else
        return true
      end
      for x = 1, 16 do
        for y = 1, 16 do
          local led = math.abs(math.floor(16 * (math.sin(x / a + t * c) + math.cos(y / b + t * d)))) % 16
          g:led(x, y, led)
        end
      end
      return true, true
    end)
    local draw = seamstress.event.addSubscriber({ 'draw' }, function()
      g:refresh()
      return true
    end)
    repeat coroutine.yield() until t >= 2
    local done = false
    update:update({
      fn = function()
        g:all(0)
        return true, true
      end
    })
    draw:update({
      fn = function()
        g:refresh()
        done = true
        return true
      end
    })
    repeat coroutine.yield() until done
    seamstress.event.removeSubscriber(update.id, { 'update' })
    seamstress.event.removeSubscriber(draw.id, { 'draw' })
  end)
  ifGrid('can talk back', function()
    seamstress.update.delta = 0.5
    seamstress.update.running = true
    local on = true
    local acc = 0
    local update = seamstress.event.addSubscriber({ 'update' }, function(_, dt)
      acc = acc + dt
      if acc < 0.5 then return true end
      acc = 0
      g:led(1, 1, on and 15 or 0)
      on = not on
      return true, true
    end)
    local draw = seamstress.event.addSubscriber({ 'draw' }, function()
      g:refresh()
      return true
    end)
    local done = false
    seamstress.event.addSubscriber({ 'monome', 'grid', 'key' }, function(_, x, y, z)
      if x == 1 and y == 1 and z == 0 then done = true end
      return true
    end)
    repeat coroutine.yield() until done
    update:update({
      fn = function()
        g:all(0)
        return true, true
      end
    })
    draw:update({
      fn = function()
        g:refresh()
        done = true
        return true
      end
    })
    repeat coroutine.yield() until done
    seamstress.event.removeSubscriber(update.id, { 'update' })
    seamstress.event.removeSubscriber(draw.id, { 'draw' })
  end)
  ifGrid('can talk back two ways', function()
    seamstress.update.delta = 0.5
    seamstress.update.running = true
    local on = true
    local acc = 0
    local update = seamstress.event.addSubscriber({ 'update' }, function(_, dt)
      acc = acc + dt
      if acc < 0.5 then return true end
      acc = 0
      g:led(4, 4, on and 15 or 0)
      on = not on
      return true, true
    end)
    local draw = seamstress.event.addSubscriber({ 'draw' }, function()
      g:refresh()
      return true
    end)
    local done = false
    g.key = function(x, y, z)
      if x == 4 and y == 4 and z == 0 then done = true end
    end
    repeat coroutine.yield() until done
    update:update({
      fn = function()
        g:all(0)
        return true, true
      end
    })
    draw:update({
      fn = function()
        g:refresh()
        done = true
        return true
      end
    })
    repeat coroutine.yield() until done
    seamstress.event.removeSubscriber(update.id, { 'update' })
    seamstress.event.removeSubscriber(draw.id, { 'draw' })
  end)
end)
