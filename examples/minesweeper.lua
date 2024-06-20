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

local t = 0
seamstress.event.addSubscriber({ 'update' }, function(dt)
  t = t + dt
  local col = math.abs(255 * math.sin(t))
  palette.clickable = clickable + seamstress.tui.Color(col, col, col)
  return true, true
end)

local function register(cell)
  seamstress.event.addSubscriber({ 'tui', 'hover' }, function(_, col, row)
    local hit = seamstress.tui.hitTest(col, row, cell)
    local old = cell.state
    cell.state = hit and 'hovered' or 'clickable'
    return true, cell.state ~= old
  end, {predicate = function ()
	return cell.state ~= 'dead'
end})
  seamstress.event.addSubscriber({ 'tui', 'mouse_down' }, function(which)
    if which == 'right' then
      if cell.text == '   ' then cell.text = ' F ' elseif cell.text == ' F ' then cell.text = '   ' end
    elseif which == 'left' then
      GameState:click(cell)
    end
    return false, true
  end, {
    predicate = function(_, col, row)
      return seamstress.tui.hitTest(col, row, cell)
    end
  })
  seamstress.event.addSubscriber({ 'cells', 'draw' }, function()
    seamstress.tui.drawInBox(palette.red(palette[cell.state](cell.text, 'bg'), 'fg'), cell)
    return true
  end)
end


local Cell = {}
Cell.__index = Cell

Cell.new = function(x, y)
  local c = {
    x = { x - 2, x + 2 },
    y = { y - 1, y + 1 },
    border = 'all',
    state = 'clickable',
    text = '   ',
    dirty = true,
  }
  register(c)
  setmetatable(c, Cell)
  return c
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

local draw
---@cast draw Subscriber

function GameState.finish(won)
  seamstress.event.clear({ 'tui' })
  seamstress.event.addSubscriber({ 'tui', 'mouse_down' }, function()
    seamstress.quit()
    return false
  end)
  local dirty = true
  draw:update({
    fn = function()
      if dirty then
        seamstress.tui.clearBox({ x = { 1, -1 }, y = { 1, -1 } })
        dirty = false
      end
      local x = seamstress.tui.cols // 2
      local y = seamstress.tui.rows // 2
      seamstress.tui.drawInBox(
        palette.clickable({'  YOU ' .. (won and 'WON!!' or 'LOST!  '), '', 'click to exit'} --[=[@as string[]]=], 'fg'),
        { x = { x - 6, x + 6 }, y = { y - 1, y + 1 } })
      return true, true
    end
  })
end

seamstress.event.addSubscriber({ 'init' }, function()
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
  draw = seamstress.event.addSubscriber({ 'draw' }, function()
    seamstress.event.publish({ 'cells', 'draw' })
    return true
  end)
  seamstress.update.delta = 1 / 60
  seamstress.update.running = true
  return true
end)
