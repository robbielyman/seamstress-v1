--- startup file
-- @script seamstress
grid = require 'core/grid'
arc = require 'core/arc'
osc = require 'core/osc'
util = require 'lib/util'
screen = require 'core/screen'
menu = require 'core/menu'
metro = require 'core/metro'
midi = require 'core/midi'
clock = require 'core/clock'
local keycodes = require 'core/keycodes'

--- global init function to be overwritten in user scripts.
init = function () end

_seamstress.monome = {
  add = function (id, serial, name, dev)
    if string.find(name, "monome arc") then
      _seamstress.arc.add(id, serial, name, dev)
    else
      _seamstress.grid.add(id, serial, name, dev)
    end
  end,
  remove = function (id)
    if arc.devices[id] then
      _seamstress.arc.remove(id)
    else
      _seamstress.grid.remove(id)
    end
  end,
}

_seamstress.screen = {
  key = function (symbol, modifiers, is_repeat, state, window)
    local char = keycodes[symbol]
    local mods = keycodes.modifier(modifiers)
    if #mods == 1 and mods[1] == "ctrl" and char == "p" and state == 1 and window == 1 then
      _seamstress.screen_show()
    elseif #mods == 1 and mods[1] == "ctrl" and char == "c" and state == 1 then
      _seamstress.quit_lvm()
    elseif Screen.key ~= nil and window == 1 then
      Screen.key(keycodes[symbol], keycodes.modifier(modifiers), is_repeat, state)
    elseif window == 2 then
      menu.key(keycodes[symbol], keycodes.modifier(modifiers), is_repeat, state)
    end
  end,
  mouse = function(x, y, window)
    if Screen.mouse ~= nil and window == 1 then
      Screen.mouse(x, y)
    elseif window == 2 then
      menu.mouse(x, y)
    end
  end,
  click = function(x, y, state, button, window)
    if Screen.click ~= nil and window == 1 then
      Screen.click(x, y, state, button)
    elseif window == 2 then
      menu.click(x, y, state, button)
    end
  end,
  resized = function(x, y, window)
    if Screen.resized ~= nil and window == 1 then
      Screen.resized(x, y)
    elseif window == 2 then
      menu.resized(x, y)
    end
  end,
}

--- startup function; called by spindle to start the script.
-- @tparam string script_file set by calling seamstress with `-s filename`
_startup = function (script_file)
  if not pcall(require, script_file) then
    print("seamstress was unable to find user-provided " .. script_file .. ".lua file!")
    print("create such a file and place it in either CWD or ~/seamstress")
  end
  init()
end
