-- Text class
-- @module params.text

--[[
  based on norns' params/text.lua
  norns params/text.lua first committed by @tehn March 19, 2020
  rewritten for seamstress by @dndrks Aug 23, 2023
]]

local Text = {}
Text.__index = Text

local tText = 4

function Text.new(id, name, text, locked, check)
  local o = setmetatable({}, Text)
  o.t = tText
  o.id = id
  o.name = name
  o.text = text or ""
  o.action = function() end
  o.locked = locked ~= nil and locked or false
  o.check = check
  return o
end

function Text:get()
  return self.text
end

function Text:set(v, silent)
  local silent = silent or false
  if self.text ~= v then
    self.text = v
    if silent == false then
      self:bang()
    end
  end
end

function Text:delta(d)
  --none
end

function Text:set_default()
  --none
end

function Text:bang()
  self.action(self.text)
end

function Text:string()
  -- any formatting here? concat?
  return self.text
end

return Text
