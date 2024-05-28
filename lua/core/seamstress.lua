--- startup file
-- @script seamstress

--[[
  seamstress is inspired by monome's norns.
  first commit by @ryleelyman April 30, 2023
]]

local seamstress = {
  monome = {
    grid = require "core/grid",
    arc = require "core/arc",
  },
  osc = require "core/osc",
  path = _seamstress.path,

  --- init callback to be overwritten in user scripts
  init = function() end,
  --- redraw callback to be overwritten in user scripts
  redraw = function() end,
  --- cleanup function to be overwritten in user scripts
  cleanup = function() end,
}

return seamstress
