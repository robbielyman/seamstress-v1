-- returning a function allows us to get around Lua's prohibition on circular inputs
-- it also allows us to avoid having to make seamstress a before `require('tui')` returns
return function(tui)
  local Entity = {}
  Entity.__index = Entity

  local events = {
    "hover",
    "mouse_down",
    "mouse_up",
    "key_down",
    "key_up",
    "update",
    "draw",
    "focus_lost",
    "window_focus",
    "resize",
    "scroll",
  }

  _seamstress.tui.entities = {}

  for _, event in ipairs(events) do
    _seamstress.tui.entities[event] = {}
    if event ~= "key_down" and event ~= "key_up" then
      _seamstress.tui[event] = function(...)
        for _, entity_key in ipairs(_seamstress.tui.entities[event]) do
          _seamstress.tui.entities[entity_key][event](...)
        end
        if tui[event] then tui[event](...) end
      end
    else
      _seamstress.tui[event] = function(key, ...)
        for _, entity_key in ipairs(_seamstress.tui.entities[event]) do
          local entity = _seamstress.tui.entities[entity_key]
          if entity then
            if type(entity[event]) == "table" then
              if entity[event][key] then entity[event][key](...) end
            else
              entity[event](key, ...)
            end
          end
        end
        if type(tui[event]) == "table" then
          if tui[event][key] then tui[event][key](...) end
        else
          tui[event](key, ...)
        end
      end
    end
  end

  local id = 1

  function Entity.new(hitbox)
    hitbox = hitbox or { x = { 1, -1 }, y = { 1, -1 } }
    local e = setmetatable({ id = id, hitbox = hitbox }, Entity)
    _seamstress.tui.entities[id] = e
    id = id + 1
    return e
  end

  function Entity:captureFocus()
    for _, entity in ipairs(_seamstress.tui.entities.focus_lost) do
      if entity ~= self.id and _seamstress.tui.entities[entity].focus_lost then
        _seamstress.tui.entities[entity].focus_lost()
      end
    end
  end

  function Entity:deactivate(which)
    which = which or "all"
    if which == "all" then
      for _, key in ipairs(events) do
        for index, value in ipairs(_seamstress.tui.entities[key]) do
          if value == self.id then
            table.remove(_seamstress.tui.entities[key], index)
            break
          end
        end
      end
    elseif type(which) == "string" and _seamstress.tui.entities[which] then
      for index, value in ipairs(_seamstress.tui.entities[which]) do
        if value == self.id then
          table.remove(_seamstress.tui.entities[which], index)
          break
        end
      end
    end
  end

  function Entity:activate(which)
    if type(which) == "string" and _seamstress.tui.entities[which] then
      for _, value in ipairs(_seamstress.tui.entities[which]) do
        if value == self.id then return end
      end
      table.insert(_seamstress.tui.entities[which], self.id)
    elseif type(which) == "table" then
      for _, key in ipairs(which) do
        for _, value in ipairs(_seamstress.tui.entities[key]) do
          if value == self.id then goto continue end
        end
        table.insert(_seamstress.tui.entities[key], self.id)
        ::continue::
      end
    end
  end

  function Entity:reactivate(on, which)
    if type(which) == "string" and _seamstress.tui.entities[which] then
      if on == "hover" then
        self.hover = function(x, y)
          self:deactivate("hover")
          self:activate(which)
        end
        self:activate("hover")
      elseif on == "mouse_down" then
        self.mouse_down = function(x, y)
          self:deactivate("mouse_down")
          self:activate(which)
        end
        self:activate("mouse_down")
      end
    end
  end

  return Entity
end
