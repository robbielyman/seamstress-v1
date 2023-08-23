--- table utility
-- @module tab
local tab = {}

--[[
  based on norns' tabutil.lua
  norns tabutil.lua first committed by @catfact Feb 9, 2018
  rewritten for seamstress by @dndrks June 26, 2023
]]

--- print the contents of a table
-- @tparam table t table to print
tab.print = function(t)
  for k, v in pairs(t) do
    print(k .. "\t" .. tostring(v))
  end
end

--- return a lexigraphically sorted array of keys for a table
-- @tparam table t table to sort
-- @treturn table sorted table
tab.sort = function(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

--- count the number of entries in a table;
-- unlike table.getn() or #table, nil entries won't break the loop
-- @tparam table t table to count
-- @treturn number count
tab.count = function(t)
  local c = 0
  for _ in pairs(t) do
    c = c + 1
  end
  return c
end

--- search table for element
-- @tparam table t table to check
-- @param e element to look for
-- @treturn boolean t/f is element is present
tab.contains = function(t, e)
  for index, value in ipairs(t) do
    if value == e then
      return true
    end
  end
  return false
end

--- given a simple table of primitives,
--- "invert" it so that values become keys and vice versa.
--- this allows more efficient checks on multiple values
-- @param t a simple table
tab.invert = function(t)
  local inv = {}
  for k, v in pairs(t) do
    inv[v] = k
  end
  return inv
end

--- search table for element, return key
-- @tparam table t table to check
-- @param e element to look for
-- @return key, nil if not found
tab.key = function(t, e)
  for index, value in ipairs(t) do
    if value == e then
      return index
    end
  end
  return nil
end

--- split multi-line string into table of strings
-- @tparam string str string with line breaks
-- @treturn table table with entries for each line
tab.lines = function(str)
  local t = {}
  local function helper(line)
    table.insert(t, line)
    return ""
  end
  helper((str:gsub("(.-)\r?\n", helper)))
  return t
end

--- split string into table with delimiter
-- @tparam string inputstr : string to split
-- @tparam string sep : delimiter
tab.split = function(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

return tab
