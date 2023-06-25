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

--- draws a line.
-- @tparam integer ax source x-coordinate (1-based)
-- @tparam integer ay source y-coordinate (1-based)
-- @tparam integer bx target x-coordinate (1-based)
-- @tparam integer by target y-coordinate (1-based)
-- @function screen.line
function Screen.line(ax, ay, bx, by)
	_seamstress.screen_line(ax, ay, bx, by)
end

--- draws a rectangle.
-- @tparam integer x upper-left x-coordinate (1-based)
-- @tparam integer y upper-left y-coordinate (1-based)
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @function screen.rect
function Screen.rect(x, y, w, h)
	_seamstress.screen_rect(x, y, w, h)
end

--- draws a filled-in rectangle.
-- @tparam integer x upper-left x-coordinate (1-based)
-- @tparam integer y upper-left y-coordinate (1-based)
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @function screen.rect_fill
function Screen.rect_fill(x, y, w, h)
	_seamstress.screen_rect_fill(x, y, w, h)
end

--- draws text to the screen.
-- @tparam integer x upper-left x-coordinate (1-based)
-- @tparam integer y upper-left y-coordinate (1-based)
-- @tparam string text text to draw
-- @function screen.text
function Screen.text(x, y, text)
	_seamstress.screen_text(x, y, text)
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
-- @function Screen.
-- @treturn integer w width in pixels
-- @treturn integer h height in pixels
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
      paramsMenu.key(keycodes[symbol], keycodes.modifier(modifiers), is_repeat, state, window)
    elseif Screen.key ~= nil then
      Screen.key(keycodes[symbol], keycodes.modifier(modifiers), is_repeat, state, window)
    end
  end,
  mouse = function(x, y, window)
    if Screen.mouse ~= nil then
      Screen.mouse(x, y, window)
    end
  end,
  click = function(x, y, state, button, window)
    if Screen.click ~= nil then
      Screen.click(x, y, state, button, window)
    end
  end,
  resized = function(x, y, window)
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
-- @tparam integer window 1 for the main window, 2 for the params window
-- @function screen.key
function Screen.key(char, modifiers, is_repeat, state, window) end

--- callback executed when the user moves the mouse with the gui window focused.
-- @tparam integer x x-coordinate
-- @tparam integer y y-coordinate
-- @tparam integer window 1 for the main window, 2 for the params window
-- @function screen.mouse
function Screen.mouse(x, y, window) end

--- callback executed when the user clicks the mouse on the gui window.
-- @tparam integer x x-coordinate
-- @tparam integer y y-coordinate
-- @tparam integer state 1 for a press, 0 for release
-- @tparam integer button bitmask for which button was pressed
-- @tparam integer window 1 for the main window, 2 for the params window
-- @function screen.click
function Screen.click(x, y, state, button, window) end

--- callback executed when the user resizes a window
-- @tparam integer x new x size
-- @tparam integer y new y size
-- @tparam integer window 1 for the main window, 2 for the params window
-- @function screen.resized
function Screen.resized(x, y, window) end

return Screen
