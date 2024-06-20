---@alias callback (fun(...): boolean, any?)

---creates a subscriber
---@param fn callback
---@param options table?
---@return Subscriber
local function Subscriber(fn, options)
  ---@class Subscriber
  ---@field options table
  ---@field fn callback # callback
  ---@field channel Channel?
  ---@field id number # the memory address of this table, so guaranteed to be unique
  ---@field update fun(self: Subscriber, opt: {predicate: (fun(...): boolean)?}?)
  local sub = {
    options = options or {},
    fn = fn or function() return true end,
    channel = nil,
    ---updates this subscriber
    ---@param self Subscriber
    ---@param opt {fn: callback?, options: {predicate: (fun(...): boolean)?}}?
    update = function(self, opt)
      if opt then
        self.fn = opt.fn or self.fn
        self.options = opt.options or self.options
      end
    end
  }
  sub.id = tonumber(tostring(sub):match(':%s*[0xX]*(%x+)'), 16)
  return sub
end

---creates a channel
---@param name string
---@param parent Channel?
---@return Channel
local function Channel(name, parent)
  ---@class Channel
  ---@field name string
  ---@field callbacks Subscriber[]
  ---@field channels {[string]: Channel}
  ---@field parent Channel?
  ---@field addSubscriber fun(self: Channel, fn: callback, options: table?): Subscriber
  ---@field getSubscriber fun(self: Channel, id: integer): {index: integer, value: Subscriber}?
  ---@field removeSubscriber fun(self: Channel, id: integer): Subscriber?
  ---@field setPriority fun(self: Channel, id: integer, priority: integer)
  ---@field add fun(self: Channel, namespace: string): Channel
  ---@field has fun(self: Channel, namespace: string): boolean
  ---@field get fun(self: Channel, namespace: string): Channel
  ---@field publish fun(self: Channel, ret: any[], ...): any[]
  return {
    name = name,
    callbacks = {},
    channels = {},
    parent = parent,
    ---adds a subscriber to this channel
    ---@param self Channel
    ---@param fn callback
    ---@param options table?
    ---@return Subscriber
    addSubscriber = function(self, fn, options)
      local callback = Subscriber(fn, options)
      local priority = #self.callbacks + 1
      options = options or {}

      if options.priority and options.priority >= 0 and options.priority < priority then
        priority = options.priority
      end

      if priority > 0 then
        table.insert(self.callbacks, priority, callback)
      else
        local old = self.callbacks[0]
        self.callbacks[0] = callback
        table.insert(self.callbacks, old)
      end
      return callback
    end,
    ---gets a subscriber handle from an id
    ---@param self Channel
    ---@param id integer # hash found in the Subscriber.id field
    ---@return { index: integer, value: Subscriber }? # nil if the subscriber was not found
    getSubscriber = function(self, id)
      for i, callback in ipairs(self.callbacks) do
        if callback.id == id then return { index = i, value = callback } end
      end
      local sub
      for _, channel in pairs(self.channels) do
        sub = channel:getSubscriber(id)
        if sub then break end
      end
      return sub
    end,
    ---removes a subscriber
    ---@param self Channel
    ---@param id integer # hash found in the Subscriber.id field
    ---@return Subscriber?
    removeSubscriber = function(self, id)
      local cb = self:getSubscriber(id)
      if cb and cb.value then
        for _, channel in pairs(self.channels) do
          channel:removeSubscriber(id)
        end
        return table.remove(self.callbacks, cb.index)
      end
    end,
    ---sets callback priority
    ---@param self Channel
    ---@param id integer # hash found in the Subscribe.id field
    ---@param priority integer
    setPriority = function(self, id, priority)
      local cb = self:getSubscriber(id)
      local p = #self.callbacks
      if priority < 0 or priority > p then priority = p end
      if cb and cb.value then
        if cb.index == 0 then
          self.callbacks[0] = nil
        else
          table.remove(self.callbacks, cb.index)
        end
        if priority ~= 0 then
          table.insert(self.callbacks, priority, cb.value)
        else
          self.callbacks[0] = cb.value
        end
      end
    end,
    ---adds a Channel
    ---@param self Channel
    ---@param namespace string
    ---@return Channel
    add = function(self, namespace)
      self.channels[namespace] = Channel(namespace, self)
      return self.channels[namespace]
    end,
    ---true if Channel with that namespace exists
    ---@param self Channel
    ---@param namespace string
    ---@return boolean
    has = function(self, namespace)
      return namespace and self.channels[namespace] and true
    end,
    ---returns or adds a Channel at the given namespace
    ---@param self Channel
    ---@param namespace string
    ---@return Channel
    get = function(self, namespace)
      return self.channels[namespace] or self:add(namespace)
    end,
    ---responds to event by sequentially firing callbacks according to their priority
    ---@param self Channel
    ---@param ret any[] # the array of responses
    ---@param ... unknown # arguments passed to callbacks
    ---@return any[] # ret plus any responses from callbacks
    publish = function(self, ret, ...)
      for _, cb in ipairs(self.callbacks) do
        if not cb.options.predicate or cb.options.predicate(...) then
          local continue, response = cb.fn(...)
          table.insert(ret, response)
          if not continue then return ret end
        end
      end
      if self.callbacks[0] then
        if not self.callbacks[0].predicate or self.callbacks[0].predicate(...) then
          local continue, response = self.callbacks[0].fn(...)
          table.insert(ret, response)
          if not continue then return ret end
        end
      end
      if parent then
        return parent:publish(ret, ...)
      end
      return ret
    end,
  }
end

---singleton event pub/sub handler
---@class seamstress.event
---@field channel Channel
local event = {
  channel = Channel('root'),
}

---gets a Channel
---@param namespace string[]
---@return Channel
function event.get(namespace)
  local channel = event.channel
  for _, value in ipairs(namespace) do
    channel = channel:get(value)
  end
  return channel
end

---adds a handler function to the given namespace
---@param namespace string[]
---@param fn callback
---@param options {predicate: (fun(...): boolean)?}?
---@return Subscriber
function event.addSubscriber(namespace, fn, options)
  return event.get(namespace):addSubscriber(fn, options)
end

---returns a Subscriber
---@param id integer # hash value at Subscriber.id
---@param namespace string[]
---@return Subscriber?
function event.getSubscriber(id, namespace)
  local ret = event.get(namespace):getSubscriber(id)
  if ret and ret.value then return ret.value end
end

---removes a subscriber from the given namespace
---@param id integer # hash value at Subscriber.id
---@param namespace string[]
---@return Subscriber? # the subscriber, if found
function event.removeSubscriber(id, namespace)
  return event.get(namespace):removeSubscriber(id)
end

---fires the callbacks present in namespace and its parents
---@param namespace string[]
---@param ... unknown args passed to callbacks
---@return any[] the aggregate responses of responders
function event.publish(namespace, ...)
  local ret = {}
  event.get(namespace):publish(ret, ...)
  return ret
end

---clears a channel and all of its children
---@param namespace string[]
function event.clear(namespace)
  local channel = event.get(namespace)
  channel.callbacks = {}
  channel.channels = {}
end

return event
