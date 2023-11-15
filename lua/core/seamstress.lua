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
_menu = paramsMenu
pmap = require("core/pmap")
params = paramset.new()
print = _seamstress.print

seamstress = {}

seamstress.state = require("core/state")

_menu.timer = metro[36]

--- global init function to be overwritten in user scripts.
init = function() end
--- global redraw function to be overwritten in user scripts.
redraw = function() end
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
_startup = function(script_file)
  local filename
  if util.exists(script_file .. ".lua") then
    filename = string.sub(script_file, 1, 1) == "/" and script_file or os.getenv("PWD") .. "/" .. script_file
  elseif util.exists(path.seamstress .. "/" .. script_file .. ".lua") then
    filename = path.seamstress .. "/" .. script_file
  else
    print("seamstress was unable to find user-provided " .. script_file .. ".lua file!")
    print("create such a file and place it in either CWD or ~/seamstress")
  end

  if filename then
    filename = filename .. ".lua"
    local ps = path.seamstress
    local path, scriptname = filename:match("^(.*)/([^.]*).*$")

    seamstress.state.script = filename
    seamstress.state.path = path
    seamstress.state.name = scriptname
    seamstress.state.shortname = seamstress.state.name:match("([^/]+)$")
    seamstress.state.data = ps .. "/data/" .. scriptname .. "/"
    if util.file_exists(seamstress.state.data) == false then
      print("### initializing data folder at " .. seamstress.state.data)
      util.make_dir(seamstress.state.data)
      if util.file_exists(seamstress.state.path .. "/data") then
        os.execute("cp " .. seamstress.state.path .. "/data/*.pset " .. seamstress.state.data)
        print("### copied default PSETs")
      end
    end

    local file = seamstress.state.data .. "pset-last.txt"
    params:clear()
    pmap.clear()

    if util.file_exists(file) then
      local f = io.open(file, "r")
      io.input(f)
      local i = io.read("*line")
      io.close(f)
      if i then
        print("### PSET last used: " .. i)
        seamstress.state.pset_last = tonumber(i)
      end
    end

    dofile(filename)
  end

  clock.add_params()
  local version_match = true
  if seamstress.version_required ~= nil then
    local parsed_required_version = {}
    for str in string.gmatch(seamstress.version_required, "([^.]+)") do
      table.insert(parsed_required_version, tonumber(str))
    end
    if parsed_required_version[1] > _seamstress.version[1] then
      version_match = false
      goto finished
    elseif parsed_required_version[1] < _seamstress.version[1] then
      goto finished
    end
    if parsed_required_version[2] > _seamstress.version[2] then
      version_match = false
      goto finished
    elseif parsed_required_version[2] <= _seamstress.version[2] then
      if parsed_required_version[3] > _seamstress.version[3] then
        version_match = false
        goto finished
      end
    end
  end
  ::finished::
  if version_match then
    init()
  else
    print(
      "!!! this script ("
        .. seamstress.state.name
        .. ") requires seamstress version "
        .. seamstress.version_required
    )
    print("!!! script not initialized, please update seamstress")
  end
  paramsMenu.init()
  pmap.read()
  if seamstress.state.path then
    return seamstress.state.path .. "/" .. script_file .. ".lua"
  end
end

_seamstress.cleanup = function()
  if cleanup ~= nil then
    cleanup()
  end
end
