--- startup file
-- @script seamstress

--[[
  seamstress is inspired by monome's norns.
  first commit by @ryleelyman April 30, 2023
]]

grid = require "core.grid"
arc = require "core.arc"
osc = require "core.osc"
util = require "lib.util"
metro = require "core.metro"
clock = require "core.clock"
testing = require "lib.testing"

seamstress = {}

seamstress.state = require "core.state"
seamstress.version_required = nil

seamstress.run_tests = _seamstress.run_tests

--- global init function to be overwritten in user scripts
init = function() end
--- global redraw function to be overwritten in user scripts
redraw = function() end
--- global cleanup function to be overwritten in user scripts
cleanup = function() end

--- startup function; called by spindle to start the script.
-- @tparam string script_file the script to run
_startup = function()
  if seamstress.run_tests then require "core.tests" end
  local script_file = _seamstress.config.script_file or "script"
  local filename
  if util.exists(script_file .. ".lua") then
    filename = string.sub(script_file, 1, 1) == "/" and script_file or path.pwd .. "/" .. script_file
  elseif util.exists(path.seamstress .. "/" .. script_file) then
    filename = path.seamstress .. "/" .. script_file
  else
    print("seamstress was unable to find user-provided " .. script_file .. ".lua file!")
    print("create such a file and place it in either CWD or ~/seamstress")
  end

  if filename then
    filename = filename .. ".lua"
    local ps = path.seamstress
    local path, script_name = filename:match("^(.*)/([^.]*).*$")

    seamstress.state.script = filename
    seamstress.state.path = path
    seamstress.state.name = script_name
    seamstress.state.shortname = seamstress.state.name:match("([^/]+)$")
    seamstress.state.data = ps .. "/data" .. script_name .. "/"
    if util.exists(seamstress.state.data) == false then
      print("### initializing data folder at " .. seamstress.state.data)
      util.make_dir(seamstress.state.data)
      if util.exists(seamstress.state.path .. "/data") then
        os.execute("cp " .. seamstress.state.path .. "/data/*.pset " .. seamstress.state.data)
        print("### copied default PSETs")
      end
    end

    local file = seamstress.state.data .. "pset-last.txt"
    -- TODO: is this necessary?
    -- params:clear()
    -- pmap.clear()

    if util.exists(file) then
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
  local version_match = (seamstress.version_required == nil)
      or util.version_compare(seamstress.version_required, _seamstress.version) <= 0
  if version_match then
    if seamstress.run_tests then testing.run() end
    init()
  else
    print("### this script (" ..
      seamstress.state.name .. ") requires seamstress version " .. seamstress.version_required)
    print("### script not initialized, please update seamstress")
  end
  -- params_menu.init()
  -- pmap.read()
  if seamstress.state.path then
    _seamstress.config.script_file = seamstress.state.path .. "/" .. script_file .. ".lua"
  end
end

_seamstress.cleanup = function()
  if cleanup ~= nil then cleanup() end
end

--- include
-- inspired by norns
function include(file)
  local dirs = { seamstress.state.path, path.pwd, path.seamstress }
  -- prefixed w/ script folder's name
  if string.match(file, "^(%w+)/") == string.match(seamstress.state.path, "/(%w+)$") then
    table.insert(dirs, 2, seamstress.state.path .. "/..")
  end
  -- look for and include the file
  for _, dir in ipairs(dirs) do
    local p = dir .. "/" .. file .. ".lua"
    if util.exists(p) then
      print("including " .. p)
      return dofile(p)
    end
  end
  -- didn't find anything
  error("MISSING INCLUDE: " .. file, 2)
end
