--- TUI interaction module
-- @module seamstress.tui
-- @author Rylee Alanza Lyman

local tui = {
  update = function(dt) end,
  draw = function() end,

  history = { idx = nil },
  Handler = {},

  palette = seamstress.config.palette and seamstress.config.palette or {},
  styles = seamstress.config.styles and seamstress.config.styles or {},
}

local methods = {
  clearBox = true,
  drawInBox = true,
  showCursorInBox = true,
  update = true,
  draw = true,
  key_down = true,
}

local _print = function (...)
  local args = { ... }
  if #args == 0 then return end
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

local metatable = {
  __index = function(t, key)
    if methods[key] then
      seamstress._launch("tui")
      print = _print
      setmetatable(t, nil)
      return t[key]
    else
      return rawget(t, key)
    end
  end
}

return setmetatable(tui, metatable)
