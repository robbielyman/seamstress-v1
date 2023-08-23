--- vport helper module
-- @module vport
local vport = {}

--- wrap a function
function vport.wrap(method)
  return function(self, ...)
    if self.device then
      return self.device[method](self.device, ...)
    end
  end
end

return vport
