--- ParamSet class
-- @module paramset

local control = require 'core/params/control'
local group = require 'core/params/group'
local binary = require 'core/params/binary'
local separator = require 'core/params/separator'
local controlspec = require 'core/controlspec'

local ParamSet = {
  tSEPARATOR = 0,
  tGROUP = 1,
  tCONTROL = 2,
  tBINARY = 3,
  sets = {}
}

ParamSet.__index = ParamSet

--- constructor.
-- @tparam string id
-- @tparam string name
function ParamSet.new(id, name)
  local ps = setmetatable({}, ParamSet)
  ps.id = id or ""
  ps.name = name or ""
  ps.params = {}
  ps.count = 0
  ps.hidden = {}
  ps.lookup = {}
  ps.group = 0
  ps.action_write = nil
  ps.action_read = nil
  ps.action_delete = nil
  ParamSet.sets[ps.id] = ps
  return ps
end

--- add generic parameter.
-- helper function to add param to paramset
-- two uses:
-- - pass "param" table with optional "action" function
-- - pass keyed table to generate "param" table. required keys are "type" and "id"
function ParamSet:add(args)
  local param = args.param
  if param == nil then
    if args.type == nil then
      print("paramset.add() error: type required")
      return nil
    elseif args.id == nil then
      print("paramset.add() error: id required")
      return nil
    end

    local id = args.id
    local name = args.name or id

    if args.type == "number"  then
      self:add_number(id, name, args.min, args.max, args.default, args.units)
    elseif args.type == "option" then
      self:add_option(id, name, args.options, args.default)
    elseif args.type == "control" then
      self:add_control(id, name, args.controlspec, args.formatter)
    elseif args.type == "binary" then
      self:add_binary(id, name, args.behavior or 'toggle', args.default)
    elseif args.type == "trigger" then
      self:add_trigger(id, name)
    elseif args.type == "separator" then
      self:add_separator(id, name)
    elseif args.type == "group" then
      self:add_group(id, name, args.n)
    else
      print("paramset.add() error: unknown type")
    end

    return nil
  end

  local overwrite = true
  if self.lookup[param.id] ~= nil and param.t ~= 0 and param.t ~= 1 then
    print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    print("!!!!! BEWARE: parameter ID collision: ".. param.id)
    print("!!!!! OVERWRITING ".. param.id)
  elseif self.lookup[param.id] ~= nil and param.t == 0 then
    if params:lookup_param(param.id).t ~= 0 then
      print("! separator ID <"..param.id.."> collides with a non-separator parameter, will not overwrite")
      overwrite = false
    elseif param.id ~= "separator" then
      print("! stealing separator ID <"..param.id.."> from earlier separator")
      overwrite = true
    end
  elseif self.lookup[param.id] ~= nil and param.t == 1 then
    if params:lookup_param(param.id).t ~= 1 then
      print("! group ID <"..param.id.."> collides with a non-group parameter, will not overwrite")
      overwrite = false
    elseif param.id ~= "group" then
      print("! stealing group ID <"..param.id.."> from earlier group")
      overwrite = true
    end
  end

  param.save = true

  table.insert(self.params, param)
  self.count = self.count + 1
  self.group = self.group - 1
  if overwrite == true then
    self.lookup[param.id] = self.count
  end
  self.hidden[self.count] = false
  if args.action then
    param.action = args.action
  end
end

--- add number.
-- @tparam string id identifier slug (no spaces)
-- @tparam string name user-facing name (can contain spaces)
-- @tparam number min minimum value
-- @tparam number max maximum value
-- @tparam number default default / initial value
-- @tparam string units
function ParamSet:add_number(id, name, min, max, default, units)
  local cs = controlspec.new(min,max,'lin',1,default,units,1/math.abs(max-min))
  self:add { param=control.new(id, name, cs) }
  params.params[params.lookup[id]].is_number = true
end

