-- Separator class
-- @module params.separator

--[[
  based on norns' params/separator.lua
  norns params/separator.lua committed by @artfwo May 8, 2018
  rewritten for seamstress by @dndrks June 26, 2023
]]

local Separator = {}
Separator.__index = Separator

local tSEPARATOR = 0

function Separator.new(id, name)
  local s = setmetatable({}, Separator)
  s.name = name or (id or "separator")
  s.id = id or s.name
  s.t = tSEPARATOR
  s.action = function() end
  return s
end

function Separator:get()
  return ""
end

function Separator:set(v) end
function Separator:delta(d) end
function Separator:set_default() end
function Separator:bang() end

function Separator:string()
  return self.name
end

return Separator
