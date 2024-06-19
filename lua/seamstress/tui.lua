--- TUI interaction module
---@module 'seamstress.tui'
---@author Rylee Alanza Lyman

---@class seamstress.tui
local tui = {
  ui = require 'seamstress.tui.ui',

  ['C-c'] = seamstress.event.addSubscriber({ 'tui', 'key_down', 'C-c' }, function()
    seamstress.event.publish({ 'quit' })
    return false
  end),

  history = { idx = nil },

  rows = 0,
  cols = 0,

  palette = seamstress.config.palette and seamstress.config.palette or {},
  styles = seamstress.config.styles and seamstress.config.styles or {},

  ---@class seamstress.tui.stdout
  ---@field [integer] string|Line
  ---@field dirty boolean
  ---@field box Box
  stdout = {
    dirty = false,
    box = { x = { 1, -1 }, y = { 1, -1 } },
  },
}

---Tests whether an x,y coordinate pair lies within a `Box`.
---@param x integer
---@param y integer
---@param box Box
---@return boolean whether the box is hit.
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

tui._print = function(...)
  local args = { ... }
  if #args == 0 then return end
  local line
  for i, v in ipairs(args) do
    if i == 1 then
      line = v
    else
      line = line .. '    ' .. v
    end
  end
  if type(line) ~= 'userdata' then
    line = line:gsub('\t', '    ')
    line = seamstress.tui.Line(line)
  else
    line = { line }
  end
  for _, l in ipairs(line) do
    seamstress.log(l --[[@as Line]])
    table.insert(tui.stdout, l)
  end
  tui.stdout.dirty = true
end

local term = os.getenv('TERM')
if term ~= 'dumb' and term ~= 'emacs' then
  print = tui._print
end

return tui, false
