-- params menu

--[[
  based on norns' params menu
  norns params menu first committed by @artfwo April 8, 2018
  reimagined for seamstress by @dndrks June 26, 2023
]]

local mEDIT = 1
local mMAP = 2

local m = {
  pos = 0,
  oldpos = 0,
  group = false,
  groupid = 0,
  alt = false,
  mode = mEDIT,
  mode_pos = 1,
  map = false,
  midi_learn = { pos = 0, state = false },
  dev = 1,
  ch = 1,
  cc = 100,
  pm,
  ps_pos = 0,
  ps_n = 0,
  ps_action = 1,
  ps_last = 0,
  dir_prev = nil,
  highlightColors = { r = 0, g = 140, b = 140 },
}

local page
local pset = {}

-- called from menu on script reset
m.reset = function()
  page = nil
  m.pos = 0
  m.group = false
  m.ps_pos = 0
  m.ps_n = 0
  m.ps_action = 1
  m.mode = mEDIT
end

local function build_page()
  page = {}
  local i = 1
  repeat
    if params:visible(i) then
      table.insert(page, i)
    end
    if params:t(i) == params.tGROUP then
      i = i + params:get(i) + 1
    else
      i = i + 1
    end
  until i > params.count
end

local function build_sub(sub)
  page = {}
  for i = 1, params:get(sub) do
    if params:visible(i + sub) then
      table.insert(page, i + sub)
    end
  end
end

