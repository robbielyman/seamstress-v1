-- returning a function allows us to get around Lua's prohibition on circular inputs
-- it also allows us to avoid having to make seamstress a global before `require('tui')` returns
return function(tui)
  local TextInput = {}

  TextInput.new = function(box)
    local e = tui.Entity.new(box)
    e.data = { tui.line("") }
    e.cursor = { x = 0, y = 1 }
    e.dirty = false
    e.key_down = {
      backspace = function()
        local x = e.cursor.x
        local y = e.cursor.y
        if x == 0 then
          if y == 1 then return end
          local line = e.data[y]
          table.remove(e.data, y)
          y = y - 1
          e.cursor.x = #(e.data[y])
          e.data[y] = e.data[y] .. line
          e.cursor.y = y
          return
        end
        e.data[y] = e.data[y]:sub(1, x - 1) .. e.data[y]:sub(x + 1)
        e.cursor.x = x - 1
      end,
      text = function(txt)
        local x = e.cursor.x
        local y = e.cursor.y
        local line = tui.line(txt)
        -- local b = e.data[y]
        e.data[y] = e.data[y] .. line
        e.cursor.x = x + #line
        e.dirty = true
      end,
      enter = function()
        local line = e.data[e.cursor.y]
        e.data[e.cursor.y] = line:sub(1, e.cursor.x)
        table.insert(e.data, e.cursor.y + 1, line:sub(e.cursor.x + 1))
        e.cursor.y = e.cursor.y + 1
        e.cursor.x = 0
        e.dirty = true
      end,
    }
    e.draw = function()
      -- if not e.dirty then return end
      tui.clearBox(e.hitbox)
      e.dirty = false
      tui.drawInBox(e.data, e.hitbox)
      if e.cursor_visible and e.focused then
        tui.showCursorInBox(e.cursor.x + 1, e.cursor.y, e.hitbox)
      end
    end
    local t = 0
    e.cursor_visible = true
    e.focused = true
    e.update = function(dt)
      t = t + dt
      if t > 0.7 then
        t = t % 0.7
        e.cursor_visible = not e.cursor_visible
        e.dirty = true
      end
    end
    e.resize = function() e.dirty = true end
    e:activate({ "key_down", "resize", "update", "draw" })
    e.clear = function()
      e.data = { tui.line("") }
      e.cursor.x = 0
      e.cursor.y = 1
      e.dirty = true
    end
    return e
  end


  return TextInput
end
