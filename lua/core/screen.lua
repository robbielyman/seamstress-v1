--- screen
-- @module screen

--[[
  inspired by norns' screen.lua (and isms by @tehn)
  norns screen.lua first committed by @tehn Jan 30, 2018
  writen for seamstress by @ryleelyman May 31, 2023
]]
local screen = {
  width = 256,
  height = 128,
  params_width = 256,
  params_height = 128,
}
screen.__index = screen

local keycodes = require("keycodes")

--- clears the screen.
-- @function screen.clear
function screen.clear()
  _seamstress.screen_clear()
end

--- redraws the screen; reveals changes.
-- @function screen.refresh
function screen.refresh()
  _seamstress.screen_refresh()
end

--- move the current position.
-- @tparam integer x target x-coordinate (1-based)
-- @tparam integer y target y-coordinate (1-based)
-- @function screen.move
function screen.move(x, y)
  _seamstress.screen_move(x, y)
end

--- move the current position with relative coordinates.
-- @tparam integer x relative target x-coordinate
-- @tparam integer y relative target y-coordinate
-- @function screen.move_rel
function screen.move_rel(x, y)
  _seamstress.screen_move_rel(x, y)
end

--- sets screen color.
-- @tparam integer r red value (0-255)
-- @tparam integer g green value (0-255)
-- @tparam integer b blue value (0-255)
-- @tparam integer a alpha value (0-255) (default 255)
-- @function screen.color
function screen.color(r, g, b, a)
  _seamstress.screen_color(r, g, b, a or 255)
end

--- draws a single pixel.
-- @tparam integer x x-coordinate (1-based)
-- @tparam integer y y-coordinate (1-based)
-- @function screen.pixel
function screen.pixel(x, y)
  _seamstress.screen_pixel(x, y)
end

--- draws a single pixel at the current coordinate.
-- @function screen.pixel_rel
function screen.pixel_rel()
  _seamstress.screen_pixel()
end

--- draws a line.
-- @tparam integer bx target x-coordinate (1-based)
-- @tparam integer by target y-coordinate (1-based)
-- @function screen.line
function screen.line(bx, by)
  _seamstress.screen_line(bx, by)
end

--- draws a line relative to the current coordinates.
-- @tparam integer bx target relative x-coordinate
-- @tparam integer by target relative y-coordinate
-- @function screen.line_rel
function screen.line_rel(bx, by)
  _seamstress.screen_line_rel(bx, by)
end

--- draws a (cubic) bezier curve.
-- @tparam number x1 1rst handle x
-- @tparam number y1 1rst handle y
-- @tparam number x2 2nd handle x
-- @tparam number y2 2nd handle y
-- @tparam number x3 3rd destination x
-- @tparam number y3 3rd destination y
-- @function screen.curve
function screen.curve(x1, y1, x2, y2, x3, y3)
  _seamstress.screen_curve(x1, y1, x2, y2, x3, y3)
end

--- draws a rectangle.
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @function screen.rect
function screen.rect(w, h)
  _seamstress.screen_rect(w, h)
end

--- draws a filled-in rectangle.
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @function screen.rect_fill
function screen.rect_fill(w, h)
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
function screen.arc(radius, theta_1, theta_2)
  _seamstress.screen_arc(radius, theta_1, theta_2)
end

--- draws a circle centered at the current position.
-- @tparam integer radius in pixels
-- @function screen.circle
function screen.circle(radius)
  _seamstress.screen_circle(radius)
end

--- draws a circle centered at the current position.
-- @tparam integer radius in pixels
-- @function screen.circle_fill
function screen.circle_fill(radius)
  _seamstress.screen_circle_fill(radius)
end

--- draws a filled in triangle with the given coordinates.
-- @tparam number ax x-coordinate in pixels
-- @tparam number ay y-coordinate in pixels
-- @tparam number bx x-coordinate in pixels
-- @tparam number by y-coordinate in pixels
-- @tparam number cx x-coordinate in pixels
-- @tparam number cy y-coordinate in pixels
-- @function screen.triangle
function screen.triangle(ax, ay, bx, by, cx, cy)
  _seamstress.screen_triangle(ax, ay, bx, by, cx, cy)
