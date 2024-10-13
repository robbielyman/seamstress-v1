---@meta

---@module 'seamstress.Timer'

---@class Timer
---@overload fun(action: fun(self: Timer, dt: number), delta: number, stage_end: integer?, stage: integer?, running: boolean?): Timer
---@field action fun(self: Timer, dt: number)
---@field delta number # must be positive
---@field stage_end integer # negative means infinite
---@field stage integer # current stage
---@field running boolean # set false to stop, true to start
local Timer = {}
