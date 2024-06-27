---@meta

---@module 'seamstress.async'

---creates an asynchronous function
---@class seamstress.async
---@overload fun(f: fun(...): any?): (fun(...): Promise)
seamstress.async = {}

---@class Promise
---@overload fun(f: fun(...): any?): Promise
local Promise = {}

seamstress.async.Promise = Promise

---must be called from an async context (e.g. a Promise or a coroutine)
---the following code snippets are equivalent; both will print "the number is 25".
---```lua
---local a = seamstress.async(function(x) return x + 12 end)
---local b = seamstress.async.Promise(function()
---  a(13):anon(function(x) print('the number is ' .. x) end)
---end)
---local c = seamstress.async.Promise(function()
---  local x = a(13):await()
---  print('the number is ' .. x)
---end)
---```
---@return any? # the return values of the Promise's function, or an error if the Promise was rejected
function Promise:await() end

---registers functions to be called when the Promise is settled
---the name is chosen for expressions like "I shall return anon":
---in JavaScript the same functionality is provided by a function named "then",
---which is a reserved word in Lua.
---Values (or errors) returned by the Promise's body are passed as arguments
---to the appropriate function.
---@param resolve fun(...): any? called if self is fulfilled
---@param reject (fun(err: string, ...): any?)? called if self is rejected
---@return Promise # a new promise which is fulfilled upon sucessful completion of either handler
function Promise:anon(resolve, reject) end

---equivalent to Promise:anon(function(...) return ... end, reject)
---@param reject fun(err: string, ...): any? called if self is rejected
---@return Promise
function Promise:catch(reject) end

---equivalent to Promise:anon(anyhow, anyhow)
---@param anyhow fun(...): any? called when self is settled
---@return Promise
function Promise:finally(anyhow) end

---creates a new Promise which fulfills when all of its arguments fulfill.
---the Promise rejects if any of its arguments reject.
---@param ... Promise[]
---@return Promise
function Promise.all(...) end

---creates a new Promise which fulfills when any of its arguments fulfill.
---the Promise rejects if all of its arguments reject.
---@param ... Promise[]
---@return Promise
function Promise.any(...) end

---creates a new Promise which settles when any of its arguments settle.
---@param ... Promise[]
---@return Promise
function Promise.race(...) end

