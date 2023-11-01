-- parameter map

--[[
  based on norns' pmap.lua
  norns pmap.lua first committed by @tehn March 19, 2020
  rewritten for seamstress by @dndrks Aug 15, 2023
]]

local pmap = {
  data = {},
  rev = {},
}

pmap.__index = pmap

function pmap.new(id)
  local p = params:lookup_param(id)
  p.midi_mapping = {
    in_lo = 0,
    in_hi = 127,
    out_lo = 0,
    out_hi = 1,
    accum = false,
    echo = false,
    value = 0,
  }
  pmap.data[id] = p.midi_mapping
end

function pmap.remove(id)
  local p = params:lookup_param(id)
  if p.midi_mapping.dev ~= nil then
    local to_remove = tab.key(pmap.rev[p.midi_mapping.dev][p.midi_mapping.ch][p.midi_mapping.cc], p.id)
    table.remove(pmap.rev[p.midi_mapping.dev][p.midi_mapping.ch][p.midi_mapping.cc], to_remove)
    pmap.data[p.id] = nil
    p.midi_mapping.dev = nil
    p.midi_mapping.ch = nil
    p.midi_mapping.cc = nil
    pmap.write()
  end
end

function pmap.assign(id, dev, ch, cc)
  local p = params:lookup_param(id)
  p.midi_mapping.dev = dev
  p.midi_mapping.ch = ch
  p.midi_mapping.cc = cc
  table.insert(pmap.rev[dev][ch][cc], id)
  pmap.write()
end

function pmap.refresh()
  for k, v in pairs(pmap.data) do
    if params.lookup[k] ~= nil then
      table.insert(pmap.rev[v.dev][v.ch][v.cc], k)
      local p = params:lookup_param(k)
      for item, val in pairs(v) do
        p.midi_mapping[item] = val
      end
      local midi_prm = pmap.data[k]
      if v.echo then
        local val
        if p.t == params.tCONTROL then
          val = params:get_raw(k)
        else
          val = params:get(k)
        end
        midi_prm.value = util.round(util.linlin(midi_prm.out_lo, midi_prm.out_hi, midi_prm.in_lo, midi_prm.in_hi, val))
        if midi_prm.echo then
          local port = pmap.data[k].dev
          midi.vports[port]:cc(midi_prm.cc, midi_prm.value, midi_prm.ch)
        end
      end
    end
  end
end

function pmap.clear()
  pmap.data = {}
  pmap.rev = {}
  -- build reverse lookup table: dev -> ch -> cc
  for dev = 1, 16 do
    pmap.rev[dev] = {}
    for ch = 1, 16 do
      pmap.rev[dev][ch] = {}
      for cc = 0, 127 do
        pmap.rev[dev][ch][cc] = {}
      end
    end
  end
end

function pmap.write()
  local filepath = path.seamstress .. "/data/" .. seamstress.state.name
  util.make_dir(filepath)
  local function quote(s)
    return '"' .. s:gsub('"', '\\"') .. '"'
  end
  local filename = filepath .. "/" .. seamstress.state.name .. ".pmap"
  print(">> saving PMAP " .. filename)
  local fd = io.open(filename, "w+")
  io.output(fd)
  local line = ""
  for k, v in pairs(pmap.data) do
    line = string.format('%s:"{', quote(tostring(k)))
    for x, y in pairs(v) do
      line = line .. x .. "=" .. tostring(y) .. ", "
    end
    line = line:sub(1, -3) .. '}"\n'
    io.write(line)
    line = ""
  end
  io.close(fd)
end

function pmap.read()
  -- prevent weird crash in case we didn't find a script
  if seamstress.state.name == nil then
    return
  end
  local function unquote(s)
    return s:gsub('^"', ""):gsub('"$', ""):gsub('\\"', '"')
  end
  local filepath = path.seamstress .. "/data/" .. seamstress.state.name
  local filename = filepath .. "/" .. seamstress.state.name .. ".pmap"
  local fd = io.open(filename, "r")
  print(">> searching for MIDI mapping: " .. filename)
  if fd then
    io.close(fd)
    for line in io.lines(filename) do
      local name, value = string.match(line, '(".-")%s*:%s*(.*)')
      if name and value and tonumber(value) == nil then
        local x = load("return " .. unquote(value))
        pmap.data[unquote(name)] = x()
      end
    end
    print(">> MIDI mapping file found, loaded!")
    pmap.refresh()
  else
    print(">> MIDI mapping file not present, using defaults")
  end
end

function pmap.delete()
  local filepath = path.seamstress .. "/data/" .. seamstress.state.name
  local filename = filepath .. "/" .. seamstress.state.name .. ".pmap"
  os.execute("rm " .. filename)
  print(">> MIDI mapping file deleted: " .. filename)
end

pmap.clear()

return pmap
