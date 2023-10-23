--- Control class
-- @module params.control

--[[
  based on norns' params/control.lua
  norns params/control.lua first committed by @tehn April 8, 2018
  rewritten for seamstress by @dndrks June 26, 2023
]]

local ControlSpec = require("core/controlspec")

local Control = {}
Control.__index = Control

local tCONTROL = 2

--- constructor.
-- @tparam string id
-- @tparam string name
-- @tparam ControlSpec controlspec
-- @tparam function formatter
-- @tparam boolean allow_pmap
function Control.new(id, name, controlspec, formatter, allow_pmap)
  local p = setmetatable({}, Control)
  p.t = tCONTROL
  if not controlspec then
    controlspec = ControlSpec.UNIPOLAR
  end
  p.id = id
  p.name = name
  p.controlspec = controlspec
  p.formatter = formatter
  p.action = function(x) end
  if allow_pmap == nil then
    p.allow_pmap = true
  else
    p.allow_pmap = allow_pmap
  end

  if controlspec.default then
    p.raw = controlspec:unmap(controlspec.default)
  else
    p.raw = 0
  end
  return p
end

--- map_value.
-- takes 0-1 and returns value scaled by controlspec.
function Control:map_value(value)
  return self.controlspec:map(value)
end

--- get.
-- returns mapped value.
function Control:get()
  return self:map_value(self.raw)
end

--- get_raw.
-- get 0-1.
function Control:get_raw()
  return self.raw
end

--- unmap_value.
-- takes a scaled value and returns 0-1, quantized to step.
function Control:unmap_value(value)
  return self.controlspec:unmap(util.round(value, self.controlspec.step))
end

--- set.
-- accepts a mapped value
function Control:set(value, silent)
  self:set_raw(self:unmap_value(value), silent)
end

--- set_raw.
-- set 0-1.
function Control:set_raw(value, silent)
  local silent = silent or false
  if self.controlspec.wrap then
    while value > 1 do
      value = value - 1
    end
    while value < 0 do
      value = value + 1
    end
  end
  local clamped_value = util.clamp(value, 0, 1)
  if self.raw ~= clamped_value then
    self.raw = clamped_value
    if silent == false then
      self:bang()
    end
  end
  if pmap.data[self.id] ~= nil then
    local midi_prm = pmap.data[self.id]
    midi_prm.value = util.round(util.linlin(midi_prm.out_lo, midi_prm.out_hi, midi_prm.in_lo, midi_prm.in_hi, self.raw))
    if midi_prm.echo then
      local port = pmap.data[self.id].dev
      midi.vports[port]:cc(midi_prm.cc, midi_prm.value, midi_prm.ch)
    end
  end
end

--- get_delta.
-- get increment used for delta()
function Control:get_delta()
  return self.controlspec.quantum
end

--- delta.
-- add delta to current value. checks controlspec for mapped vs not.
-- default division of delta for 100 steps range.
function Control:delta(d)
  self:set_raw(self.raw + d * self:get_delta())
end

--- set_default.
function Control:set_default()
  self:set(self.controlspec.default)
end

--- bang.
function Control:bang()
  self.action(self:get())
end

--- get_range.
-- @return range as table {minval, maxval}
function Control:get_range()
  r = { self.controlspec.minval, self.controlspec.maxval }
  return r
end

--- get_wrap.
-- @return wrap boolean
function Control:get_wrap()
  return self.controlspec.wrap
end

--- string.
-- @return formatted string
function Control:string(quant)
  if self.formatter then
    return self.formatter(self)
  else
    quant = quant or 0.01
    local a = util.round(self:get(), quant)
    if self.controlspec.units == "" then
      return a
    end
    return a .. " " .. self.controlspec.units
  end
end

return Control
