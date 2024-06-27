---@meta

---@module 'seamstress.clock'

---@class seamstress.clock
---@field tempo number
---@field is_playing boolean
---@field time number
---@field link_quantum number
---@field source 'internal' | 'midi' | 'link'
---@field beat number
seamstress.clock = {}

---@class Clock
---@field id integer
---@field coro thread

---creates and starts a new
---@param f fun(...)
---@param ... unknown args passed to f
---@return Clock
function seamstress.clock.run(f, ...) end

---cancels a clock
---@param clock Clock|integer # if an integer, should be a clock.id
function seamstress.clock.cancel(clock) end

---sleeps the containing clock to be resumed automatically
---@param seconds number # sleep time
function seamstress.clock.sleep(seconds) end

---sleeps the containing clock to be resumed automatically
---@param beat number # in beats
---@param offset number? # in beats
function seamstress.clock.sync(beat, offset) end

---ticks the midi clock
---@param bytes string
function seamstress.clock.midi(bytes) end
