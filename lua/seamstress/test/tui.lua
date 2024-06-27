local busted = require 'busted'

require 'seamstress.tui'

busted.describe(
  "seamstress.tui.Color",
  function()
    busted.it("has the default color", function()
      local col = seamstress.tui.Color()
      busted.assert.same(tostring(col), "color(default)")
    end)
    busted.it("has RGB colors", function()
      local col = seamstress.tui.Color(255, 150, 33)
      busted.assert.same(tostring(col), "color(r:0xff g:0x96 b:0x21)")
    end)
    busted.it("can be initialized by name", function()
      local col = seamstress.tui.Color("red")
      busted.assert.truthy(col)
      busted.assert.truthy(type(col) == 'userdata')
    end)
    busted.it("can be initialized with an RGB hex string", function()
      local col = seamstress.tui.Color("#aaeeff")
      busted.assert.same(tostring(col), "color(r:0xaa g:0xee b:0xff)")
    end)
    busted.it("can be queried", function()
      local a = seamstress.tui.Color(123, 56, 88)
      busted.assert.same(a.r, 123)
      busted.assert.same(a.g, 56)
      busted.assert.same(a.b, 88)
    end)
    busted.it("can be added", function()
      local default = seamstress.tui.Color()
      local white = seamstress.tui.Color('#ffffff')
      busted.assert.same(default + white, default)
      local a = seamstress.tui.Color(100, 0, 255)
      local b = seamstress.tui.Color(0, 33, 255)
      local c = seamstress.tui.Color(50, 16, 255)
      busted.assert.same(a + b, c)
    end)
    busted.it("can be negated", function()
      local default = seamstress.tui.Color()
      local white = seamstress.tui.Color('#ffffff')
      local black = seamstress.tui.Color('#000000')
      busted.assert.same(-default, default)
      busted.assert.same(-white, black)
    end)
    busted.it("can be subtracted", function()
      local default = seamstress.tui.Color()
      local a = seamstress.tui.Color('#beadee')
      local b = seamstress.tui.Color('#123456')
      local c = -b
      busted.assert.same(a - default, default)
      busted.assert.same(default - b, default)
      busted.assert.same(a - b, a + c)
    end)
    busted.it("can be multiplied", function()
      local default = seamstress.tui.Color()
      local a = seamstress.tui.Color('#abcdef')
      local b = seamstress.tui.Color('#012345')
      busted.assert.same(default * a, default)
      busted.assert.same(b * default, default)
      busted.assert.same(a * b, seamstress.tui.Color(
        math.floor(a.r * b.r / 255),
        math.floor(a.g * b.g / 255),
        math.floor(a.b * b.b / 255)
      ))
    end)
    busted.it("can be divided", function()
      local default = seamstress.tui.Color()
      local a = seamstress.tui.Color('#a24def')
      local b = seamstress.tui.Color('#0cd345')
      busted.assert.same(default / a, default)
      busted.assert.same(b / default, default)
      busted.assert.same(a / b, a * (-b))
    end)
  end)

busted.describe(
  "seamstress.tui",
  function()
    busted.before_each(function()
      seamstress.event.clear({ 'tui' })
    end)

    busted.after_each(function()
      seamstress.event.clear({ 'tui' })
      seamstress.update.running = false
      seamstress.update.delta = 1 / 60
    end)

    busted.it("can draw beautifully to the terminal",
      function()
        local done = false
        local t = 0
        local fg = seamstress.tui.Color('#ff8800')
        local logo = [[
███████╗███████╗ █████╗ ███╗   ███╗███████╗████████╗██████╗ ███████╗███████╗███████╗
██╔════╝██╔════╝██╔══██╗████╗ ████║██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔════╝██╔════╝
███████╗█████╗  ███████║██╔████╔██║███████╗   ██║   ██████╔╝█████╗  ███████╗███████╗
╚════██║██╔══╝  ██╔══██║██║╚██╔╝██║╚════██║   ██║   ██╔══██╗██╔══╝  ╚════██║╚════██║
███████║███████╗██║  ██║██║ ╚═╝ ██║███████║   ██║   ██║  ██║███████╗███████║███████║
╚══════╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝
]]
        seamstress.update.running = true
        seamstress.update.delta = 1 / 60
        seamstress.event.addSubscriber({ 'update' }, function(_, dt)
          t = t + dt
          fg = seamstress.tui.Color(math.abs(255 * math.cos(t)), math.abs(255 * math.sin(t + math.pi)),
            math.abs(255 * math.sin(t)))
          if t > 2 then
            done = true
          end
          return true, true
        end)
        local sub = seamstress.event.addSubscriber({ 'draw' }, function()
          local x = seamstress.tui.buffer.cols // 2
          local y = seamstress.tui.buffer.rows // 2
          seamstress.tui.buffer.write({ x - 43, -1 }, { y - 3, -1 }, logo, { fg = fg, wrap = "word" })
          return true
        end)
        repeat
          coroutine.yield()
        until done
        done = false
        sub:update({
          fn = function()
            seamstress.tui.buffer.set({ 1, -1 }, { 1, -1 })
            done = true
            return true, true
          end
        })
        repeat coroutine.yield() until done
      end)
    busted.it("can respond to key input",
      function()
        local done = false
        local dirty = true
        seamstress.event.addSubscriber({ 'tui', 'resize' }, function()
          dirty = true
          return true, dirty
        end)
        local sub = seamstress.event.addSubscriber({ 'draw' }, function()
          dirty = false
          local x = seamstress.tui.buffer.cols // 2
          local y = seamstress.tui.buffer.rows // 2
          seamstress.tui.buffer.write({ x - 10, -1 }, { y, -1 }, "press any key to continue")
          return true
        end)
        seamstress.event.publish { 'draw' }
        seamstress.event.addSubscriber({ 'tui', 'key_down' }, function()
          done = true
          sub:update({
            fn = function()
              seamstress.tui.buffer.set({ 1, -1 }, { 1, -1 })
              return true
            end
          })
          return true, true
        end)
        repeat
          coroutine.yield()
        until done
      end)

    busted.pending("higher level ui abstractions", function()
      busted.describe("ui", function()
        busted.it("has fully-featured buttons", function()
          local done = false
          seamstress.tui.ui.Button.new('click to continue',
            function() done = true end,
            { 'centered', 'centered' })
          repeat
            coroutine.yield()
          until done
        end)
      end)
    end)
  end)
