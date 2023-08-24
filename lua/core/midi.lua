--- midi
-- @module midi

--[[
  based on norns' midi.lua
  norns midi.lua first committed by @artfwo March 4, 2018
  rewritten for seamstress by @ryleelyman June 12, 2023
]]

--- midi device (input or output)
-- @type midi
local Midi = {}
Midi.__index = Midi

local vport = require("vport")

Midi.inputs = {}
Midi.vinports = {}
Midi.outputs = {}
Midi.voutports = {}

for i = 1, 16 do
  Midi.voutports[i] = {
    name = "none",
    device = nil,
    connected = false,

    send = function(self, ...)
      if self.device then
        self.device:send(...)
      end
    end,
    note_on = vport.wrap("note_on"),
    note_off = vport.wrap("note_off"),
    cc = vport.wrap("cc"),
    pitchbend = vport.wrap("pitchbend"),
    key_pressure = vport.wrap("key_pressure"),
    channel_pressure = vport.wrap("channel_pressure"),
    program_change = vport.wrap("program_change"),
    start = vport.wrap("start"),
    stop = vport.wrap("stop"),
    continue = vport.wrap("continue"),
    clock = vport.wrap("clock"),
    song_position = vport.wrap("song_position"),
    song_select = vport.wrap("song_select"),
  }
  Midi.vinports[i] = {
    name = "none",
    device = nil,
    connected = false,
    event = nil,
  }
end

function Midi.new(name, is_input, id, dev)
  local d = setmetatable({}, Midi)
  d.id = id
  d.name = name
  d.remove = nil
  d.port = nil
  d.dev = dev
  d.is_input = is_input
  local connected = {}
  if is_input then
    d.event = nil
    for i = 1, 16 do
      if Midi.vinports[i].name == name then
        return d
      end
    end
    for i = 1, 16 do
      if Midi.vinports[i].name == "none" then
        Midi.vinports[i].name = name
        break
      end
    end
  else
    for i = 1, 16 do
      if Midi.voutports[i].name == name then
        return d
      end
    end
    for i = 1, 16 do
      if Midi.voutports[i].name == "none" then
        Midi.voutports[i].name = name
        break
      end
    end
  end
  return d
end

--- callback executed when midi device is added
-- @tparam dev midi midi device
-- @tparam bool is_input true if input, false if output
-- @function midi.add
function Midi.add(dev, is_input) end

--- callback executed when midi device is removed
-- @tparam dev midi midi device
-- @function midi.remove
function Midi.remove(dev) end

--- send midi out an output device
-- @tparam midi self midi device
-- @tparam table data to send
-- @function midi:send
function Midi:send(data)
  if self.is_input then
    error("cannot send from input!")
    return
  end
  if data.type then
    local d = Midi.to_data(data)
    _seamstress.midi_write(self.dev, d)
  else
    _seamstress.midi_write(self.dev, data)
  end
end

--- send midi note on event.
-- @tparam integer note : note number
-- @tparam integer vel : velocity
-- @tparam integer ch : midi channel
-- @function midi:note_on
function Midi:note_on(note, vel, ch)
  self:send { type = "note_on", note = note, vel = vel, ch = ch or 1 }
end

--- send midi note off event.
-- @tparam integer note : note number
-- @tparam integer vel : velocity
-- @tparam integer ch : midi channel
-- @function midi:note_off
function Midi:note_off(note, vel, ch)
  self:send { type = "note_off", note = note, vel = vel or 100, ch = ch or 1 }
end

--- send midi continuous controller event.
-- @tparam integer cc : cc number
-- @tparam integer val : value
-- @tparam integer ch : midi channel
-- @function midi:cc
function Midi:cc(cc, val, ch)
  self:send { type = "cc", cc = cc, val = val, ch = ch or 1 }
end

--- send midi pitchbend event.
-- @tparam integer val : value
-- @tparam integer ch : midi channel
-- @function midi:pitchbend
function Midi:pitchbend(val, ch)
  self:send { type = "pitchbend", val = val, ch = ch or 1 }
end

--- send midi key pressure event.
-- @tparam integer note : note number
-- @tparam integer val : value
-- @tparam integer ch : midi channel
-- @function midi:key_pressure
function Midi:key_pressure(note, val, ch)
  self:send { type = "key_pressure", note = note, val = val, ch = ch or 1 }
