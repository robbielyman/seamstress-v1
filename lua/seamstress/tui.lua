--- TUI interaction module
-- @module seamstress.tui
-- @author Rylee Alanza Lyman

local Handler = {
  __name = 'seamstress.tui.Handler',
}

Handler.new = function(f, exclusive)
  if exclusive then exclusive = true else exclusive = false end
  return setmetatable(
    {
      _f = f and f or function() return false end,
      exclusive = exclusive,
    },
    Handler)
end

Handler.__index = Handler

Handler.__call = function(self, ...)
  if self == Handler then return Handler.new(...) end
  if self.exclusive then
    local function call(f, ...)
      if type(f) ~= 'function' and f[arg[1]] then
        if f[arg[1]](table.unpack(arg, 2)) then return true end
      else
        if f(...) then return true end
      end
    end
    for _, handler in ipairs(self) do
      if call(handler, ...) then return true end
    end
    return call(self._f, ...)
  else
    local function call(f, ...)
      if type(f) ~= 'function' and f[arg[1]] then
        f[arg[1]](table.unpack(arg, 2))
      else
        f(...)
      end
    end
    for _, handler in ipairs(self) do
      call(handler, ...)
    end
    call(self._f, ...)
  end
end

function Handler:add(other, key)
  if not key then
    local n = #self
    self[n + 1] = other
    return
  end
  if type(self[key]) == 'function' then
    local new = Handler.new()
    new:add(self[key])
    new:add(other)
    self[key] = new
  else
    if not self[key] then
      self[key] = other
      return
    end
    self[key]:add(other)
  end
end

function Handler:remove(other, key)
  if not key then
    for i, match in ipairs(self) do
      if other == match then
        table.remove(self, i)
        break
      end
    end
    return
  end
  if self[key] == other then
    self[key] = nil
    return
  end
  if type(self[key]) == 'table' then
    self[key]:remove(other)
  end
end

local tui = {
  update = Handler.new(),
  draw = Handler.new(),
  key_down = Handler.new(function(...) print(...) end, true),
  key_up = Handler.new(nil, true),
  scroll = Handler.new(nil, true),
  mouse_down = Handler.new(nil, true),
  mouse_up = Handler.new(nil, true),
  hover = Handler.new(nil, true),
  drag = Handler.new(nil, true),
  paste = Handler.new(nil, true),
  window_focus = Handler.new(),
  resize = Handler.new(),

  history = { idx = nil },
  Handler = Handler,

  palette = {},
  styles = {},

  rows = 0,
  cols = 0,
  --  palette = seamstress.config.palette and seamstress.config.palette or {},
  --  styles = seamstress.config.styles and seamstress.config.styles or {},
}

function tui.hitTest(x, y, box)
  local x_start = box.x[1] < 0 and box.x[1] + tui.cols or box.x[1]
  if x < x_start then return false end
  local x_end = box.x[2] < 0 and box.x[2] + tui.cols or box.x[2]
  if x > x_end then return false end

  local y_start = box.y[1] < 0 and box.y[1] + tui.rows or box.y[1]
  if y < y_start then return false end
  local y_end = box.y[2] < 0 and box.y[2] + tui.rows or box.y[2]
  if y > y_end then return false end

  return true
end

tui.key_down:add(function()
  seamstress.quit()
  return true
end, 'C-c')

local methods = {
  clearBox = true,
  drawInBox = true,
  showCursorInBox = true,
  update = true,
  draw = true,
  key_down = true,
  key_up = true,
  scroll = true,
  mouse_down = true,
  mouse_up = true,
  hover = true,
  drag = true,
  paste = true,
  window_focus = true,
  resize = true,
  redraw = true,
  rows = true,
  cols = true,
}

local _print = function(...)
  local args = { ... }
  if #args == 0 then return end
  if not tui.stdout then
    seamstress.log(...)
    return
  end
  local n = #tui.stdout.data + 1
  local line
  for i, v in ipairs(args) do
    if i == 1 then
      line = v
    else
      line = line .. '    ' .. v
    end
  end
  if type(line) ~= 'userdata' then line = tui.Line(line) end
  tui.stdout.data[n] = line
  tui.stdout.dirty = true
end

return tui
