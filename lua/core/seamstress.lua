--- startup file
-- @script seamstress
grid = require 'core/grid'
arc = require 'core/arc'
osc = require 'core/osc'
util = require 'lib/util'
screen = require 'core/screen'
metro = require 'core/metro'
midi = require 'core/midi'
clock = require 'core/clock'
print = _seamstress.print

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

--- startup function; called by spindle to start the script.
-- @tparam string script_file set by calling seamstress with `-s filename`
_startup = function (script_file)
  if not util.exists(script_file..'.lua') and not util.exists(path.seamstress .. '/' .. script_file .. '.lua')then
    print("seamstress was unable to find user-provided " .. script_file .. ".lua file!")
    print("create such a file and place it in either CWD or ~/seamstress")
  else
    require(script_file)
    init()
  end
end
