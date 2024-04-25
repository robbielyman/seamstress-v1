--- metro
-- @module metro

--[[
  based on norns' metro.lua
  norns metro.lua first committed by @tehn November 20, 2017
  rewritten for seamstress by @ryleelyman June 2, 2023
]]

--- metro object class
-- @type metro
local Metro = {
  --- constant representing the maximum number of metros.
  -- the actual number is hard-coded in zig
  -- @field num_metros 36
  num_metros = 36,
  metros = {},
  available = {},
  assigned = {},
}
Metro.__index = Metro

--- initialize a new metro if one is available
-- @tparam func|{event=func,time=number,count=integer} arg
-- either a function to be executed repeatedly or a table of arguments
-- @tparam[opt] number arg_time time interval to execute the function; defaults to 1.0
-- @tparam[opt] number count if positive, the number of times to execute;
-- defaults to -1 (infinite repeats)
-- @treturn ?metro metro if one is available
function Metro.init(arg, arg_time, arg_count)
  local event = nil
  local time = arg_time or 1
  local count = arg_count or -1
  if type(arg) == "table" then
	  event = arg.event
    time = arg.time or 1
    count = arg.count or -1
  else
    event = arg
  end

  local id = nil
  for i, val in ipairs(Metro.available) do
	  if val == true then id = i break end
  end
  if id ~= nil then
	  Metro.assigned[id] = true
    Metro.available[id] = false
    local m = Metro.metros[id]
    m.event = event
    m.time = time
    m.count = count
    return m
  end
  print("metro.init: nothing available")
  return nil
end

--- free up a metro slot
-- also stops a metro
-- @tparam integer id (1-36)
function Metro.free(id)
	Metro.metros[id]:stop()
  Metro.available[id] = true
  Metro.assigned[id] = false
end

function Metro.new(id)
  local m = {
    props = {
      id = id,
      time = 1,
      count = -1,
      event = nil,
      init_stage = 1,
    }
    }
    setmetatable(m, Metro)
    return m
end

--- starts a metro
-- @tparam metro self metro
-- @tparam number|{time=number,count=integer,stage=integer} time
-- either a table of arguments or a (fractional time interval in seconds)
-- @tparam[opt] integer count stage to stop at (defaults to -1: infinite)
-- @tparam[opt] integer stage stage to start at
function Metro:start(time, count, stage)
	if type(time) == "table" then
	  if time.time then self.props.time = time.time end
    if time.count then self.props.count = time.count end
    if time.stage then self.props.init_stage = time.stage end
  else
    if time then self.props.time = time end
    if count then self.props.count = count end
    if stage then self.props.init_stage = stage end
  end
  self.is_running = true
  _seamstress.metro_start(self.props.id, self.props.time, self.props.count, self.props.init_stage)
end

--- stops a metro
-- @tparam metro self metro
function Metro:stop()
	_seamstress.metro_stop(self.props.id)
  self.is_running = false
end

Metro.__newindex = function (self, idx, val)
	if idx == "time" then
	  self.props.time = val
    -- NB: metro time isn't applied until next wakeup.
    -- this is true even if you are setting time from the metro callaback;
    -- metro has already gone to sleep when lua main thread gets the event
    -- if you need a fully dynamic metro, re-schedule on the wakeup
    _seamstress.metro_set_time(self.props.id, self.props.time)
  elseif idx == "count" then self.props.count = val
  elseif idx == "init_stage" then self.props.init_stage = val
  else -- FIXME: dunno if this is necessary
    rawset(self, idx, val)
  end
end

Metro.__index = function (self, idx)
	if type(idx) == "number" then return Metro.metros[idx]
  elseif idx == "start" then return Metro.start
  elseif idx == "stop" then return Metro.stop
  elseif idx == "id" then return self.props.id
  elseif idx == "count" then return self.props.count
  elseif idx == "time" then return self.props.time
  elseif idx == "init_stage" then return self.props.init_stage
  elseif self.props[idx] then return self.props[idx]
  else return rawget(self, idx) end
end

setmetatable(Metro, Metro)

for i = 1, Metro.num_metros do
	Metro.metros[i] = Metro.new(i)
  Metro.available[i] = true
  Metro.assigned[i] = false
end

_seamstress.metro = {
  event = function (id, stage)
    local m = Metro.metros[id]
    if m then
	    if m.event then m.event(stage) end
      if m.count > -1 then
	      if stage > m.count then m.is_running = false end
      end
    end
  end,
}

return Metro
