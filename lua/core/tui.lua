---
-- TUI interaction module
-- @module seamstress.tui
-- @author Rylee Alanza Lyman

local tui = {
  --- constructs a seamstress.tui.Color object
  color = _seamstress.tuiColorNew,
  style = _seamstress.tuiStyleNew,
  line = _seamstress.tuiLineNew,
  clearBox = _seamstress.tuiClearBox,
  drawInBox = _seamstress.tuiDrawInBox,
  showCursorInBox = _seamstress.tuiShowCursorInBox,
  history = { idx = nil },
  key_down = function(key, txt)
    print(key, txt)
    if key == 'C-c' then
        _seamstress.quit()
      end
  end,
  palette = _seamstress.config.palette and _seamstress.config.palette or {},
  styles = _seamstress.config.styles and _seamstress.config.styles or {},
  Entity = {},
  TextInput = {},
  ScrollBox = {},
  FixedBox = {},
}


_seamstress.tui = {
  history = { idx = nil },
  logs = {},
  colors = tui.palette,
  styles = tui.styles,
}


tui.Entity = require('core.tui.entity')(tui)
tui.TextInput = require('core.tui.text_input')(tui)
tui.ScrollBox = require('core.tui.scroll_box')(tui)
tui.FixedBox = require('core.tui.fixed_box')(tui)

tui.logs = tui.ScrollBox.new(_seamstress.tui.logs, { x = { 2, -2 }, y = { 1, 4 } })
tui.logs.update = function()
  tui.logs.dirty = true
end
tui.logs:activate('update')
tui.stdout = tui.ScrollBox.new({}, { x = { 2, -2 }, y = { 5, -6 } })

_seamstress._print = function(...)
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
  if type(line) ~= 'userdata' then line = tui.line(line) end
  tui.stdout.data[n] = line
  tui.stdout.dirty = true
end


tui.stdin = tui.TextInput.new({ x = { 1, -1 }, y = { -5, -1 }, border = 'all' })
tui.stdin.key_down['S-enter'] = tui.stdin.key_down.enter
tui.stdin.key_down.enter = function()
  tui.stdin.dirty = true
  local chunk = ""
  for _, line in ipairs(tui.stdin.data) do
    local str = tostring(line)
    if str == "quit" then _seamstress.quit() end
    chunk = chunk .. str .. '\n'
  end
  -- add return
  local func, err = load("return " .. chunk, "stdin", "t", _G)
  -- that didn't compile
  if type(err) == "string" then
    -- try without return
    func, err = load(chunk, "stdin", "t", _G)
  end
  -- that still didn't compile
  if type(err) == "string" then
    if string.sub(err, -5) == "<eof>" then
      -- we're continuing, so act as if we pressed shift-enter
      tui.stdin.key_down['S-enter']()
      return
    end
    -- there was some other syntax error, so print it
    print(err)
    -- clear the buffer
    tui.stdin.clear()
    tui.history.idx = nil
    return
  end
  -- that compiled!
  -- add the buffer to history
  if func then
    table.insert(tui.history, tui.stdin.data)
    for _, line in ipairs(tui.stdin.data) do
      print(line)
    end
  end
  tui.stdout.dirty = true
  tui.stdin.clear()
  if func then
    local rets = { pcall(func) }
    print(table.unpack(rets, 2))
  end
  tui.history.idx = nil
end

local function deepCopyList(t)
  if type(t) ~= 'table' then return t end
  local ret = {}
  for i, value in ipairs(t) do
    ret[i] = deepCopyList(value)
  end
  return ret
end

tui.stdin.key_down['S-up'] = tui.stdin.key_down.up
tui.stdin.key_down.up = function()
  if tui.history.idx and tui.history.idx > 1 then
    tui.history.idx = tui.history.idx - 1
    tui.stdin.data = deepCopyList(tui.history[tui.history.idx])
    tui.stdin.cursor.y = #tui.stdin.data
    tui.stdin.cursor.x = #(tui.stdin.data[tui.stdin.cursor.y])
    tui.stdin.dirty = true
  elseif #tui.history > 0 then
    tui.history.idx = #tui.history
    tui.stdin.data = deepCopyList(tui.history[tui.history.idx])
    tui.stdin.cursor.y = #tui.stdin.data
    tui.stdin.cursor.x = #(tui.stdin.data[tui.stdin.cursor.y])
    tui.stdin.dirty = true
  end
end

return tui
