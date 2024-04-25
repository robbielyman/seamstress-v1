--- osc
-- @module osc

--[[
  based on norns' osc.lua
  norns osc.lua first committed by @artfwo April 17, 2018
  rewritten for seamstress by @ryleelyman April 30, 2023
]]

local osc = {}

osc.event = function(path, args, from) end

_seamstress.osc = {
  method_list = {},
  event = function(path, args, from)
    if osc.event then
      osc.event(path, args, from)
    end
  end
}

return osc
