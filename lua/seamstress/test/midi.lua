local busted = require 'busted'

busted.describe('seamstress.midi', function()
  busted.it('can encode and decode messages', function()
    local note_on = { 'note_on', 16, 60, 127 }
    local note_off = { 'note_off', 16, 60, 33 }
    local clock = { 'clock' }
    local str = seamstress.midi.encode(clock)
    local msgs = { clock, note_on, note_off }
    local longstr = seamstress.midi.encodeAll(msgs)
    busted.assert.same(longstr:byte(1), str:byte(1))
    local tbl = {}
    for msg in seamstress.midi.messages(longstr) do table.insert(tbl, msg) end
    busted.assert.same(tbl, msgs)
  end)

  busted.it('can send and receive from inputs and outputs', function()
    local ports = seamstress.midi.list
    if #ports.inputs > 0 and #ports.outputs > 0 then
      seamstress.midi.connectInput(ports.inputs[1])
      seamstress.midi.disconnectInput(ports.inputs[1])
      seamstress.midi.connectOutput(ports.outputs[1])
    end
    local done = true
    for _, v in ipairs(ports.inputs) do
      if v:find('IAC') then
        done = false
        seamstress.midi.connectInput(v)
        seamstress.event.addSubscriber({ 'midi', 'control_change' }, function(_, _, chan, cc, val)
          if chan == 4 and cc == 78 and val == 33 then done = true end
          return true
        end)
        local out = seamstress.midi.connectOutput(v)
        busted.assert.truthy(out)
        ---@cast out -nil
        out.send({ 'control_change', 4, 78, 33 })
        repeat coroutine.yield() until done
      end
    end
  end)

  busted.it('can really play', function()
    local out = seamstress.midi.connectOutput('from seamstress 1')
    local state = false
    local note = 60

    local t = seamstress.Timer(function()
      if state then
        out.send({ 'note_off', 1, note, 80 })
      else
        note = math.random(50, 70)
        out.send({ 'note_on', 1, note, math.random(1, 127) })
      end
      state = not state
    end, 0.08, 24)

    repeat coroutine.yield() until t.running == false
  end)
end)
