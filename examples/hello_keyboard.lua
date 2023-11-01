-- hello_keyboard.lua
-- introduces how to capture and display keyboard input

-- for a fully-developed script example, run 'seamstress -e plasma'

function init()
  data = {
    modifier = "none",
    char = "none",
    is_repeat = "false",
    state = 0,
  }
end

function screen.key(char, modifiers, is_repeat, state)
  if #modifiers == 1 then
    data.modifier = modifiers[1]
  elseif #modifiers == 0 then
    data.modifier = "none"
  end
  if char.name ~= nil then
    data.char = char.name
  else
    char = char == " " and "space" or char
    data.char = char
  end
  data.is_repeat = tostring(is_repeat)
  data.state = state
  redraw()
end

function redraw()
  screen.clear()
  screen.level(15)
  screen.move(10, 10)
  screen.text("last char: " .. data.char)
  screen.move_rel(0, 10)
  screen.text("current mod: " .. data.modifier)
  screen.move_rel(0, 10)
  screen.text("repeat: " .. data.is_repeat)
  screen.move_rel(0, 10)
  screen.text("state: " .. data.state)
  screen.update()
end
