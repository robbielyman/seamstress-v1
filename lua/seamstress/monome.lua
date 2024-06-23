-- we depend on osc, so load it

local monome = {
  Grid = {
    devices = {},
  },
  Arc = {
    devices = {},
  },
}

---connects to the nth Grid device
---@param n integer?
---@return Grid # well, effectively
monome.Grid.connect = function(n)
  n = n or 1
  if not monome.Grid.devices[n] then
    local g = monome.Grid.new()
    monome.Grid.devices[n] = setmetatable({
      dev = g,
    }, {
      __index = function(t, k)
        if k == "dev" then return rawget(t, k) end
        return rawget(t, "dev")[k]
      end,
      __newindex = function(t, k, v)
        if k == "dev" then
          rawset(t, k, v)
          return
        end
        t.dev[k] = v
      end
    })
  end
  return monome.Grid.devices[n]
end

---draw a segment.
---nb: this is calling down to `Arc:led` underneath
---@param self Arc
---@param ring integer # (1-4)
---@param from integer # first led (1-64)
---@param to integer # second led (1-64)
---@param level integer # (0-15)
local function segment(self, ring, from, to, level)
  local tau = 2 * math.pi

  local function overlap(a, b, c, d)
    if a > b then
      return overlap(a, tau, c, d) + overlap(0, b, c, d)
    elseif c > d then
      return overlap(a, b, c, tau) + overlap(a, b, 0, d)
    else
      return math.max(0, math.min(b, d) - math.max(a, c))
    end
  end

  local function overlap_segment(a, b, c, d)
    return overlap(a % tau, b % tau, c % tau, d % tau)
  end

  local leds = {}
  local step = tau / 64
  for i = 1, 64 do
    local a = tau / 64 * (i - 1)
    local b = tau / 64 * i
    local overlap_amt = overlap_segment(tau / 64 * from, tau / 64 * to, a, b)
    leds[i] = overlap_amt / step * level
    self:led(ring, i, leds[i])
  end
end


---connects to the nth Arc device
---@param n integer?
---@return Arc # well, effectively
monome.Arc.connect = function(n)
  n = n or 1
  if not monome.Arc.devices[n] then
    local a = monome.Arc.new()
    monome.Arc.devices[n] = setmetatable({
      dev = a,
    }, {
      __index = function(t, k)
        if k == "dev" then return rawget(t, k) end
        return rawget(t, "dev")[k]
      end,
      __newindex = function(t, k, v)
        if k == "dev" then
          rawset(t, k, v)
          return
        end
        t.dev[k] = v
      end
    })
    monome.Arc.devices[n].segment = segment
  end
  return monome.Arc.devices[n]
end

---callback when a Grid device is added
---@param dev Grid
monome.Grid.add = function(dev)
  local unused, grid
  for i, g in ipairs(monome.Grid.devices) do
    if g.serial == dev.serial then
      if g.add then g.add(dev.name, dev.serial) end
      seamstress.event.publish({ 'monome', 'Grid', 'add' }, g, dev.name, dev.serial)
      return
    elseif g.serial == nil and unused == nil then
      unused = i
    end
  end
  if unused then
    monome.Grid.devices[unused].dev = dev
    grid = monome.Grid.devices[unused]
    if grid.add then grid.add(dev.name, dev.serial) end
  else
    grid = monome.Grid.connect(#monome.Grid.devices + 1)
    grid.dev = dev --[[@as userdata]]
  end
  seamstress.event.publish({ 'monome', 'Grid', 'add' }, grid, dev.name, dev.serial)
end

---callback when an Arc device is added
---@param dev Arc
monome.Arc.add = function(dev)
  local unused, arc
  for i, a in ipairs(monome.Arc.devices) do
    if a.serial == dev.serial then
      if a.add then a.add(dev.name, dev.serial) end
      seamstress.event.publish({ 'monome', 'Arc', 'add' }, a, dev.name, dev.serial)
      return
    elseif a.serial == nil and unused == nil then
      unused = i
    end
  end
  if unused then
    monome.Arc.devices[unused].dev = dev
    arc = monome.Arc.devices[unused]
    if arc.add then arc.add(dev.name, dev.serial) end
  else
    arc = monome.Arc.connect(#monome.Arc.devices + 1)
    arc.dev = dev --[[@as userdata]]
  end
  arc.segment = segment
  seamstress.event.publish({ 'monome', 'Arc', 'add' }, arc, dev.name, dev.serial)
end

---callback when an Arc device is removed
---@param dev Arc
monome.Arc.remove = function(dev)
  for _, a in ipairs(monome.Arc.devices) do
    if a.serial == dev.serial then
      if a.remove then a.remove(dev.name, dev.serial) end
      seamstress.event.publish({ 'monome', 'Arc', 'remove' }, a, dev.name, dev.serial)
      return
    end
  end
  warn('no device found for arc ' .. dev.name .. ' ' .. dev.serial)
end

---callback when a Grid device is removed
---@param dev Grid
monome.Grid.remove = function(dev)
  for _, g in ipairs(monome.Grid.devices) do
    if g.serial == dev.serial then
      if g.remove then g.remove(dev.name, dev.serial) end
      seamstress.event.publish({ 'monome', 'Grid', 'remove' }, g, dev.name, dev.serial)
      return
    end
  end
  warn('no device found for grid ' .. dev.name .. ' ' .. dev.serial)
end

return { monome, false }
