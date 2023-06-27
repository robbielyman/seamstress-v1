--- seamstress configuration
-- add to package.path
-- @script config.lua
local home = os.getenv('HOME')
local pwd = os.getenv('PWD')
local seamstress_home = home .. '/seamstress'
local seamstress = '/usr/local/share/seamstress/lua'
local sys = seamstress .. '/?.lua;'
local core = seamstress .. '/core/?.lua;'
local lib = seamstress .. '/lib/?.lua;'
local luafiles = pwd .. '/?.lua;'
local seamstressfiles = seamstress_home .. '/?.lua;'

--- custom package.path setting for require.
-- includes folders under `/usr/local/share/seamstress/lua`,
-- as well as the current directory
-- and `$HOME/seamstress`
package.path = sys .. core .. lib .. luafiles .. seamstressfiles.. package.path

--- path object
path = {
  home = home, -- user home directory
  pwd = pwd, -- directory from which seamstress was run
  seamstress = seamstress_home -- defined to be `home .. '/seamstress'`
}

_old_print = print

-- norns compatibility fns

-- as currently seamstress doesn't allow to switch scripts at runtime,
-- PWD got added to package.path, making this fn a simple alias
function include(file)
  return require(file)
end
