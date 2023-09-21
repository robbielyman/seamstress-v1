-- hello_pmaps.lua
-- introduces how to MIDI map and manage mapping files (known as PMAPs)

-- a script's mapping file is written every time a mapping is created or edited,
--    and when a PSET is saved (see hello_psets.lua).

-- this file is saved to your seamstress path, under 'data/<scriptname>/<scriptname>.pmap'

-- MAPPING:
-- while running a script, focus the params screen and press SHIFT + M to toggle
--   between the params UI and the mapping UI.
-- press ENTER on any unassigned entry (any with a -) to toggle MIDI learn.
-- once seamstress receives a MIDI CC on any channel / number / device,
--    it will register the assignment and save a .pmap file in the seamstress.state.path
-- in mapping mode, any learned parameter can be cleared with SHIFT + BACKSPACE.

-- MAPPING EDIT:
-- while in mapping mode, press ENTER on any mapped parameter to open the mapping for editing.
-- here, you can manually modify:
--   - CC
--   - channel
--   - device
--   - out: lowest parameter value (scales incoming CC value to this range)
--   - out: highest parameter value (scales incoming CC value to this range)
--   - in: lowest incoming value (any CC lower than this value will not affect the parameter)
--   - in: highest incoming value (any CC higher than this value will not affect the parameter)
--   - accum: enable when using relative / delta-based CC streams
--   - echo: enable to send the parameter's (scaled) value back to the mapped controller (for LED activity)
-- in MAPPING EDIT mode, you can use these keys:
--   - left/right: nav
--   - up/down: delta +/- 1
--   - right ALT + up/down: delta +/- 10
--   - TAB: cycle to next parameter
--   - SHIFT + TAB: cycle to previous parameter

-- SCRIPTING:
-- all of these commands refer to:
--   path.seamstress .. "/data/" .. seamstress.state.name .. "/" .. seamstress.state.name .. ".pmap"
-- to write on-demand: pmap.write()
-- to read on-demand: pmap.read()
-- to delete on-demand: pmap.delete()

function init()
  header = function(text)
    screen.color(182, 66, 38)
    screen.text(text)
  end

  instruction = function(text)
    screen.color(70, 138, 168)
    screen.text(text)
  end

  params:add_separator("hello PMAPs!")
  params:add {
    type = "number",
    id = "mappable_number",
    name = "you can map this!",
    min = 0,
    max = 10,
    default = 8,
  }

  params:add {
    type = "option",
    id = "mappable_option",
    name = "or this!",
    options = { "yes", "yep", "yeh!" },
  }

  params:add {
    type = "binary",
    id = "mappable_binary",
    behavior = "momentary",
    name = "momentary!",
    action = function(x)
      print("hi from momentary", x)
    end,
  }

  params:add {
    type = "trigger",
    id = "mappable_trigger",
    name = "trigger!",
    action = function()
      print("hi from trigger")
    end,
  }

  params:add {
    type = "binary",
    id = "mappable_toggle",
    behavior = "toggle",
    name = "toggle!",
    action = function(x)
      print("hi from toggle", x)
    end,
  }

  params:add {
    type = "control",
    id = "mappable_control",
    name = "control!",
    controlspec = controlspec.FREQ,
  }

  params:add_separator("unmappable params")
  params:add {
    type = "number",
    id = "unmappable_number",
    name = "you cannot map this!",
    min = 0,
    max = 10,
    default = 0,
    allow_pmap = false,
  }
  params:add {
    type = "option",
    id = "unmappable_option",
    name = "can't map this either!",
    options = { "nope", "nah", "nothin'" },
    allow_pmap = false,
  }
  params:add {
    type = "binary",
    id = "unmappable_binary",
    name = "truly, unmappable",
    allow_pmap = false,
  }
  params:add {
    type = "control",
    id = "unmappable_control",
    name = "keep movin'",
    controlspec = controlspec.FREQ,
    allow_pmap = false,
  }

  redraw()
end

function redraw()
  screen.clear()
  screen.move(10, 10)
  header("in params window:")
  screen.move(20, 20)
  instruction("SHIFT + M: toggle MAPPING")
  screen.move(10, 35)
  header("if a parameter is unmapped:")
  screen.move(20, 45)
  instruction("ENTER / RETURN: toggle MIDI learn")
  screen.move(10, 55)
  header("if a parameter is mapped:")
  screen.move(20, 65)
  instruction("ENTER / RETURN: enter mapping management")

  screen.refresh()
end