--- add option.
-- @tparam string id (no spaces)
-- @tparam string name (can contain spaces)
-- @param options
-- @param default
function ParamSet:add_option(id, name, options, default)
  -- self:add { param=option.new(id, name, options, default) }
  local cs = controlspec.new(1,#options,'lin',1,default,units,1/(#options-1))
  local frm = function(param) return options[(type(param) == 'table' and param:get() or param)] end
  self:add { param=control.new(id, name, cs, frm) }
end

--- add binary.
-- @tparam string id (no spaces)
-- @tparam string name (can contain spaces)
-- @tparam string behavior "toggle" or "trigger" or "momentary"; defaults to "toggle"
-- @tparam integer default 0 or 1
function ParamSet:add_binary(id, name, behavior, default)
	self:add { param = binary.new(id, name, behavior or "toggle", default) }
end

--- add trigger.
-- @tparam string id (no spaces)
-- @tparam string name (can contain spaces)
function ParamSet:add_trigger(id, name)
	self:add { param = binary.new(id, name, "trigger") }
end

--- add control.
-- @tparam string id (no spaces)
-- @tparam string name (can contain spaces)
-- @tparam controlspec controlspec
-- @param formatter
function ParamSet:add_control(id, name, controlspec, formatter)
  self:add { param=control.new(id, name, controlspec, formatter) }
end

--- add separator.
-- id and name are optional.
-- if neither id or name are provided,
-- separator will be named 'separator'
-- and will not have a unique parameter index.
-- separators which have their own parameter index
-- can be hidden / shown.
-- @tparam string id (no spaces)
-- @tparam string name (can contain spaces)
function ParamSet:add_separator(id, name)
  self:add { param=separator.new(id, name) }
end

--- add parameter group.
-- groups cannot be nested,
-- i.e. a group cannot be made within a group.
-- id and name are optional.
-- if neither id or name are provided,
-- group will be named 'group'
-- and will not have a unique parameter index.
-- groups which have their own parameter index
-- can be hidden / shown.
-- @tparam string id (no spaces)
-- @tparam string name (can contain spaces)
-- @tparam int n
function ParamSet:add_group(id, name, n)
  if id == nil then id = "group" end
  n = type(name) == "number" and name or (n or 1)
  if self.group < 1 then
    self:add { param=group.new(id, name, n) }
    self.group = type(name) == "number" and name or n
  else
    print("ERROR: paramset cannot nest GROUPs")
  end
end

--- print.
function ParamSet:print()
  print("paramset ["..self.name.."]")
  for k,v in pairs(self.params) do
    local name = v.name or 'unnamed' -- e.g., separators
    print(k.." "..name.." = "..v:string())
  end
end

--- list.
-- lists param id's
function ParamSet:list()
  print("paramset ["..self.name.."]")
  for k,v in pairs(self.params) do
    if v.id then
      print(v.id)
    end
  end
end

--- name.
-- @tparam string index
function ParamSet:get_name(index)
  if type(index)=="string" then index = self.lookup[index] end
  return self.params[index].name or ""
end

--- query whether param used the number template.
-- @tparam string index
function ParamSet:is_number(index)
  if type(index)=="string" then index = self.lookup[index] end
  return self.params[index].is_number or false
end

--- id.
-- @tparam number index
function ParamSet:get_id(index)
  return self.params[index].id
end

--- string.
-- @param index
-- @param[opt] quant rounding qunatification
function ParamSet:string(index, quant)
  local param = self:lookup_param(index)
  return param:string(quant)
end

--- set.
-- @param index
-- @param v value
-- @tparam boolean silent
function ParamSet:set(index, v, silent)
  local param = self:lookup_param(index)
  return param:set(v, silent)
end

--- set_raw (for control types only).
-- @param index
-- @param v value
-- @tparam boolean silent
function ParamSet:set_raw(index, v, silent)
  local param = self:lookup_param(index)
  param:set_raw(v, silent)
end

--- get.
-- @param index
function ParamSet:get(index)
  local param = self:lookup_param(index)
  return param:get()
end

--- get_raw (for control types only).
-- @param index
function ParamSet:get_raw(index)
  local param = self:lookup_param(index)
  return param:get_raw()
end

--- delta.
-- @param index
-- @tparam number d delta
function ParamSet:delta(index, d)
  local param = self:lookup_param(index)
  param:delta(d)
end

--- set action.
-- @param index
-- @tparam function func set the action for this index
function ParamSet:set_action(index, func)
  local param = self:lookup_param(index)
  param.action = func
end

--- set save state.
-- @param index
-- @param state set the save state for this index
function ParamSet:set_save(index, state)
  local param = self:lookup_param(index)
  param.save = state
end

--- get type.
-- @param index
function ParamSet:t(index)
  local param = self:lookup_param(index)
  if param ~= nil then
    return param.t
  end
end

--- get range
-- @param index
function ParamSet:get_range(index)
  local param = self:lookup_param(index)
  return param:get_range()
end

--- get whether or not parameter should be pmap'able
-- @param index
function ParamSet:get_allow_pmap(index)
  local param = self:lookup_param(index)
  local allow = param.allow_pmap
  if param == nil then return true end
  return allow
end

--- set visibility to hidden.
-- @param index
function ParamSet:hide(index)
  if type(index)=="string" then index = self.lookup[index] end
  self.hidden[index] = true
end

--- set visiblility to show.
-- @param index
function ParamSet:show(index)
  if type(index)=="string" then index = self.lookup[index] end
  self.hidden[index] = false
end

--- get visibility.
-- parameters are visible by default.
-- @param index
function ParamSet:visible(index)
  if type(index)=="string" then index = self.lookup[index] end
  return not self.hidden[index]
end

local function quote(s)
  return '"'..s:gsub('"', '\\"')..'"'
end

local function unquote(s)
  return s:gsub('^"', ''):gsub('"$', ''):gsub('\\"', '"')
end

-- get param object at index; useful for meta-programming tasks like changing a param once it's been created.
-- @param index
function ParamSet:lookup_param(index)
  if type(index) == "string" and self.lookup[index] then
    return self.params[self.lookup[index]]
  elseif self.params[index] then
    return self.params[index]
  else
    error("invalid paramset index: "..index)
  end
end

--- bang all params.
function ParamSet:bang()
  for _,v in pairs(self.params) do
    if not (v.t == self.tBINARY and v.behavior == 'trigger') then
      v:bang()
    end
  end
end

--- clear.
function ParamSet:clear()
  self.name = ""
  self.params = {}
  self.count = 0
  self.action_read = nil 
  self.action_write = nil
  self.action_delete = nil
  self.lookup = {}
end

return ParamSet
