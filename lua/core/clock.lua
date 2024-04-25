--- clock coroutines
-- @module clock

--[[
  based on norns' clock.lua
  norns clock.lua first committed by @artfwo April 11, 2019
  rewritten for seamstress by @ryleelyman June 16, 2023
]]

local clock = {}
local SCHEDULE_SLEEP <const> = 0
local SCHEDULE_SYNC <const> = 1

_seamstress.clock = {
  threads = {},
  resume = function(id, ...)
    local coro = _seamstress.clock.threads[id]
    local result, mode, time, offset = coroutine.resume(coro, ...)
    if coroutine.status(coro) == "dead" then
      if result then clock.cancel(id) else error(mode) end
    else
      if result and mode ~= nil then
        if mode == SCHEDULE_SLEEP then
          _seamstress.clock_schedule_sleep(id, time)
        elseif mode == SCHEDULE_SYNC then
          if offset ~= nil then
            _seamstress.clock_schedule_sync(id, time, offset)
          else
            _seamstress.clock_schedule_sync(id, time)
          end
        else
          error("invalid clock scheduler mode: " .. mode "")
        end
      end
    end
  end,
}

local function new_id()
  for i = 1, 100 do
    if _seamstress.clock.threads[i] == nil then return i end
  end
  error("no clocks free!")
end

--- create and start a coroutine.
-- @tparam function f coroutine function
-- @param[opt] ... any extra arguments passed to f
-- @treturn ?integer coroutine id that can be used with clock.cancel
-- @see clock.cancel
function clock.run(f, ...)
  local co = coroutine.create(f)
  local id = new_id()
  if id then
    _seamstress.clock.threads[id] = co
    _seamstress.clock.resume(id, ...)
    return id
  end
end

--- stop a coroutine started by clock.run
-- @tparam integer id coroutine id
-- @see clock.run
function clock.cancel(id)
  _seamstress.clock_cancel(id)
  _seamstress.clock.threads[id] = nil
end

--- returns the current time in beats since reset was called.
-- @treturn number beats time in beats
function clock.get_beats()
  return _seamstress.clock_get_beats()
end

--- returns the current tempo in bpm
-- @treturn number bpm
function clock.get_tempo()
  return _seamstress.clock_get_tempo()
end

--- returns the length in seconds of a single beat
-- @treturn number seconds
function clock.get_sec_per_beat()
  local bpm = clock.get_tempo()
  return 60 / bpm
end

--- alias to get_sec_per_beat for norns compatibility
clock.get_beat_sec = clock.get_sec_per_beat

--- sets the clock source
-- @tparam string source "internal", "midi", or "link"
function clock.set_source(source)
  if type(source) == "number" then
    _seamstress.clock_set_source(source - 1)
  elseif source == "internal" then
    _seamstress.clock_set_source(0)
  elseif source == "midi" then
    _seamstress.clock_set_source(1)
  elseif source == "link" then
    _seamstress.clock_set_source(2)
  else
    error("unknown clock source: " .. source)
  end
end

clock.transport = {
  --- callback when clock starts
  start = function() end,
  --- callback when clock stops
  stop = function() end,
  --- callback when the clock beat number is reset
  reset = function() end,
}

clock.internal = {
  set_tempo = function(bpm)
    return _seamstress.clock_internal_set_tempo(bpm)
  end,
  start = function()
    return _seamstress.clock_internal_start()
  end,
  stop = function()
    return _seamstress.clock_internal_stop()
  end,
}

clock.link = {
  set_tempo = function(bpm)
    return _seamstress.clock_link_set_tempo(bpm)
  end,
  start = function()
    return _seamstress.clock_link_start()
  end,
  stop = function()
    return _seamstress.clock_link_stop()
  end,
}

clock.tempo_change_handler = nil

_seamstress.transport = {
  start = function()
    _seamstress.transport_active = true
    -- paramsMenu.redraw()
    if clock.transport.start then
      clock.transport.start()
    end
  end,
  stop = function()
    _seamstress.transport_active = false
    -- paramsMenu.redraw()
    if clock.transport.stop then
      clock.transport.stop()
    end
  end,
  reset = function()
    if clock.transport.reset then
      clock.transport.reset()
    end
  end,
}

-- TODO
function clock.add_params() end

return clock
