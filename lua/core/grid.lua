--- grid
-- @module grid

--[[
  based on norns' grid.lua
  norns grid.lua first committed by @catfact March 14, 2017
  rewritten for seamstress by @ryleelyman April 30, 2023
]]

--- grid object
-- @type grid
local Grid = {}
Grid.__index = Grid

local vport = require("vport")

Grid.devices = {}
Grid.ports = {}

for i = 1, 4 do
  Grid.ports[i] = {
    name = "none",
    device = nil,
    delta = nil,
    key = nil,
    led = vport.wrap("led"),
    all = vport.wrap("all"),
    refresh = vport.wrap("refresh"),
    rotation = vport.wrap("rotation"),
    intensity = vport.wrap("intensity"),
    tilt_enable = vport.wrap("tilt_enable"),
    cols = 0,
    rows = 0,
  }
end

function Grid.new(id, serial, name)
  local g = setmetatable({}, Grid)

  g.id = id
  g.serial = serial
  g.name = name .. " " .. serial
  g.dev = id
  g.key = nil
  g.tilt = nil
  g.remove = nil
  g.rows = _seamstress.grid_rows(id)
  g.cols = _seamstress.grid_cols(id)

  for i = 1, 4 do
    if Grid.ports[i].name == g.name then
      return g
    end
  end
  for i = 1, 4 do
    if Grid.ports[i].name == "none" then
      Grid.ports[i].name = g.name
      break
    end
  end

  return g
end

--- callback called when a grid is plugged in;
-- overwrite in user scripts
-- @tparam grid dev grid object
-- @function grid.add
function Grid.add(dev)
  print("grid added:", dev.id, dev.name, dev.serial)
end

--- attempt to connect grid at port `n`
-- @tparam integer n (1-4)
-- @function grid.connect
-- @treturn grid grid
function Grid.connect(n)
  n = n or 1
  return Grid.ports[n]
end

--- callback executed when a grid is removed;
-- overwrite in user scripts
-- @tparam grid dev grid object
-- @function grid.remove
function Grid.remove(dev) end

--- set grid rotation
-- @tparam grid self grid object
-- @tparam integer val rotation
-- @todo what does this expect?
-- @function grid:rotation
function Grid:rotation(val)
  _seamstress.grid_set_rotation(self.dev, val)
end

--- set grid led
-- @tparam grid self grid object
-- @tparam integer x x-coordinate of led (1-based)
-- @tparam integer y y-coordinate of led (1-based)
-- @tparam integer val (0-15)
-- @function grid:led
function Grid:led(x, y, val)
  _seamstress.grid_set_led(self.dev, x, y, val)
end

--- set all grid leds
-- @tparam grid self grid object
-- @tparam integer val (0-15)
-- @function grid:all
function Grid:all(val)
  _seamstress.monome_all_led(self.dev, val)
end

--- refresh dirty quads
-- @tparam grid self grid object
-- @function grid:refresh
function Grid:refresh()
  _seamstress.grid_refresh(self.dev)
end

--- limit led intensity
-- @tparam grid self grid object
-- @tparam integer i intensity limit
-- @function grid:intensity
function Grid:intensity(i)
  _seamstress.monome_intensity(self.dev, i)
end

--- enable/disable grid tilt sensor
-- @tparam grid self grid object
-- @tparam integer sensor (1-based)
-- @tparam bool tilt enable/disable flag
-- @function grid:tilt
function Grid:tilt(sensor, boolean)
  if boolean then
    _seamstress.grid_tilt_enable(self.dev, sensor)
  else
    _seamstress.grid_tilt_disable(self.dev, sensor)
  end
end

function Grid.update_devices()
  for _, device in pairs(Grid.devices) do
    device.port = nil
  end

  for i = 1, 4 do
    Grid.ports[i].device = nil
    Grid.ports[i].rows = 0
    Grid.ports[i].cols = 0
    for _, device in pairs(Grid.devices) do
      if device.name == Grid.ports[i].name then
        Grid.ports[i].device = device
        Grid.ports[i].rows = device.rows
        Grid.ports[i].cols = device.cols
        device.port = i
      end
    end
  end
end

_seamstress.grid = {
  add = function(id, serial, name, dev)
    local g = Grid.new(id, serial, name, dev)
    Grid.devices[id] = g
    Grid.update_devices()
    if Grid.add ~= nil then
      Grid.add(g)
    end
  end,

  remove = function(id)
    local g = Grid.devices[id]
    if g then
      if Grid.ports[g.port].remove then
        Grid.ports[g.port].remove()
      end
      if Grid.remove then
        Grid.remove(Grid.devices[id])
      end
    end
    Grid.devices[id] = nil
    Grid.update_devices()
  end,

  key = function(id, x, y, z)
    local grid = Grid.devices[id]
    if grid ~= nil then
      if grid.key then
        grid.key(x, y, z)
      end

      if grid.port then
        if Grid.ports[grid.port].key then
          Grid.ports[grid.port].key(x, y, z)
        end
      end
    else
      error("no entry for grid " .. id)
    end
  end,

  tilt = function(id, sensor, x, y, z)
    local grid = Grid.devices[id]
    if grid ~= nil then
      if grid.tilt then
        grid.tilt(sensor, x, y, z)
      end
      if grid.port then
        if Grid.ports[grid.port].tilt then
          Grid.ports[grid.port].tilt(sensor, x, y, z)
        end
      end
    else
      error("no entry for grid " .. id)
    end
  end,
}

return Grid