m.key = function(char, modifiers, is_repeat, state)
  -- encapsulates both encoder + key interactions from norns...
  if #modifiers == 1 and modifiers[1] == "shift" and char == "m" and state == 1 then
    m.mode = m.mode == mEDIT and mMAP or mEDIT
    if m.group then
      build_sub(m.groupid)
    else
      build_page()
    end
  end

  if m.mode == mEDIT or m.mode == mMAP then
    local i = page[m.pos + 1]
    local t = params:t(i)
    if (char.name == "up" or char.name == "down") and state == 1 then
      if tab.contains(modifiers, "alt") then
        -- jump
        local d = char.name == "up" and -1 or 1
        local i = m.pos + 1
        repeat
          i = i + d
          if i > #page then
            i = 1
          end
          if i < 1 then
            i = #page
          end
        until params:t(page[i]) == params.tSEPARATOR or i == 1
        m.pos = i - 1
        m.midi_learn.pos = m.pos
      else
        -- delta 1
        local d = char.name == "up" and -1 or 1
        local prev = m.pos
        m.pos = util.clamp(m.pos + d, 0, #page - 1)
        m.midi_learn.pos = m.pos
        m.midi_learn.state = false
        if m.pos ~= prev then
          m.redraw()
        end
      end
    elseif (char.name == "right" or char.name == "left") and state == 1 then
      -- adjust value
      if params.count > 0 then
        local d = char.name == "left" and -1 or 1
        local dx = m.fine and (d / 20) or (m.coarse and d * 10 or d)
        params:delta(page[m.pos + 1], dx)
      end
    elseif char.name == "return" then
      if state == 1 then
        -- enter group
        if t == params.tGROUP then
          build_sub(i)
          m.group = true
          m.groupid = i
          m.groupname = params:string(i)
          m.oldpos = m.pos
          m.pos = 0
        -- jump separator
        elseif t == params.tSEPARATOR then
          local n = m.pos + 1
          repeat
            n = n + 1
            if n > #page then
              n = 1
            end
          until params:t(page[n]) == params.tSEPARATOR
          m.pos = n - 1
        -- midi learn
        elseif m.mode == mMAP and params:get_allow_pmap(i) then
          local n = params:get_id(i)
          local pm = params:lookup_param(n).midi_mapping

          m.midi_learn.pos = m.pos
          if pm.dev == nil then
            m.midi_learn.state = not m.midi_learn.state
            if m.midi_learn.state then
              pmap.new(n)
              pm = params:lookup_param(n).midi_mapping
            end
          else
            m.midi_learn.state = false
          end
        end
      end
    elseif char.name == "rshift" then
      m.fine = state == 1
    elseif char.name == "ralt" then
      m.coarse = state == 1
    elseif char.name == "backspace" then
      if tab.contains(modifiers, "shift") and state == 1 then
        if m.mode == mMAP then
          pmap.remove(i)
        end
      elseif state == 1 then
        if m.group == true then
          m.group = false
          build_page()
          m.pos = m.oldpos
        end
      end
    end
  end
  m.redraw()
end

m.newtext = function(txt)
  if txt ~= "cancel" then
    params:set(page[m.pos + 1], txt)
    m.redraw()
  end
end

m.redraw = function()
  _seamstress.screen_set(2)
  screen.clear()

  if m.mode == mEDIT then
    local n = "PARAMETERS"
    if m.group then
      n = n .. " / " .. m.groupname
    end
    screen.color(130, 140, 140, 255)
    screen.move(10, 10)
    screen.text(n)
    screen.move_rel(0, 20)
    for i = 1, 20 do
      if (i > 1 - m.pos) and (i < #page - m.pos + 2) then
        if i == 2 then
          screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b, 255)
        else
          screen.color(130, 140, 140, 255)
        end
        local p = page[i + m.pos - 1]
        local t = params:t(p)
        screen.move_rel(0, 10)
        if t == params.tSEPARATOR then
          screen.text(params:get_name(p))
          screen.move_rel(0, 8)
          screen.line_rel(127, 0)
          screen.move_rel(0, -8)
        elseif t == params.tGROUP then
          screen.text(params:get_name(p) .. " >")
        else
          screen.text(params:get_name(p))
          screen.move_rel(127, 0)
          screen.text_right(params:string(p, params:is_number(p) and 1 or 0.001))
          screen.move_rel(-127, 0)
        end
      end
    end
  elseif m.mode == mMAP then
    local n = "PARAMETERS: MAPPING"
    if m.group then
      n = n .. " / " .. m.groupname
    end
    screen.color(130, 140, 140, 255)
    screen.move(10, 10)
    screen.text(n)
    screen.move_rel(0, 20)
    for i = 1, 20 do
      if (i > 1 - m.pos) and (i < #page - m.pos + 2) then
        if i == 2 then
          screen.color(m.highlightColors.r, m.highlightColors.g, m.highlightColors.b)
        else
          screen.color(130, 140, 140, 255)
        end
        local p = page[i + m.pos - 1]
        local t = params:t(p)
        local n = params:get_name(p)
        local id = params:get_id(p)
        screen.move_rel(0, 10)
        if t == params.tSEPARATOR then
          screen.text(n)
          screen.move_rel(0, 8)
          screen.line_rel(127, 0)
          screen.move_rel(0, -8)
        elseif t == params.tGROUP then
          screen.text(n .. " >")
        else
          screen.text(id)
          screen.move_rel(127, 0)
          if params:get_allow_pmap(id) then
            local pm = params:lookup_param(id).midi_mapping
            if pm.dev then
              screen.text_right("CC:" .. pm.cc .. " | CH:" .. pm.ch .. " | DEV:" .. pm.dev)
            elseif m.midi_learn.state and i == 2 then
              screen.text_right("[learning]")
            else
              screen.text_right("-")
            end
          end
          screen.move_rel(-127, 0)
        end
      end
    end
  end

  screen.refresh()
  _seamstress.screen_set(1)
end

m.menu_midi_event = function(data, dev)
  if data.type == "cc" then
    local ch = data.ch
    local cc = data.cc
    local v = data.val
    if m.midi_learn.state then
      m.midi_learn.state = false
      m.dev = dev
      m.ch = ch
      m.cc = cc
      local p = page[m.pos + 1]
      local id = params:get_id(p)
      pmap.assign(id, m.dev, m.ch, m.cc)
      m.redraw()
    else
      local r = pmap.rev[dev][ch][cc]
      for param_target = 1, #r do
        local d = r[param_target]
        local prm_id = d
        d = params:lookup_param(prm_id).midi_mapping
        local t = params:t(prm_id)
        if d.accum then
          v = (v > 64) and 1 or -1
          d.value = util.clamp(d.value + v, d.in_lo, d.in_hi)
          v = d.value
        end
        local s = util.clamp(v, d.in_lo, d.in_hi)
        s = util.linlin(d.in_lo, d.in_hi, d.out_lo, d.out_hi, s)
        if t == params.tCONTROL or t == params.tTAPER then
          params:set_raw(prm_id, s)
        elseif t == params.tNUMBER or t == params.tOPTION then
          s = util.round(s)
          params:set(prm_id, s)
        elseif t == params.tBINARY then
          params:delta(prm_id, s)
          for i, param in ipairs(params.params) do
            if params:lookup_param(i).behavior == params:lookup_param(prm_id).behavior then
              if params:lookup_param(i).behavior == "trigger" then
                m.triggered[i] = 2
              else
                m.on[i] = params:get(i)
              end
            end
          end
        end
      end
      m.redraw()
    end
  end
end

m.init = function()
  if page == nil then
    build_page()
  end
  m.alt = false
  m.fine = false
  m.coarse = false
  m.redraw()
end

m.deinit = function() end

m.rebuild_params = function()
  if m.mode == mEDIT then
    if m.group then
      build_sub(m.groupid)
    else
      build_page()
    end
    m.redraw()
  end
end

m.mouse = function(x, y) end

m.click = function(x, y, state, button) end

return m
