--- startup file
-- @script seamstress

--[[
  seamstress is inspired by monome's norns.
  first commit by @ryleelyman April 30, 2023
]]

grid = require("core/grid")
arc = require("core/arc")
osc = require("core/osc")
util = require("lib/util")
tab = require("lib/tabutil")
screen = require("core/screen")
metro = require("core/metro")
midi = require("core/midi")
clock = require("core/clock")
controlspec = require("core/controlspec")
paramset = require("core/params")
paramsMenu = require("core/menu/params-menu")
params = paramset.new()
print = _seamstress.print

seamstress = {}

seamstress.state = require("core/state")

--- global init function to be overwritten in user scripts.
init = function() end
--- global cleanup function to be overwritten in user scripts.
cleanup = function() end

_seamstress.monome = {
	add = function(id, serial, name, dev)
		if string.find(name, "monome arc") then
			_seamstress.arc.add(id, serial, name, dev)
		else
			_seamstress.grid.add(id, serial, name, dev)
		end
	end,
	remove = function(id)
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
  local filename
  if util.exists(script_file..'.lua') then
    filename = string.sub(script_file,1,1) == "/" and script_file or os.getenv("PWD").."/"..script_file
  elseif util.exists(path.seamstress .. '/' .. script_file .. '.lua') then
    filename = path.seamstress .. '/' .. script_file
  else
    print("seamstress was unable to find user-provided " .. script_file .. ".lua file!")
    print("create such a file and place it in either CWD or ~/seamstress")
  end

  if filename then
    filename = filename .. '.lua'
    path, scriptname = filename:match("^(.*)/([^.]*).*$")

    seamstress.state.script = filename
    seamstress.state.path = path
    seamstress.state.name = scriptname
    seamstress.state.shortname = seamstress.state.name:match( "([^/]+)$" )

    require(script_file)
  end

  clock.add_params()
  init()
  paramsMenu.init()
end

_seamstress.cleanup = function()
	if cleanup ~= nil then
		cleanup()
	end
end
