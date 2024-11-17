---@meta
---@module 'seamstress.osc.Client'

---represents a remote OSC communicator
---@class seamstress.osc.Client
local client = {}

client.__index = client

function Client(tbl)
  return setmetatable(tbl, client)
end

local osc = require 'seamstress.osc'

function client:dispatch(server, msg, address, time)
  for pattern, func in pairs(self) do
    if osc.matchPath(pattern, msg.path) then
      local ok, keep_going = pcall(func, server, msg, address, time)
      if ok then
        if not keep_going then return end
      else
        seamstress.event.publish({ 'error' }, keep_going)
      end
    end
  end
end

return Client
