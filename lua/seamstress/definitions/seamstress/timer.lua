---@meta

---@module 'seamstress.Timer'

---@class Timer
---@field action fun(self: Timer, dt: number)
---@field delta number # must be positive
---@field stage_end integer # negative means infinite
---@field stage integer # current stage
---@field running boolean # set false to stop, true to start
local Timer = {}

---creates a new Timer
---@param action fun(self: Timer, dt: number)
---@param delta number # must be positive
---@param stage_end integer? # negative means infinite
---@param stage integer? # defaults to 1
---@param running boolean? # defaults to true; set running state
---@return Timer
seamstress.Timer = function(action, delta, stage_end, stage, running) end
