---seamstress is an engine for art.
---@module 'seamstress'

local sys = seamstress._prefix
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
---@cast home string?

package.path = seamstress._pwd ..
    package.config:sub(1, 1) ..
    package.config:sub(5, 5) ..
    '.lua' ..
    package.config:sub(3, 3) ..
    package.path

---path object
seamstress.path = {
  sys = sys,
  home = home,
  pwd = seamstress._pwd,
}


seamstress.event = require 'seamstress.event'

seamstress.event.addSubscriber({ 'quit' }, function()
  seamstress.quit()
  return false
end)

seamstress.event.addSubscriber({ 'hello' }, function(...)
  if seamstress.hello then seamstress.hello(...) end
  if hello then hello(...) end
  return true
end)

seamstress.event.addSubscriber({ 'init' }, function()
  if seamstress.init then seamstress.init() end
  if init then init() end
  return true
end)

seamstress.event.addSubscriber({ 'cleanup' }, function()
  if seamstress.cleanup then seamstress.cleanup() end
  if cleanup then cleanup() end
  return true
end)

local modules = {
  tui = true,
  osc = { 'monome' },
  monome = { 'osc' },
}

--- the global seamstress object.
--- modules are loaded by seamstress when referenced.
setmetatable(seamstress, {
  __index = function(t, key)
    local found = modules[key]
    if found == true then
      local val = require('seamstress.' .. key)
      t[key] = val[1]
      modules[key] = val[1]
      if val[2] == true then
        seamstress._load(key)
        seamstress._launch(key)
      end
    elseif found then
      ---@cast found string[]
      local launch = {}
      for _, k in ipairs(found) do
        local val = require('seamstress.' .. k)
        t[k] = val[1]
        if val[2] == true then table.insert(launch, k) end
      end
      local val = require('seamstress.' .. key)
      t[key] = val[1]
      if val[2] == true then
        seamstress._load(key)
        seamstress._launch(key)
      end
      for _, k in ipairs(launch) do
        seamstress._load(k)
        seamstress._launch(k)
      end
    end
    if found then
      return modules[key]
    else
      return rawget(t, key)
    end
  end
})

local term = os.getenv('TERM')
if term ~= 'dumb' and term ~= 'emacs' then
  _ = seamstress.tui
else
  modules.tui = false
end

-- add with lowest priority so that we commit the render at the end
seamstress.event.addSubscriber({ 'draw' }, function()
  if seamstress.tui then seamstress.tui.renderCommit() end
  return true
end, { priority = 0 })

-- NB: starts disabled! enable with seamstress.update.running = true
seamstress.update = seamstress.Timer(function(_, dt)
  local ret = seamstress.event.publish({ 'update' }, dt)
  for _, v in ipairs(ret) do
    if v then
      seamstress.event.publish({ 'draw' })
      break
    end
  end
end, 1 / 60, -1, 1, false)

---startup function
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
  if ok then
    seamstress.event.publish({ 'hello' }, seamstress.version)
    seamstress.event.publish({ 'init' })
  end
end
