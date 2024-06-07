-- returning a function allows us to get around Lua's prohibition on circular inputs
-- it also allows us to avoid having to make seamstress a global before `require('tui')` returns
return function(tui)
  local FixedBox = {}

  FixedBox.new = function(data, box)
    local e = tui.Entity.new(box)
    e.data = data
    e.dirty = false
    e.draw = function()
      if not e.dirty then return end
      tui.clearBox(e.hitbox)
      e.dirty = false
      tui.drawInBox(e.data, e.hitbox)
      -- tui.drawInBox({ table.unpack(e.data, e.hitbox.y[2] - e.hitbox.y[1] + 1) }, e.hitbox)
    end
    e:activate({ "draw" })
    e.move = function(x, y)
      tui.clearBox(e.hitbox)
      e.hitbox.x[1] = e.hitbox.x[1] + x
      e.hitbox.x[2] = e.hitbox.x[2] + x
      e.hitbox.y[1] = e.hitbox.y[1] + y
      e.hitbox.y[2] = e.hitbox.y[2] + y
      e.dirty = true
    end
    return e
  end

  return FixedBox
end
