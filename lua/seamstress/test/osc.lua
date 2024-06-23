local busted = require 'busted'

_ = seamstress.osc

busted.describe('seamstress.osc', function()
  busted.it('can receive messages', function()
    local done = false
    seamstress.event.addSubscriber({ 'osc', 'paths', 'are', 'chunked' }, function(info, ...)
      local arg = { ... }
      busted.assert.same('/paths/are/chunked', info[1])
      busted.assert.same('ihfdsS', info.types)
      busted.assert.same(1, arg[1])
      busted.assert.same(2000, arg[2])
      busted.assert(math.abs(3.14 - arg[3]) < 0.0001)
      busted.assert.same(1.00, arg[4])
      busted.assert.same('test', arg[5])
      busted.assert.same('arg', arg[6])
      done = true
      return true
    end)
    if os.execute('oscsend localhost ' ..
          seamstress.osc.local_port .. ' /paths/are/chunked ihfdsS 1 2000 3.14 1.00 test arg')
        == nil then
      done = true
    end
    repeat
      coroutine.yield()
    until done
  end)

  busted.it('can send messages', function()
    local done = false
    seamstress.osc.patternedHandler('/this/*/osc', function(info, ...)
      local arg = { ... }
      busted.assert.same('/this/is/some/osc', info[1])
      busted.assert.same('sih', info.types)
      busted.assert.same("hi", arg[1])
      busted.assert.same(13, arg[2])
      busted.assert.same(69, arg[3])
      done = true
      return true
    end)
    seamstress.osc.send(seamstress.osc.local_port, { '/this/is/some/osc', 'sih' }, "hi", 13, 69)
    repeat coroutine.yield() until done
  end)
end)
