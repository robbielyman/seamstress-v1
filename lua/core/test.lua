local event = require 'seamstress.event'
local seamstress = require 'seamstress'

local function loadTestFiles(root_files, patterns, options)
  
end

local function runner()
  local busted = require 'busted.core' ()
  require 'busted' (busted)
  local directory = os.getenv("SEAMSTRESS_LUA_PATH") .. package.config:sub(1, 1) .. "test"
  error('TODO')
end

event.addSubscriber({ 'init' }, function()
  local ok, busted = pcall(require, 'busted')
  if ok then
    runner()
    return false
  end
  print(busted)
  seamstress.quit()
  return false
end)
