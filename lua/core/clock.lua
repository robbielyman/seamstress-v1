--- clock coroutines
-- @module clock

local clock = {}

_seamstress.clock = {}
_seamstress.clock.threads = {}
local clock_id_counter = 1
local function new_id()
  local id = clock_id_counter
  clock_id_counter = clock_id_counter + 1
  return id
end

--- create and start a coroutine.
-- @tparam function f coroutine functions
-- @param[opt] ... any extra arguments passed to f
-- @treturn integer coroutine id that can be used with clock.cancel
-- @see clock.cancel
function clock.run(f, ...)
  local co = coroutine.create(f)
  local id = new_id()
  _seamstress.clock.threads[id] = co
  _seamstress.clock_resume(id, co, ...)
  return id
end

--- stop a coroutine started by clock.run.
-- @tparam integer id coroutine id
-- @see clock.run
function clock.cancel(id)
  _seamstress.clock_cancel(id)
  _seamstress.clock.threads[id] = nil
end

local SCHEDULE_SLEEP = 0
local SCHEDULE_SYNC = 1
--- suspend coroutine and schedule resuming time.
-- call from *within* a coroutine function started by `clock.run`
-- @tparam float s seconds to wait for
function clock.sleep(...)
  return coroutine.yield(SCHEDULE_SLEEP, ...)
end

--- suspend coroutine and schedule resuming sync quantum.
-- call from *within* a coroutine function started by `clock.run`
-- @tparam float beat sync quantum (may be larger than 1)
-- @tparam[opt] float offset if set, this will be added to the sync quantum
function clock.sync(...)
  return coroutine.yield(SCHEDULE_SYNC, ...)
end

--- returns the current time in beats since reset was called.
-- @treturn number beats time in beats
function clock.get_beats()
  _seamstress.clock_get_beats()
end

--- returns the current tempo in bpm
-- @treturn number bpm
function clock.get_tempo()
  _seamstress.clock_get_tempo()
end

--- returns the length in seconds of a single beat
-- @treturn number seconds
function clock.get_beat_per_sec()
  local bpm = clock.get_tempo()
  return 60 / bpm
end

clock.transport = {
  --- callback when clock starts
  start = function() end,
  --- callback when the clock stops
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
  end
}

clock.tempo_change_handler = nil

_seamstress.transport = {
  start = function()
    if clock.transport.start then clock.transport.start() end
  end,
  stop = function()
    if clock.transport.stop then clock.transport.stop() end
  end,
  reset = function()
    if clock.transport.reset then clock.transport.reset() end
  end,
}

function clock.add_params()
  local send_midi_clock = {}
  params:add_group("CLOCK", "CLOCK", 19)
  params:add_option("clock_source", "source", { "internal" },
    seamstress.state.clock.source)
  params:set_action("clock_source",
    function(x)
      if x == 1 then clock.internal.set_tempo(params:get("clock_tempo")) end
    end)
  params:set_save("clock_source", false)
  params:add_number("clock_tempo", "tempo", 1, 300, seamstress.state.clock.tempo)
  params:set_action("clock_tempo",
    function(bpm)
      local source = params:string("clock_source")
      if source == "internal" then clock.internal.set_tempo(bpm) end
      seamstress.state.clock.tempo = bpm
      if clock.tempo_change_handler ~= nil then
        clock.tempo_change_handler(bpm)
      end
    end)
  params:set_save("clock_tempo", false)
  params:add_trigger("clock_reset", "reset")
  params:set_action("clock_reset",
    function()
      local source = params:string("clock_source")
      if source == "internal" then clock.internal.start() end
    end)
  params:add_separator("midi_clock_out_separator", "midi clock out")
  for i = 1, 16 do
    local short_name = string.len(midi.voutports[i].name) <= 20 and midi.voutports[i].name or
    util.acronym(midi.voutports[i].name)
    params:add_binary("clock_midi_out_" .. i, i .. ". " .. short_name, "toggle", seamstress.state.clock.midi_out[i])
    params:set_action("clock_midi_out_" .. i,
      function(x)
        if x == 1 then
          if not tab.contains(send_midi_clock, i) then
            table.insert(send_midi_clock, i)
          end
        else
          if tab.contains(send_midi_clock, i) then
            table.remove(send_midi_clock, tab.key(send_midi_clock, i))
          end
        end
        seamstress.state.clock.midi_out[i] = x
      end)
    if short_name ~= "none" and midi.voutports[i].connected then
      params:show("clock_midi_out_" .. i)
    else
      params:hide("clock_midi_out_" .. i)
    end
    params:set_save("clock_midi_out_" .. i, false)
  end
  params:lookup_param("clock_tempo"):bang()

  -- executes midi out
  clock.run(function()
    while true do
      clock.sync(1 / 24)
      for i = 1, #send_midi_clock do
        local port = send_midi_clock[i]
        midi.voutports[port]:clock()
      end
    end
  end)

  -- update tempo param value (currently a no-op)
  clock.run(function()
    while true do
      clock.sleep(1)
    end
  end)
end

return clock
