--- random utils
-- @module util

--[[
  based on norns' util.lua
  norns util.lua first committed by @tehn March 23, 2018
  rewritten for seamstress by @ryleelyman April 30, 2023
]]

local util = {}

--- check whether a file exists
-- @tparam string name filename
-- @treturn bool true if the file exists
-- @function util.exists
function util.exists(name)
  local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    end
    return false
end

--- check whether a file exists
util.file_exists = util.exists

--- make directory (with parents as needed).
-- @tparam string path
function util.make_dir(path)
	os.execute("mkdir -p " .. path)
end

return util