end

--- draws a filled in quad with the given coordinates.
-- @tparam number ax x-coordinate in pixels
-- @tparam number ay y-coordinate in pixels
-- @tparam number bx x-coordinate in pixels
-- @tparam number by y-coordinate in pixels
-- @tparam number cx x-coordinate in pixels
-- @tparam number cy y-coordinate in pixels
-- @tparam number dx x-coordinate in pixels
-- @tparam nubmer dy y-coordinate in pixels
-- @function screen.quad
function screen.quad(ax, ay, bx, by, cx, cy, dx, dy)
  _seamstress.screen_quad(ax, ay, bx, by, cx, cy, dx, dy)
end

--- draws arbitrary vertex-defined geometry.
-- @param vertices a list of lists of the form {{x, y}, {r, g, b, a?}, {t_x, t_y}?},
-- where x, y, t_x, and t_y represent pixel coordinates
-- and r, g, b, a represents a color.
-- @param indices (optional) a list of indices into the vertices list
-- @param texture (optional) a texture created by `screen.new_texture`
-- @function screen.geometry
function screen.geometry(vertices, indices, texture)
  if indices then
    if texture then
      _seamstress.screen_geometry(vertices, indices, texture.texture)
    else
      _seamstress.screen_geometry(vertices, indices)
    end
  else
    _seamstress.screen_geometry(vertices)
  end
end

--- draws text to the screen.
-- @tparam string text text to draw
-- @function screen.text
function screen.text(text)
  _seamstress.screen_text(text)
end

--- draws text to the screen.
-- @tparam string text text to draw
-- @function screen.text_center
function screen.text_center(text)
  _seamstress.screen_text_center(text)
end

--- draws text to the screen.
-- @tparam string text text to draw
-- @function screen.text_right
function screen.text_right(text)
  _seamstress.screen_text_right(text)
end

--- gets size of text.
-- @tparam string text text to size
-- @treturn integer w width in pixels
-- @treturn integer h height in pixels
-- @function screen.get_text_size
function screen.get_text_size(text)
  return _seamstress.screen_get_text_size(text)
end

--- returns the size of the current window.
-- @treturn integer w width in pixels
-- @treturn integer h height in pixels
-- @function screen.get_size
function screen.get_size()
  return _seamstress.screen_get_size()
end

--- sets the size of the current window
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @tparam integer z zoom factor
function screen.set_size(w, h, z)
  _seamstress.screen_set_size(w, h, z or 4)
end

--- sets the fullscreen state of the current window
-- @tparam bool is_fullscreen
function screen.set_fullscreen(is_fullscreen)
  _seamstress.screen_set_fullscreen(is_fullscreen)
end

_seamstress.screen = {
  key = function(symbol, modifiers, is_repeat, state, window)
    local char = keycodes[symbol]
    local mods = keycodes.modifier(modifiers)
    if #mods == 1 and mods[1] == "ctrl" and char == "p" and state == 1 and window == 1 then
      _seamstress.screen_show()
    elseif #mods == 1 and mods[1] == "ctrl" and char == "c" and state == 1 then
      _seamstress.quit_lvm()
    elseif window == 2 then
      paramsMenu.key(keycodes[symbol], keycodes.modifier(modifiers), is_repeat, state)
    elseif screen.key ~= nil then
      screen.key(keycodes[symbol], keycodes.modifier(modifiers), is_repeat, state)
    end
  end,
  mouse = function(x, y, window)
    if window == 2 then
      paramsMenu.mouse(x, y)
    elseif screen.mouse ~= nil then
      screen.mouse(x, y)
    end
  end,
  click = function(x, y, state, button, window)
    if window == 2 then
      paramsMenu.click(x, y, state, button)
    elseif screen.click ~= nil then
      screen.click(x, y, state, button)
    end
  end,
  wheel = function (x, y, window)
    if window == 2 then
      paramsMenu.wheel(x, y)
    elseif screen.wheel ~= nil then
      screen.wheel(x, y)
    end
  end,
  resized = function(x, y, window)
    if window == 1 then
      screen.width = x
      screen.height = y
      clock.run(function()
        clock.sleep(0.125)
        if screen.resized ~= nil then
          screen.resized()
        end
      end)
    else
      screen.params_width = x
      screen.params_height = y
      clock.run(function()
        clock.sleep(0.125)
        paramsMenu.redraw()
      end)
    end
  end,
}