end

--- send midi channel pressure event.
-- @tparam integer val : value
-- @tparam integer ch : midi channel
-- @function midi:channel_pressure
function Midi:channel_pressure(val, ch)
  self:send { type = "channel_pressure", val = val, ch = ch or 1 }
end

--- send midi program change event.
-- @tparam integer val : value
-- @tparam integer ch : midi channel
-- @function midi:program_change
function Midi:program_change(val, ch)
  self:send { type = "program_change", val = val, ch = ch or 1 }
end

--- send midi start event.
-- @function midi:start
function Midi:start()
  self:send { type = "start" }
end

--- send midi stop event.
-- @function midi:stop
function Midi:stop()
  self:send { type = "stop" }
end

--- send midi continue event.
-- @function midi:continue
function Midi:continue()
  self:send { type = "continue" }
end

--- send midi clock event.
-- @function midi:clock
function Midi:clock()
  self:send { type = "clock" }
end

--- send midi song position event.
-- @tparam integer lsb :
-- @tparam integer msb :
-- @function midi:song_position
function Midi:song_position(lsb, msb)
  self:send { type = "song_position", lsb = lsb, msb = msb }
end

--- send midi song select event.
-- @tparam integer val : value
-- @function midi:song_select
function Midi:song_select(val)
  self:send { type = "song_select", val = val }
end

--- connects to an input port
-- @tparam[opt] integer n (1-16)
-- @function midi.connect_input
function Midi.connect_input(n)
  local n = n or 1
  return Midi.vinports[n]
end

--- connects to an output port
-- @tparam[opt] integer n (1-16)
-- @function midi.connect_output
function Midi.connect_output(n)
  local n = n or 1
  return Midi.voutports[n]
end

-- function table for msg-to-data conversion
local to_data = {
  -- FIXME: should all subfields have default values (ie note/vel?)
  note_on = function(msg)
    return { 0x90 + (msg.ch or 1) - 1, msg.note, msg.vel or 100 }
  end,
  note_off = function(msg)
    return { 0x80 + (msg.ch or 1) - 1, msg.note, msg.vel or 100 }
  end,
  cc = function(msg)
    return { 0xb0 + (msg.ch or 1) - 1, msg.cc, msg.val }
  end,
  pitchbend = function(msg)
    return { 0xe0 + (msg.ch or 1) - 1, msg.val & 0x7f, (msg.val >> 7) & 0x7f }
  end,
  key_pressure = function(msg)
    return { 0xa0 + (msg.ch or 1) - 1, msg.note, msg.val }
  end,
  channel_pressure = function(msg)
    return { 0xd0 + (msg.ch or 1) - 1, msg.val }
  end,
  program_change = function(msg)
    return { 0xc0 + (msg.ch or 1) - 1, msg.val }
  end,
  start = function(msg)
    return { 0xfa }
  end,
  stop = function(msg)
    return { 0xfc }
  end,
  continue = function(msg)
    return { 0xfb }
  end,
  clock = function(msg)
    return { 0xf8 }
  end,
  song_position = function(msg)
    return { 0xf2, msg.lsb, msg.msb }
  end,
  song_select = function(msg)
    return { 0xf3, msg.val }
  end,
}

--- convert msg to data (midi bytes).
-- @tparam table msg :
-- @treturn table data : table of midi status and data bytes
function Midi.to_data(msg)
  if msg.type then
    return to_data[msg.type](msg)
  else
    error("failed to serialize midi message")
  end
end

