-- Binary class
-- @module params.Binary

local binary = {}
binary.__index = binary

local tBINARY = 3

function binary.new(id, name, behavior, default, allow_pmap)
	local t = setmetatable({}, binary)
  t.t = tBINARY
  t.id = id
  t.name = name
  t.default = default or 0
  t.value = t.default
  t.behavior = behavior or 'trigger'
  t.action = function () end
  if allow_pmap == nil then t.allow_pmap = true else t.allow_pmap = allow_pmap end
  return t
end

function binary:get()
	return self.value
end

function binary:set(v, silent)
	silent = silent or false
  v = (v > 0) and 1 or 0
  if self.value ~= v then
    self.value = v
    if silent == false then
      if self.behavior ~= 'trigger' or v == 1 then
        self:bang()
      end
    end
  end
end

function binary:delta(d)
	if self.behavior == 'momentary' then
    self:set(d)
  elseif self.behavior == 'toggle' then
    if d ~= 0 then self:set(self.value == 0 and 1 or 0) end
  elseif d~=0 then
    self:bang()
  end
end

function binary:set_default()
	self:set(self.default)
end

function binary:bang()
	self.action(self.value)
end

function binary:string()
  if self.behavior == 'trigger' then return '' end
  return self.value == 1 and "on" or "off"
end

function binary:get_range()
	return {0,1}
end

return binary
