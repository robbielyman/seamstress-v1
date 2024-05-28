--- seamstress configuration
-- add to package.path
-- @script config.lua
local home = os.getenv("HOME")
local seamstress_home = home .. "/seamstress"
local sys = _seamstress.prefix .. "/?.lua;"
local core = _seamstress.prefix .. "/core/?.lua;"
local lib = _seamstress.prefix .. "/lib/?.lua;"
local luafiles = _seamstress._pwd .. "/?.lua;"
local seamstressfiles = seamstress_home .. "/?.lua;"

--- custom package.path setting for require.
-- includes folders under seamstress binary directory,
-- as well as the current directory
-- and `$HOME/seamstress`
package.path = sys .. core .. lib .. luafiles .. seamstressfiles .. package.path

--- path object
_seamstress.path = {
  home = home, -- user home directory
  pwd = _seamstress._pwd, -- directory from which seamstress was run
  seamstress = seamstress_home, -- defined to be `home .. '/seamstress'`
}

print = _seamstress._print
--- startup function; called by spindle to start the script.
-- @tparam string script_file set by calling seamstress with `-s filename`

local seamstress = require "seamstress"

_seamstress._startup = function (script_file)
  local filename
    if seamstress.util.exists(script_file .. ".lua") then
        filename = string.sub(script_file, 1, 1) == "/" and script_file or seamstress.path.pwd .. "/" .. script_file
    elseif seamstress.util.exists(seamstress.path.seamstress .. "/" .. script_file .. ".lua") then
      filename = seamstress.path.seamstress .. "/" .. script_file
    else
        print("seamstress was unable to find user-provided " .. script_file .. ".lua file!")
        print("create such a file and place it in either CWD or ~/seamstress")
    end

    if filename then
        dofile(filename)
    end
    seamstress.init()
end

_seamstress.cleanup = function ()
	if seamstress.cleanup ~= nil then seamstress.cleanup() end
end
