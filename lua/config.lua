--- seamstress configuration
-- add to package.path
-- @script config.lua
local home = os.getenv("HOME")
local pwd = os.getenv("PWD")
local seamstress_home = home .. "/seamstress"
local sys = _seamstress.prefix .. "/?.lua;"
local core = _seamstress.prefix .. "/core/?.lua;"
local lib = _seamstress.prefix .. "/lib/?.lua;"
local luafiles = pwd .. "/?.lua;"
local seamstressfiles = seamstress_home .. "/?.lua;"

--- custom package.path setting for require.
-- includes folders under `/usr/local/share/seamstress/lua`,
-- as well as the current directory
-- and `$HOME/seamstress`
package.path = sys .. core .. lib .. luafiles .. seamstressfiles .. package.path

--- path object
path = {
	home = home, -- user home directory
	pwd = pwd, -- directory from which seamstress was run
	seamstress = seamstress_home, -- defined to be `home .. '/seamstress'`
}

_old_print = print

function include(file)
  -- local dirs = {norns.state.path, _path.code, _path.extn}
  local dirs = {seamstress.state.path, path.pwd, path.seamstress}
  for _, dir in ipairs(dirs) do
    local p = dir..'/'..file..'.lua'
    -- if util.file_exists(p) then
    if util.exists(p) then
      print("including "..p)
      return dofile(p)
    end
  end

  -- didn't find anything
  print("### MISSING INCLUDE: "..file)
  error("MISSING INCLUDE: "..file,2)
end
