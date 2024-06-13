require 'seamstress.tui'

local clickable = seamstress.tui.Color('#939ab7')

local palette = {
  hovered = seamstress.tui.Color('#a5adcb') + seamstress.tui.Color('#ffffff'),
  clickable = clickable,
  dead = seamstress.tui.Color('#363a4f'),
  red = seamstress.tui.Color('#ed8796'),
}

local GameState = {
  init = false
}

local Cell = {}
Cell.__index = Cell

local function register(cell)
  seamstress.tui.hover:add(function(...)
    return cell:hover(...)
  end)
  seamstress.tui.mouse_down:add(function(...)
    return cell:mouse_down(...)
  end)
  seamstress.tui.draw:add(function(...)
    cell:draw(...)
  end)
  seamstress.tui.update:add(function(...)
    cell:update(...)
  end)
end

Cell.new = function(x, y)
  local c = {
    x = { x - 2, x + 2 },
    y = { y - 1, y + 1 },
    border = 'all',
    state = 'clickable',
    text = '   ',
    dirty = true,
  }
  setmetatable(c, Cell)
  register(c)
  return c
end

local t = 0
seamstress.tui.update:add(function(_, dt)
  t = t + dt
  local col = math.abs(255 * math.sin(t))
  palette.clickable = clickable + seamstress.tui.Color(col, col, col)
end)

function Cell:update()
  if self.state == 'clickable' then self.dirty = true end
end

function Cell:draw()
  if not self.dirty then return end
  seamstress.tui.drawInBox(palette.red(palette[self.state](self.text, 'bg'), 'fg'), self)
end

function Cell:mouse_down(which, col, row)
  if not seamstress.tui.hitTest(col, row, self) then return end
  if self.state == 'dead' then return end
  if which == 'right' then
    if self.text == '   ' then self.text = '️ F ' elseif self.text == ' F ' then self.text = '   ' end
    self.dirty = true
  elseif which == 'left' then
    GameState:click(self)
  end
end

function Cell:hover(_, col, row)
  if self.state == 'dead' then return end
  local hit = seamstress.tui.hitTest(col, row, self)
  local old = self.state
  self.state = hit and 'hovered' or 'clickable'
  if self.state ~= old then self.dirty = true end
end

local width = 9
local height = 9
local num_mines = 10

local function cellIdxFromPos(x, y)
  return (y - 1) * width + x
end

local function posFromCellIdx(n)
  local x = (n - 1) % width + 1
  local y = (n - x) / width + 1
  return { x, y }
end

local function neighbors(x, y)
  return {
    { x - 1, y - 1 }, { x, y - 1 }, { x + 1, y - 1 },
    { x - 1, y }, { x, y }, { x + 1, y },
    { x - 1, y + 1 }, { x, y + 1 }, { x + 1, y + 1 },
  }
end

function GameState.start(x, y)
  local indices = neighbors(x, y)
  local bad_indices = {}
  for i, v in ipairs(indices) do
    bad_indices[i] = cellIdxFromPos(table.unpack(v))
  end
  local mines = {}
  for i = 1, num_mines do
    local done = true
    local idx
    repeat
      done = true
      idx = math.random(width * height)
      for _, value in ipairs(mines) do
        if idx == value then
          done = false
          break
        end
      end
      if done then
        for _, v in ipairs(bad_indices) do
          if idx == v then
            done = false
            break
          end
        end
      end
    until done
    mines[i] = idx
  end
  GameState.board = {}
  for i = 1, width do
    GameState.board[i] = {}
    for j = 1, height do
      GameState.board[i][j] = 0
    end
  end
  for _, mine in ipairs(mines) do
    local pos = posFromCellIdx(mine)
    local n = neighbors(table.unpack(pos))
    for _, p in ipairs(n) do
      if GameState.board[p[1]] and GameState.board[p[1]][p[2]] then
        GameState.board[p[1]][p[2]] = GameState.board[p[1]][p[2]] + 1
      end
    end
  end
  for _, mine in ipairs(mines) do
    local pos = posFromCellIdx(mine)
    GameState.board[pos[1]][pos[2]] = '💣'
  end
end

function GameState.reveal(x, y)
  local n = neighbors(x, y)
  for _, pos in ipairs(n) do
    if GameState.board[pos[1]] and GameState.board[pos[1]][pos[2]] then
      if GameState.board[pos[1]][pos[2]] == 0 then
        local new = GameState.cells[pos[1]][pos[2]].state ~= 'dead'
        if not new then goto continue end
        GameState.cells[pos[1]][pos[2]].state = 'dead'
        GameState.cells[pos[1]][pos[2]].dirty = true
        GameState.reveal(pos[1], pos[2])
      elseif GameState.board[pos[1]][pos[2]] ~= '💣' then
        local new = GameState.cells[pos[1]][pos[2]].state ~= 'dead'
        if not new then goto continue end
        GameState.cells[pos[1]][pos[2]].state = 'dead'
        GameState.cells[pos[1]][pos[2]].text = ' ' .. GameState.board[pos[1]][pos[2]] .. ' '
        GameState.cells[pos[1]][pos[2]].dirty = true
      end
    end
    ::continue::
  end
end

function GameState.finish(won)
  seamstress.tui.hover = seamstress.tui.Handler.new(nil, true)
  seamstress.tui.mouse_down = seamstress.tui.Handler.new(function()
    seamstress.quit()
  end)
  local dirty = true
  seamstress.tui.update:add(function(_, dt)
    t = t + dt
    local col = math.abs(255 * math.sin(t))
    palette.clickable = clickable + seamstress.tui.Color(col, col, col)
  end)
  seamstress.tui.draw = seamstress.tui.Handler.new(function()
    if dirty then
      seamstress.tui.clearBox({ x = { 1, -1 }, y = { 1, -1 } })
      dirty = false
    end
    local x = seamstress.tui.cols // 2
    local y = seamstress.tui.rows // 2
    seamstress.tui.drawInBox(palette.clickable({'  YOU ' .. (won and 'WON!!' or 'LOST!  '), '', 'click to exit'}, 'fg'),
      { x = { x - 6, x + 6 }, y = { y - 1, y + 1 } })
  end)
end

seamstress.init = function()
  local x = seamstress.tui.cols // 2
  local y = seamstress.tui.rows // 2
  GameState.cells = {}
  for i = 1, width do
    GameState.cells[i] = {}
    for j = 1, height do
      GameState.cells[i][j] = Cell.new(x - 5 * 5 + i * 5, y - 5 * 3 + j * 3)
    end
  end
  GameState.click = function(self, cell)
    for i = 1, width do
      for j = 1, height do
        if self.cells[i][j] == cell then
          if not self.init then
            self.init = true
            GameState.start(i, j)
          end
          if GameState.board[i][j] == '💣' then
            return GameState.finish(false)
          else
            GameState.reveal(i, j)
          end
        end
      end
    end
    for i = 1, width do
      for j = 1, height do
        local c = self.cells[i][j]
        if c.state ~= 'dead' and GameState.board[i][j] ~= '💣' then return end
      end
    end
    GameState.finish(true)
  end
end