--- callback executed when the user types a key into the gui window.
-- @tparam string|table char either the character or a table of the form {name = "name"}
-- @tparam table modifiers a table with the names of modifier keys pressed down
-- @tparam bool is_repeat true if the key is a repeat event
-- @tparam integer state 1 for a press, 0 for release
-- @function screen.key
function screen.key(char, modifiers, is_repeat, state) end

--- callback executed when the user moves the mouse with the gui window focused.
-- @tparam number x x-coordinate
-- @tparam number y y-coordinate
-- @function screen.mouse
function screen.mouse(x, y) end

--- callback executed when the user clicks the mouse on the gui window.
-- @tparam number x x-coordinate
-- @tparam number y y-coordinate
-- @tparam integer state 1 for a press, 0 for release
-- @tparam integer button bitmask for which button was pressed
-- @function screen.click
function screen.click(x, y, state, button) end

--- callback executed when the user scrolls with the mouse wheel on the gui window.
-- @tparam number x amount moved in the x-direction (right positive)
-- @tparam number y amount moved in the y-direction (away from you positive)
-- @function screen.wheel
function screen.wheel(x, y) end

--- callback executed when the user resizes a window
-- @function screen.resized
function screen.resized() end

--- @section screen.Texture
Texture = {}
screen.Texture = Texture
Texture.__index = Texture

--- renders the texture object with top-left corner at (x,y)
-- @tparam integer x x-coordinate
-- @tparam integer y y-coordinate
-- @tparam number zoom scale at which to draw, defaults to 1
-- @function Texture:render
function Texture:render(x, y, zoom)
  _seamstress.screen_render_texture(self.texture, x, y, zoom or 1)
end

--- renders the texture object with top-left corner at (x,y)
-- @tparam integer x x-coordinate
-- @tparam integer y y-coordinate
-- @tparam number theta angle in radians to rotate the texture about its center
-- @tparam bool flip_h flip horizontally if true
-- @tparam bool flip_v flip vertically if true
-- @tparam number zoom scale at which to draw, defaults to 1
-- @function screen.Texture.render_extended
function Texture:render_extended(x, y, theta, flip_h, flip_v, zoom)
  _seamstress.screen_render_texture_extended(self.texture, x, y, zoom or 1, theta, flip_h == true, flip_v == true)
end

--- creates and returns a new texture object
-- the texture data is a rectangle of dimensions (width,height)
-- with top-left corner the current screen position
-- call before calling `screen.refresh`.
-- this operation is slower than most screen calls; try not to call it in a clock, for instance.
-- @tparam integer width width in pixels
-- @tparam integer height height in pixels
-- @function screen.new_texture
function screen.new_texture(width, height)
  local t = {
    texture = _seamstress.screen_new_texture(width, height),
    width = width,
    height = height,
  }
  setmetatable(t, Texture)
  return t
end

--- creates and returns a new texture object from an image file
-- @tparam string filename absolute path to file
-- @function screen.new_texture_from_file
function screen.new_texture_from_file(filename)
  local texture = _seamstress.screen_new_texture_from_file(filename)
  local w, h = _seamstress.screen_texture_dimensions(texture)
  local t = {
    texture = texture,
    width = w,
    height = h,
  }
  setmetatable(t, Texture)
  return t
end

return screen
