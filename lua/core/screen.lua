--- screen
-- @module screen
local Screen = {}
Screen.__index = Screen

local keycodes = require("keycodes")

--- clears the screen.
-- @function screen.clear
function Screen.clear()
	_seamstress.screen_clear()
end

local current = 1

--- sets the screen which will be affected by following screen calls.
-- call `screen.reset` to return to the previous state.
-- @tparam integer value 1 (gui) or 2 (params)
-- @function screen.set
function Screen.set(value)
  local old = current
  local old_reset = Screen.reset
  _seamstress.screen_set(value)
  current = value
  Screen.reset = function()
    _seamstress.screen_set(old)
    Screen.reset = old_reset
    current = old
  end
end

--- resets which screen will be affected by future screen calls.
-- @function screen.reset
function Screen.reset() end

--- redraws the screen; reveals changes.
-- @function screen.refresh
function Screen.refresh()
	_seamstress.screen_refresh()
end

--- move the current position.
-- @tparam integer x target x-coordinate (1-based)
-- @tparam integer y target y-coordinate (1-based)
-- @function screen.move
function Screen.move(x, y)
	_seamstress.screen_move(x, y)
end

--- move the current position with relative coordinates.
-- @tparam integer x relative target x-coordinate 
-- @tparam integer y relative target y-coordinate
-- @function screen.move_rel
function Screen.move_rel(x, y)
	_seamstress.screen_move_rel(x, y)
end

--- sets screen color.
-- @tparam integer r red value (0-255)
-- @tparam integer g green value (0-255)
-- @tparam integer b blue value (0-255)
-- @tparam integer a alpha value (0-255) (default 255)
-- @function screen.color
function Screen.color(r, g, b, a)
	_seamstress.screen_color(r, g, b, a or 255)
end

--- draws a single pixel.
-- @tparam integer x x-coordinate (1-based)
-- @tparam integer y y-coordinate (1-based)
-- @function screen.pixel
function Screen.pixel(x, y)
	_seamstress.screen_pixel(x, y)
end

--- draws a single pixel at the current coordinate.
-- @function screen.pixel_rel
function Screen.pixel_rel()
	_seamstress.screen_pixel()
end

--- draws a line.
-- @tparam integer bx target x-coordinate (1-based)
-- @tparam integer by target y-coordinate (1-based)
-- @function screen.line
function Screen.line(bx, by)
	_seamstress.screen_line(bx, by)
end

--- draws a line relative to the current coordinates.
-- @tparam integer bx target relative x-coordinate 
-- @tparam integer by target relative y-coordinate
-- @function screen.line_rel
function Screen.line_rel(bx, by)
	_seamstress.screen_line_rel(bx, by)
end

--- draws a rectangle.
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @function screen.rect
function Screen.rect(w, h)
	_seamstress.screen_rect(w, h)
end

--- draws a filled-in rectangle.
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @function screen.rect_fill
function Screen.rect_fill(w, h)
	_seamstress.screen_rect_fill(w, h)
end

--- draws a circle arc centered at the current position.
-- angles are measured in radians and proceed clockwise
-- with 0 pointing to the right. We should have
-- `0 <= theta_1 <= theta_2 <= 2 * pi`
-- @tparam integer radius in pixels
-- @tparam number theta_1 initial angle in radians.
-- @tparam number theta_2 terminal angle in radians.
-- @function screen.arc
function Screen.arc(radius, theta_1, theta_2)
	_seamstress.screen_arc(radius, theta_1, theta_2)
end

--- draws a circle centered at the current position.
-- @tparam integer radius in pixels
-- @function screen.circle
function Screen.circle(radius)
	_seamstress.screen_circle(radius)
end

--- draws a circle centered at the current position.
-- @tparam integer radius in pixels
-- @function screen.circle_fill
function Screen.circle_fill(radius)
	_seamstress.screen_circle_fill(radius)
end

--- draws text to the screen.
-- @tparam string text text to draw
-- @function screen.text
function Screen.text(text)
	_seamstress.screen_text(text)
end

--- draws text to the screen.
-- @tparam string text text to draw
-- @function screen.text_center
function Screen.text_center(text)
	_seamstress.screen_text_center(text)
end

--- draws text to the screen.
-- @tparam string text text to draw
-- @function screen.text_right
function Screen.text_right(text)
	_seamstress.screen_text_right(text)
end

--- gets size of text.
-- @tparam string text text to size
-- @treturn integer w width in pixels
-- @treturn integer h height in pixels
-- @function screen.get_text_size
function Screen.get_text_size(text)
  return _seamstress.screen_get_text_size(text)
end

--- returns the size of the current window.
-- @treturn integer w width in pixels
-- @treturn integer h height in pixels
-- @function screen.get_size
function Screen.get_size()
  return _seamstress.screen_get_size()
end

_seamstress.screen = {
  key = function (symbol, modifiers, is_repeat, state, window)
    local char = keycodes[symbol]
    local mods = keycodes.modifier(modifiers)
    if #mods == 1 and mods[1] == "ctrl" and char == "p" and state == 1 and window == 1 then
      _seamstress.screen_show()
    elseif #mods == 1 and mods[1] == "ctrl" and char == "c" and state == 1 then
      _seamstress.quit_lvm()
    elseif window == 2 then
      paramsMenu.key(keycodes[symbol], keycodes.modifier(modifiers), is_repeat, state)
    elseif Screen.key ~= nil then
      Screen.key(keycodes[symbol], keycodes.modifier(modifiers), is_repeat, state)
    end
  end,
  mouse = function(x, y, window)
    if window == 2 then
      paramsMenu.mouse(x, y)
    elseif Screen.mouse ~= nil then
      Screen.mouse(x, y)
    end
  end,
  click = function(x, y, state, button, window)
    if window == 2 then
      paramsMenu.click(x, y, state, button)
    elseif Screen.click ~= nil then
      Screen.click(x, y, state, button)
    end
  end,
  resized = function(x, y, window)
    paramsMenu.redraw()
    if Screen.resized ~= nil then
      Screen.resized(x, y, window)
    end
  end,
}

--- callback executed when the user types a key into the gui window.
-- @tparam string|table char either the character or a table of the form {name = "name"}
-- @tparam table modifiers a table with the names of modifier keys pressed down
-- @tparam bool is_repeat true if the key is a repeat event
-- @tparam integer state 1 for a press, 0 for release
-- @function screen.key
function Screen.key(char, modifiers, is_repeat, state) end

--- callback executed when the user moves the mouse with the gui window focused.
-- @tparam integer x x-coordinate
-- @tparam integer y y-coordinate
-- @function screen.mouse
function Screen.mouse(x, y) end

--- callback executed when the user clicks the mouse on the gui window.
-- @tparam integer x x-coordinate
-- @tparam integer y y-coordinate
-- @tparam integer state 1 for a press, 0 for release
-- @tparam integer button bitmask for which button was pressed
-- @function screen.click
function Screen.click(x, y, state, button) end

--- callback executed when the user resizes a window
-- @tparam integer x new x size
-- @tparam integer y new y size
-- @tparam integer window 1 for the main window, 2 for the params window
-- @function screen.resized
function Screen.resized(x, y, window) end

return Screen
