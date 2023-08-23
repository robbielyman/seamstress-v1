--- osc
-- @module osc

--[[
  based on norns' osc.lua
  norns osc.lua first committed by @artfwo April 17, 2018
  rewritten for seamstress by @ryleelyman April 30, 2023
]]

local OSC = {}

OSC.__index = OSC

--- callback executed when seamstress receives OSC
-- overwrite in user scripts
-- @tparam string path an osc path `/like/this`
-- @tparam table args arguments from the OSC message
-- @tparam {host,port} from table containing sender information
-- @function osc.event
function OSC.event(path, args, from) end

--- send OSC message
-- @tparam[opt] {host,port} to address (both strings)
-- @tparam string path an osc path `/like/this`
-- @tparam[opt] table args an array of arguments to the OSC message
function OSC.send(to, path, args)
  if not to then
    to = { "localhost", _seamstress.remote_port }
  end
  _seamstress.osc_send(to, path, args)
end

_seamstress.osc = {}

function _seamstress.osc.event(path, args, from)
  if OSC.event ~= nil then
    OSC.event(path, args, from)
  end
end

return OSC
