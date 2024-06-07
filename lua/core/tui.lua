_seamstress.tui = {
  stdin = {},
  stdout = {},
  history = {
    idx = nil,
  },
  logs = {},
}

local tui = {
  color = _seamstress.tuiColorNew,
  style = _seamstress.tuiStyleNew,
  cell = _seamstress.tuiCellNew,
  line = _seamstress.tuiLineNew,
  clearBox = _seamstress.tuiClearBox,
  drawInBox = _seamstress.tuiDrawInBox,
  showCursorInBox = _seamstress.tuiShowCursorInBox,
  history = { idx = nil },
  key_down = {
    ['C-c'] = function()
      _seamstress.quit()
    end
  },
  palette = _seamstress.config.palette and _seamstress.config.palette or {},
  styles = _seamstress.config.styles and _seamstress.config.styles or {},
}

local white = tui.color(255, 255, 255)
local red = tui.color(255, 0, 0)
local green = tui.color(0, 255, 0)
local blue = tui.color(0, 0, 255)
local yellow = red + green + white
local orange = yellow + red
local teal = blue + green
local indigo = blue + red + blue
local violet = indigo + red + white
local black = tui.color(0, 0, 0)
local pink = red + white
local sky = blue + white
local brown = black + orange + white

_seamstress.tui.colors = tui.palette

_seamstress.tui.styles = tui.styles


tui.Entity = require('core.tui.entity')(tui)
tui.TextInput = require('core.tui.text_input')(tui)
tui.ScrollBox = require('core.tui.scroll_box')(tui)
tui.FixedBox = require('core.tui.fixed_box')(tui)

-- tui.logs = tui.ScrollBox.new(_seamstress.tui.logs, { x = { 2, -2 }, y = { -14, -13 } })
-- tui.logs.update = function()
-- tui.logs.dirty = true
-- end
-- tui.logs:activate('update')
tui.stdout = tui.ScrollBox.new(_seamstress.tui.stdout, { x = { 2, -2 }, y = { 1, -6 } })

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

-- _seamstress.tui.hello = function(version)
--   local str = pink('S', 'fg') ..
--       red('E', 'fg') ..
--       orange('A', 'fg') ..
--       yellow('M', 'fg') ..
--       green('S', 'fg') ..
--       teal('T', 'fg') ..
--       blue('R', 'fg') ..
--       sky('E', 'fg') ..
--       violet('S', 'fg') ..
--       brown('S', 'fg')
--   print(str)
--   local version_string = version[1] .. '.' .. version[2] .. '.' .. version[3]
--   if version.pre then version_string = version_string .. '-' .. version.pre end
--   print(sky("seamstress version: " .. version_string, 'fg'))
-- end


tui.stdin = tui.TextInput.new({ x = { 1, -1 }, y = { -5, -1 }, border = 'all' })
tui.stdin.key_down['S-enter'] = tui.stdin.key_down.enter
tui.stdin.key_down.enter = function()
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
      table.insert(_seamstress.tui.stdout, line)
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

-- tui.bouncer = {}
-- for i = 1, 8 do
--   local dir_x, dir_y = math.random(), math.random()
--   local norm = math.sqrt(dir_x * dir_x + dir_y * dir_y)
--   local dir = { dir_x / norm, dir_y / norm }
--   local w = _seamstress.tui_cols and _seamstress.tui_cols or 30
--   local h = _seamstress.tui_rows and _seamstress.tui_rows or 30

--   local SEAMSTRESS_TXT = pink('S', 'fg') ..
--       red('E', 'fg') ..
--       orange('A', 'fg') ..
--       yellow('M', 'fg') ..
--       green('S', 'fg') ..
--       teal('T', 'fg') ..
--       blue('R', 'fg') ..
--       sky('E', 'fg') ..
--       violet('S', 'fg') ..
--       brown('S', 'fg')

--   local x = 30 * math.random()
--   local y = 10 * math.random()
--   local b = tui.FixedBox.new({ SEAMSTRESS_TXT }, { x = { x, x + 10 }, y = { y, y } })
--   b.update = function(dt)
--     if b.hitbox.x[1] <= 1 then dir[1] = -dir[1] end
--     if b.hitbox.x[2] >= w then dir[1] = -dir[1] end
--     if b.hitbox.y[1] <= 1 then dir[2] = -dir[2] end
--     if b.hitbox.y[2] >= h - 12 then dir[2] = -dir[2] end
--     b.move(dir[1] * dt * 10, dir[2] * dt * 10)
--     b.dirty = true
--   end
--   b.resize = function(width, height)
--     w, h = width, height
--     b.dirty = true
--     b.update(0.1)
--   end
--   b:activate({ 'update', 'resize', 'draw' })
--   tui.bouncer[i] = b
-- end

return tui
