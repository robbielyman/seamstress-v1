--- seamstress is an engine for art.
-- @module seamstress

local old_exit = os.exit
os.exit = function(...)
  seamstress.quit()
  old_exit(...)
end

local function setupPath(s)
  local sys = s._prefix
  package.path = sys ..
      package.config:sub(1, 1) ..
      package.config:sub(5, 5) ..
      ".lua" ..
      package.config:sub(3, 3) ..
      package.path
  local home = os.getenv("SEAMSTRESS_HOME")
  if not home then
    local homedir = os.getenv("HOME")
    if homedir then home = homedir .. package.config:sub(1, 1) .. "seamstress" end
    if home then
      package.path = home ..
          package.config:sub(1, 1) ..
          package.config:sub(5, 5) ..
          '.lua' ..
          package.config:sub(3, 3) ..
          package.path
    end
  end
  package.path = s._pwd ..
      package.config:sub(1, 1) ..
      package.config:sub(5, 5) ..
      '.lua' ..
      package.config:sub(3, 3) ..
      package.path
  return {
    sys = sys,
    home = home,
    pwd = s._pwd,
  }
end

local modules = {}

--- the global seamstress object.
-- modules are loaded by seamstress when referenced.
setmetatable(seamstress, {
  __index = function(t, key)
    local found = modules[key]
    if found then
      rawset(t, key, require('seamstress.' .. key))
      seamstress._load(key)
      return rawget(t, key)
    else
      return rawget(t, key)
    end
  end
})
seamstress.path = setupPath(seamstress)

local term = os.getenv("TERM")
if term ~= 'dumb' and term ~= 'emacs' then
	seamstress.tui = require 'seamstress.tui'
end


seamstress.cleanup = function()
  if cleanup then cleanup() end
end
seamstress.init = function()
  if init then init() end
end
seamstress._start = function()
  local filename = seamstress.config.script_name
  local ok, err = true, nil
  if filename == "test" or filename == "test.lua" then
    local tests = require('seamstress.test.init')
    tests.run()
    return
  elseif filename then
    local suffixed = filename:find(".lua")
    ok, err = pcall(require, suffixed and filename:sub(1, suffixed - 1) or filename)
    if not ok then
      print("ERROR: " .. err)
      print("seamstress will continue as a REPL")
    end
  end
  if ok and seamstress.hello then seamstress.hello(seamstress.version) end
  if ok then seamstress.init() end
end

seamstress._unload = function(which)
  if modules[which] then
    local promise = seamstress.__unload(which):anon(function() seamstress.___unload(which) end)
    return promise
  end
end
