-- returning a function allows us to get around Lua's prohibition on circular inputs
-- it also allows us to avoid having to make seamstress a global before `require('tui')` returns
return function(tui)
  local ScrollBox = {}
  ScrollBox.__index = ScrollBox

  ScrollBox.new = function(data, box)
    local e = tui.Entity.new(box)
    e.data = data
    e.cursor = { x = 0, y = 1 }
    e.dirty = false
    e.draw = function()
      if not e.dirty then return end
      tui.clearBox(e.hitbox)
      e.dirty = false
      tui.drawInBox(e.data, e.hitbox)
    end
    e.resize = function() e.dirty = true end
    e:activate({ "resize", "draw" })
    return e
  end

  return ScrollBox
end
