return setmetatable({}, {
  __call = function(self, f)
    return function(...)
      local arg = { ... }
      return seamstress.async.Promise(function()
          return f(table.unpack(arg))
      end)
    end
  end
})