--- convert data (midi bytes) to msg.
-- @tparam table data :
-- @treturn table msg : midi message table, contents vary depending on message
function Midi.to_msg(data)
  local msg = {}
  -- note on
  if data[1] & 0xf0 == 0x90 then
    msg = {
      note = data[2],
      vel = data[3],
      ch = data[1] - 0x90 + 1,
    }
    if data[3] > 0 then
      msg.type = "note_on"
    elseif data[3] == 0 then -- if velocity is zero then send note off
      msg.type = "note_off"
    end
  -- note off
  elseif data[1] & 0xf0 == 0x80 then
    msg = {
      type = "note_off",
      note = data[2],
      vel = data[3],
      ch = data[1] - 0x80 + 1,
    }
  -- cc
  elseif data[1] & 0xf0 == 0xb0 then
    msg = {
      type = "cc",
      cc = data[2],
      val = data[3],
      ch = data[1] - 0xb0 + 1,
    }
  -- pitchbend
  elseif data[1] & 0xf0 == 0xe0 then
    msg = {
      type = "pitchbend",
      val = data[2] + (data[3] << 7),
      ch = data[1] - 0xe0 + 1,
    }
  -- key pressure
  elseif data[1] & 0xf0 == 0xa0 then
    msg = {
      type = "key_pressure",
      note = data[2],
      val = data[3],
      ch = data[1] - 0xa0 + 1,
    }
  -- channel pressure
  elseif data[1] & 0xf0 == 0xd0 then
    msg = {
      type = "channel_pressure",
      val = data[2],
      ch = data[1] - 0xd0 + 1,
    }
  -- program change
  elseif data[1] & 0xf0 == 0xc0 then
    msg = {
      type = "program_change",
      val = data[2],
      ch = data[1] - 0xc0 + 1,
    }
  -- start
  elseif data[1] == 0xfa then
    msg.type = "start"
  -- stop
  elseif data[1] == 0xfc then
    msg.type = "stop"
  -- continue
  elseif data[1] == 0xfb then
    msg.type = "continue"
  -- clock
  elseif data[1] == 0xf8 then
    msg.type = "clock"
  -- song position pointer
  elseif data[1] == 0xf2 then
    msg = {
      type = "song_position",
      lsb = data[2],
      msb = data[3],
    }
  -- song select
  elseif data[1] == 0xf3 then
    msg = {
      type = "song_select",
      val = data[2],
    }
  -- active sensing (should probably ignore)
  elseif data[1] == 0xfe then
  -- do nothing
  -- system exclusive
  elseif data[1] == 0xf0 then
    msg = {
      type = "sysex",
      raw = data,
    }
  -- everything else
  else
    msg = {
      type = "other",
      raw = data,
    }
  end
  return msg
end

-- update devices.
function Midi.update_devices()
  -- reset vports for existing devices
  for _, device in pairs(Midi.inputs) do
    device.port = nil
  end
  for _, device in pairs(Midi.outputs) do
    device.port = nil
  end

  -- connect available devices to vports
  for i = 1, 16 do
    Midi.vinports[i].device = nil
    Midi.voutports[i].device = nil

    for _, device in pairs(Midi.inputs) do
      if device.name == Midi.vinports[i].name then
        Midi.vinports[i].device = device
        device.port = i
      end
    end
    for _, device in pairs(Midi.outputs) do
      if device.name == Midi.voutports[i].name then
        Midi.voutports[i].device = device
        device.port = i
      end
    end
  end
  Midi.update_connected_state()
end

function Midi.update_connected_state()
  for i = 1, 16 do
    if Midi.vinports[i].device ~= nil then
      Midi.vinports[i].connected = true
    else
      Midi.vinports[i].connected = false
    end
    if Midi.voutports[i].device ~= nil then
      Midi.voutports[i].connected = true
    else
      Midi.voutports[i].connected = false
    end
  end
end

_seamstress.midi = {
  add = function(name, is_input, id, dev)
    local d = Midi.new(name, is_input, id, dev)
    if is_input == true then
      Midi.inputs[id] = d
    else
      Midi.outputs[id] = d
    end
    Midi.update_devices()
    if Midi.add ~= nil then
      Midi.add(d, is_input)
    end
  end,
  remove = function(is_input, id)
    if is_input == true then
      if Midi.inputs[id] then
        Midi.remove(Midi.inputs[id])
        if Midi.inputs[id].remove then
          Midi.inputs[id]:remove()
        end
      end
    else
      if Midi.outputs[id] then
        Midi.remove(Midi.outputs[id])
        if Midi.outputs[id].remove then
          Midi.outputs[id]:remove()
        end
      end
    end
  end,
  event = function(id, timestamp, bytes)
    local d = Midi.inputs[id]
    if d ~= nil then
      if d.event ~= nil then
        d.event(timestamp, bytes)
      end
      if d.port then
        if Midi.vinports[d.port].event then
          Midi.vinports[d.port].event(timestamp, bytes)
        end
        paramsMenu.menu_midi_event(Midi.to_msg(bytes), d.port)
      end
    else
      error("no entry for midi " .. id)
    end
  end,
}

return Midi
