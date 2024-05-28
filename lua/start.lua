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

_seamstress._startup = function (script_file)
	
end

seamstress = require "seamstress"
