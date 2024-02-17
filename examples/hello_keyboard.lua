-- hello_keyboard.lua
-- introduces how to capture and display keyboard input

-- for a fully-developed script example, run 'seamstress -e plasma'

function init()
  screen.set_size(128, 56)
  data = {
    modifier = "none",
    char = "none",
    is_repeat = "false",
    state = 0,
  }
  display_lines = {
    { "last char: ", "char" },
    { "current mod: ", "modifier" },
    { "repeat: ", "is_repeat" },
    { "state: ", "state" },
  }
  L1 = 7
  L2 = 15
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
  for i = 1, 4 do
    screen.move(10, 10 * i)
    screen.level(L1)
    local ln = display_lines[i][1] -- get text string
    screen.text(ln) -- display text string

    local width, height = screen.get_text_size(ln)
    screen.move_rel(width, 0)
    screen.level(L2)
    ln = data[display_lines[i][2]] -- get data
    screen.text(ln) -- display data
  end
  screen.update()
end
