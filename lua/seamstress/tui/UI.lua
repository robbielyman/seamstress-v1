---@module 'seamstress.tui.UI'
---@author Rylee Alanza Lyman
local M = {}

---@class Pane
M.Pane = {
  root = {
    children = {},
    visible = true,
    first_responder = true,
  }
}
M.Pane.__index = M.Pane

seamstress.event.addSubscriber({})

M.Pane.new = function(parent, size, location, options)
    local p = setmetatable({}, M.Pane)
    return p
end

---@alias State 'active' | 'hovered' | 'depressed' | 'inactive'

---@class Button
M.Button = {}
M.Button.__index = M.Button

---creates a new button
---@param title string|{[State]: {title: string, style: Style?}?}
---@param action fun()?
---@param location [integer|'centered',integer|'centered']?
---@param parent Pane?
---@param options table?
---@return Button
M.Button.new = function(title, action, location, parent, options)
  if type(title) == 'string' then
  elseif type(title) == 'userdata' then
  else
  end
  action = action or function() end
  if type('action') ~= "function" then
    options = parent --[[@as table?]]
    parent = location --[[@as Pane?]]
    location = action --[[@as [integer|'centered',integer|'centered']?]]
    action = function() end
  end
  location = location or { 'centered', 'centered' }
  if not location[1] then
    options = parent --[[@as table?]]
    parent = location --[[@as Pane?]]
    location = { 'centered', 'centered' }
  end
  parent = parent or M.Pane.root
  local b = setmetatable({
    active = active,
    hovered = hovered,
    depressed = depressed,
    inactive = inactive,
    state = state
  }, M.Button)
  return b
end


return M
