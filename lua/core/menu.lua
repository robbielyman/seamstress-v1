local menu = {}

local width, height = 128, 64

function menu.mouse(x, y) end

function menu.click(x, y, button, state) end

function menu.key(char, modifiers, is_repeat, state) end

function menu.resized(x, y)
  width = x
  height = y
  menu.redraw()
end

function menu.redraw()
	screen.set(2)
  screen.clear()
  screen.refresh()
  screen.reset(1)
end

return menu
