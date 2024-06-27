---@class seamstress.osc
---@field local_port integer
local osc = {}

---registers a pattern-matching OSC event handler
---if you don't need pattern matching,
---OSC events /like/this will be announced at {'osc', 'like', 'this'} by default
---@param pattern string
---@param f fun(path: {[1]:string, from: [string, string], types: string}, ...): boolean
---@return Subscriber
function osc.patternedHandler(pattern, f)
  return seamstress.event.addSubscriber({ 'osc' }, f, {
    predicate = function(_, path)
      return seamstress.osc.match(pattern, path[1])
    end,
  })
end

return { osc, true }
