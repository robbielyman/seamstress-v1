--- Arc
-- @module arc

--[[
  based on norns' arc.lua
  norns arc.lua first committed by @artfwo, @scanner-darkly and @okyeron November 15, 2018
  rewritten for seamstress by @ryleelyman April 30, 2023
]]

--- arc object
-- @type arc
local Arc = {}
Arc.__index = Arc

local vport = require("vport")

Arc.devices = {}
Arc.ports = {}

for i = 1, 4 do
  Arc.ports[i] = {
    name = "none",
    device = nil,
    delta = nil,
    key = nil,
    led = vport.wrap("led"),
    all = vport.wrap("all"),
    refresh = vport.wrap("refresh"),
    segment = vport.wrap("segment"),
  }
end

function Arc.new(id, serial, name)
  local a = setmetatable({}, Arc)

  a.id = id
  a.serial = serial
  a.name = name .. " " .. serial
  a.dev = id
  a.delta = nil
  a.key = nil
  a.remove = nil
  a.port = nil

  for i = 1, 4 do
    if Arc.ports[i].name == a.name then return a end
  end
  for i = 1, 4 do
    if Arc.ports[i].name == "none" then
      Arc.ports[i].name = a.name
      break
    end
  end
  return a
end

--- callback executed when arc is plugged in.
-- overwrite in user scripts
-- @tparam arc dev arc object
function Arc.add(dev)
  print("arc added:", dev.id, dev.name, dev.serial)
end

--- attempt to connect to the first available arc.
-- @tparam integer n (1-4)
-- @treturn arc arc
function Arc.connect(n)
  n = n or 1
  return Arc.ports[n]
end

--- set arc led.
-- @tparam arc self arc object
-- @tparam integer ring arc ring (1-4)
-- @tparam integer x arc led (1-based)
-- @tparam inteegr val level (0-15)
function Arc:led(ring, x, val)
  _seamstress.arc_set_led(self.dev, ring, x, val)
end

--- set all leds.
-- @tparam arc self arc object
-- @tparam integer val level (0-15)
function Arc:all(val)
  _seamstress.monome_all_led(self.dev, val)
end

--- update dirty quads.
-- @tparam arc self arc object
function Arc:refresh()
  _seamstress.arc_refresh(self.dev)
end

--- draw a segment.
-- nb: this is calling down to `arc:led` underneath
-- @tparam arc self arc object
-- @tparam integer ring (1-4)
-- @tparam integer from first led (1-64)
-- @tparam inteegr to second led (1-64)
-- @tparam integer level (0-15)
function Arc:segment(ring, from, to, level)
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

  local step = tau / 64
  for i = 1, 64 do
    local a = tau / 64 * (i - 1)
    local b = tau / 64 * i
    local overlap_amt = overlap_segment(tau / 64 * from, tau / 64 * to, a, b)
    local led = util.round(overlap_amt / step * level)
    self:led(ring, i, led)
  end
end

--- limits led intensity.
-- @tparam arc self arc device
-- @tparam integer i level (0-15)
function Arc:intensity(i)
  -- FIXME: is this fine??
  _seamstress.grid_intensity(self.dev, i)
end

function Arc.update_devices()
  for _, device in pairs(Arc.devices) do
    device.port = nil
  end

  for i = 1, 4 do
    Arc.ports[i].device = nil
    for _, device in pairs(Arc.devices) do
      if device.name == Arc.ports[i].name then
        Arc.ports[i].device = device
        device.port = i
      end
    end
  end
end

_seamstress.arc = {
  add = function(id, serial, name)
    local a = Arc.new(id, serial, name)
    Arc.devices[id] = a
    Arc.update_devices()
    if Arc.add ~= nil then Arc.add(a) end
  end,

  remove = function(id)
    local a = Arc.devices[id]
    if a then
      if Arc.ports[a.port].remove then
        Arc.ports[a.port].remove()
      end
      if Arc.remove then
        Arc.remove(Arc.devices[id])
      end
    end
    Arc.devices[id] = nil
    Arc.update_devices()
  end,

  delta = function(id, n, d)
    local arc = Arc.devices[id]
    if arc then
      if arc.delta then
        arc.delta(n, d)
      end
      if arc.port then
        if Arc.ports[arc.port].delta then
          Arc.ports[arc.port].delta(n, d)
        end
      end
    else
      error("no entry for arc " .. id)
    end
  end,


  key = function(id, n, z)
    local arc = Arc.devices[id]
    if arc then
      if arc.key then arc.key(n, z) end
      if arc.port then
        if Arc.ports[arc.port].key then
          Arc.ports[arc.port].key(n, z)
        end
      end
    else
      error("no entry for arc " .. id)
    end
  end,
}

return Arc
