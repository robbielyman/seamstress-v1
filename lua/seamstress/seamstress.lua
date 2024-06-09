--- seamstress is an engine for art.
-- @module seamstress

local modules = {
  path = true,
  monome = true,
  osc = true,
  tui = true,
}

--- the global seamstress object.
-- modules are loaded by seamstress when referenced.
seamstress = setmetatable({
  cleanup = function()
    if cleanup then cleanup() end
  end,
  _start = function()
    if seamstress.hello then seamstress.hello(seamstress.version) end
  end,
}, {
    __index = function(t, key)
    local found = modules[key]
    if found then
      rawset(t, key, require('seamstress.' .. key))
      seamstress._load(key)
      return t[key]
    else
      return t[key]
    end
  end
})
