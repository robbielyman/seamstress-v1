local Box = {}
Box.__index = Box

function Box.new(spec)
  return setmetatable({ spec = spec }, Box)
end

function Box:resize(width, height)
  self.x[1] = self.spec.x[1] <= 0 and width + self.spec.x[1] + 1 or self.spec.x[1]
  self.y[1] = self.spec.y[1] <= 0 and height + self.spec.y[1] + 1 or self.spec.y[1]
  self.x[2] = self.spec.x[2] < 0 and width + self.spec.x[2] + 1 or self.spec.x[2]
  self.y[2] = self.spec.y[2] < 0 and height + self.spec.y[2] + 1 or self.spec.y[2]
end

Box.__call = Box.new

return Box
