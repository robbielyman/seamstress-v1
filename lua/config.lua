--- seamstress configuration
-- add to package.path
-- @script config.lua
local home = os.getenv("HOME")
local seamstress_home = home .. "/seamstress"
local sys = _seamstress.prefix .. "/?.lua;"
local core = _seamstress.prefix .. "/core/?.lua;"
local lib = _seamstress.prefix .. "/lib/?.lua;"
local luafiles = _pwd .. "/?.lua;"
local seamstressfiles = seamstress_home .. "/?.lua;"

--- custom package.path setting for require.
-- includes folders under `/usr/local/share/seamstress/lua`,
-- as well as the current directory
-- and `$HOME/seamstress`
package.path = sys .. core .. lib .. luafiles .. seamstressfiles .. package.path

--- path object
path = {
  home = home, -- user home directory
  pwd = _pwd, -- directory from which seamstress was run
  seamstress = seamstress_home, -- defined to be `home .. '/seamstress'`
}

_old_print = print

--- include
-- inspired by norns' version
-- norns does the lookup in the following dirs: norns.state.path, _path.code, _path.extn
function include(file)
  local dirs = { seamstress.state.path, path.pwd, path.seamstress }
  -- case prefixed w/ script folder's name (equivalent to norns' _path.code)
  if string.match(file, "^(%w+)/") == string.match(seamstress.state.path, "/(%w+)$") then
    table.insert(dirs, 2, seamstress.state.path .. "/..")
  end
  for _, dir in ipairs(dirs) do
    local p = dir .. "/" .. file .. ".lua"
    if util.exists(p) then
      print("including " .. p)
      return dofile(p)
    end
  end

  -- didn't find anything
  print("### MISSING INCLUDE: " .. file)
  error("MISSING INCLUDE: " .. file, 2)
end
