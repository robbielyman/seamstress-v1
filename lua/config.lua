--- seamstress configuration
-- @script config.lua

-- add to package.path
local home = os.getenv("HOME")
local seamstress_home = home .. "/seamstress"
local sys = _seamstress.prefix .. "/?.lua;"
local core = _seamstress.prefix .. "/core/?.lua;"
local lib = _seamstress.prefix .. "/lib/?.lua;"
local luafiles = _pwd .. "/?.lua;"
local seamstressfiles = seamstress_home .. "/?.lua;"

--- custom package.path setting for require.
-- includes folders under seamstress "share" directory
-- as well as the current directory
-- and `$HOME/seamstress`
package.path = sys .. core .. lib .. luafiles .. seamstressfiles .. package.path

--- path object
path = {
  home = home,                  -- user home directory
  pwd = _pwd,                   -- directory from which seamstress was run
  seamstress = seamstress_home, -- defined to be `home .. '/seamstress'`
}
