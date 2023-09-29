-- hello_midi.lua
-- this script is an 8-step MIDI sequencer with CC value, note, and velocity per step

-- key components ( preceeded by -- [//\\] )
--   my_var = midi.connect(x) : connects the device at MIDI port x to a scripting variable
--   my_var:cc(num,val,ch) : send MIDI CC
--   my_var:note_on(note,vel,ch) : send MIDI note on
--   my_var:note_off(note,vel,ch) : send MIDI note off
--   my_var.event : assign incoming MIDI bytes to a function (use 'midi.to_msg(bytes)' for easy conversion)

local MU = require("musicutil") -- we'll use musicutil for easy note formatting + quantization

function init()
  midi_devices = {} -- build a table of connected MIDI devices for MIDI input + output
  midi_device_names = {} -- index their names to display them in params

  for i = 1, #midi.vports do -- for each MIDI port:
    -- [//\\]
    midi_devices[i] = midi.connect(i) -- connect to the device
    -- [//\\]
    midi_devices[i].event = function(bytes) -- establish what to do with incoming MIDI messages
      midi_event(midi.to_msg(bytes), i)
    end
    midi_device_names[i] = i .. ": " .. midi.vports[i].name -- log its name
  end

  -- build scales for quantized note selection:
  scale_names = {}
  for i = 1, #MU.SCALES do
    table.insert(scale_names, string.lower(MU.SCALES[i].name))
  end

  -- sequence data:
  stepper = {
    cc = { 0, 0, 0, 0, 0, 0, 0, 0 },
    note = { 0, 0, 0, 0, 0, 0, 0, 0 },
    vel = { 127, 127, 127, 127, 127, 127, 127, 127 },
    current_step = 0,
    all_notes = {},
    active_notes = {},
    playing = false,
  }

  add_parameters()

  -- screen redrawing:
  screen_dirty = true
  redraw_metro = metro.init()
  redraw_metro.time = 1 / 60
  redraw_metro.event = redraw
  redraw_metro:start()

  -- UI button:
  btn = {
    x = 10,
    y = 60,
    w = 30,
    h = 16,
    state = false,
  }
end

function add_parameters() -- helper function to add all of our parameters
  params:add_separator("MIDI input")
  params:add_option("midi_input_device", "port", midi_device_names, 1)
  params:add_option("midi_input_transport", "ext. MIDI start/stop?", { "no", "yes" }, 1)
  params:add_separator("MIDI output")
  params:add_option("midi_output_device", "port", midi_device_names, 1)
  params:add_number("midi_ch", "channel", 1, 16, 1)
  params:add_number("cc_num", "CC number", 0, 127, 0)
  params:add_number("cc_mapval", "CC value (for mapping)", 0, 127, 0)
  params:set_action("cc_mapval", function(value)
    local port = params:get("midi_output_device")
    local cc_num = params:get("cc_num")
    local midi_ch = params:get("midi_ch")
    -- [//\\]
    midi_devices[port]:cc(cc_num, value, midi_ch)
  end)

  params:add_group("steps", (#stepper.note * 4) + 6)

  params:add_separator("meta")

  params:add_control("root_note", "root note", controlspec.new(0, 127, "lin", 1, 60, nil, 1 / 127), function(param)
    return MU.note_num_to_name(param:get(), true)
  end)
  params:set_action("root_note", function()
    build_scale()
  end)
  params:add_option("scale", "scale", scale_names, 5)
  params:set_action("scale", function()
    build_scale()
  end)
  params:add_trigger("randomize_ccs", "randomize cc's")
  params:set_action("randomize_ccs", function()
    for i = 1, #stepper.note do
      params:set("step_" .. i .. "_cc", math.random(0, 127))
    end
  end)
  params:add_trigger("randomize_notes", "randomize notes")
  params:set_action("randomize_notes", function()
    for i = 1, #stepper.note do
      params:set("step_" .. i .. "_note", math.random(16))
    end
  end)
  params:add_trigger("randomize_vels", "randomize velocities")
  params:set_action("randomize_vels", function()
    for i = 1, #stepper.note do
      params:set("step_" .. i .. "_vel", math.random(0, 127))
    end
  end)

  for i = 1, #stepper.note do
    params:add_separator("step " .. i)
    params:add {
      type = "number",
      id = "step_" .. i .. "_cc",
      name = "cc value",
      min = 0,
      max = 127,
      default = math.random(0, 127),
      action = function(value)
        stepper.cc[i] = value
        screen_dirty = true
      end,
    }
    params:add {
      type = "control",
      id = "step_" .. i .. "_note",
      name = "note",
      controlspec = controlspec.new(
        1, -- min
        16, -- max
        "lin", -- warp
        1, -- step (output will be rounded to a multiple of step)
        math.random(16), -- default
        nil, -- units (an indicator for the unit of measure the data represents)
        1 / 16 -- quantum (input quantization value. adjustments are made by this fraction of the range)
      ),
      formatter = function(param)
        return (stepper.all_notes[param:get()] .. " / " .. MU.note_num_to_name(stepper.all_notes[param:get()], true))
      end,
      action = function(value)
        stepper.note[i] = value
        screen_dirty = true
      end,
    }
    params:add {
      type = "number",
      id = "step_" .. i .. "_vel",
      name = "velocity",
      min = 0,
      max = 127,
      default = 127,
      action = function(value)
        stepper.vel[i] = value
        screen_dirty = true
      end,
    }
  end

  params:bang() -- perform all parameters' associated actions
end

-- create a pool of 16 notes in our current scale:
function build_scale()
  stepper.all_notes = MU.generate_scale_of_length(params:get("root_note"), params:get("scale"), 16)
  local num_to_add = 16 - #stepper.all_notes
  for i = 1, num_to_add do
    table.insert(stepper.all_notes, stepper.all_notes[16 - num_to_add])
  end
  screen_dirty = true
end

-- turn off each note on a regular tick:
function all_notes_off()
  local port = params:get("midi_output_device")
  local midi_ch = params:get("midi_ch")
  for _, a in pairs(stepper.active_notes) do
    -- [//\\]
    midi_devices[port]:note_off(a, nil, params:get("midi_ch"))
  end
  stepper.active_notes = {}
end

-- [//\\]
-- called with each incoming MIDI message:
function midi_event(data, dev)
  if dev == params:get("midi_input_device") and params:string("midi_input_transport") == "yes" then
    if data.type == "start" then
      go()
    elseif data.type == "stop" then
      stop()
    end
  end
end

-- transport start:
function go()
  stepper.playing = true
  btn.state = true
  sequencer_clock = clock.run(function()
    while true do
      clock.sync(1 / 4)
      seq()
    end
  end)
end

-- transport stop:
function stop()
  stepper.playing = false
  btn.state = false
  clock.cancel(sequencer_clock)
  stepper.current_step = 0
  screen_dirty = true
end

-- this occurs on every step:
function seq()
  local port = params:get("midi_output_device")
  local cc_num = params:get("cc_num")
  local midi_ch = params:get("midi_ch")

  stepper.current_step = util.wrap(stepper.current_step + 1, 1, 8)

  local cc_val = stepper.cc[stepper.current_step]
  local midi_note = stepper.all_notes[stepper.note[stepper.current_step]]
  local midi_vel = stepper.vel[stepper.current_step]

  -- [//\\]
  midi_devices[port]:cc(cc_num, cc_val, midi_ch)
  midi_devices[port]:note_on(midi_note, midi_vel, midi_ch)

  table.insert(stepper.active_notes, midi_note)

  clock.run(function()
    clock.sleep((60 / params:get("clock_tempo") / 4) * 2 * 0.25)
    all_notes_off()
  end)
  screen_dirty = true
end

-- when a mouse click occurs:
function screen.click(x, y, state, button)
  if button == 1 then -- if left button is pressed or released:
    -- check to see if button press occurs in the 'start' / 'stop' UI button's coordinates:
    if x >= btn.x and x <= btn.x + 30 and y >= btn.y and y <= btn.y + 16 and state == 1 then
      if not stepper.playing then
        go()
      else
        stop()
      end
    end
    screen_dirty = true
  end
end

-- redraw the script UI:
function redraw()
  if screen_dirty then
    screen.clear()

    screen.move(btn.x, btn.y)
    if btn.state then
      screen.color(141, 69, 249)
    else
      screen.color(177, 249, 69)
    end
    screen.rect_fill(btn.w, btn.h)
    screen.move(btn.x + 15, btn.y + 4)
    local on_off = btn.state and 255 or 0
    screen.color(on_off, on_off, on_off)
    screen.text_center(btn.state and "stop" or "start")

    screen.move(10, 10)
    screen.color(255, 255, 255)
    screen.text("cc: ")

    screen.move(30, 10)
    for i = 1, #stepper.cc do
      screen.move_rel(25, 0)
      screen.color(255, 255, stepper.current_step == i and 30 or 255)
      screen.text_right(stepper.cc[i])
    end

    screen.move(10, 20)
    screen.color(255, 255, 255)
    screen.text("note: ")

    screen.move(30, 20)
    for i = 1, #stepper.note do
      screen.move_rel(25, 0)
      screen.color(255, 255, stepper.current_step == i and 30 or 255)
      screen.text_right(MU.note_num_to_name(stepper.all_notes[stepper.note[i]], true))
    end

    screen.move(10, 30)
    screen.color(255, 255, 255)
    screen.text("vel: ")

    screen.move(30, 30)
    for i = 1, #stepper.vel do
      screen.move_rel(25, 0)
      screen.color(255, 255, stepper.current_step == i and 30 or 255)
      screen.text_right(stepper.vel[i])
    end

    screen.refresh()
    screen_dirty = false
  end
end
