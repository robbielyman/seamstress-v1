--- helper module for translating SDL keycodes
-- @module keycodes

local key = {}
key.__index = function(t, index)
  if t == key then
    if type(index) == "number" then
      if index >= 0 and index <= 255 then
        return string.char(index)
      end
    end
    return nil
  end
end
setmetatable(key, key)

local function n(name)
  return { name = name }
end

key[8] = n("backspace")
key[9] = n("tab")
key[13] = n("return")
key[27] = n("escape")
key[0x40000039] = n("capslock")
key[0x4000003a] = n("F1")
key[0x4000003b] = n("F2")
key[0x4000003c] = n("F3")
key[0x4000003d] = n("F4")
key[0x4000003e] = n("F5")
key[0x4000003f] = n("F6")
key[0x40000040] = n("F7")
key[0x40000041] = n("F8")
key[0x40000042] = n("F9")
key[0x40000043] = n("F10")
key[0x40000044] = n("F11")
key[0x40000045] = n("F12")
key[0x4000004F] = n("right")
key[0x40000050] = n("left")
key[0x40000051] = n("down")
key[0x40000052] = n("up")
key[0x400000e0] = n("lctrl")
key[0x400000e1] = n("lshift")
key[0x400000e2] = n("lalt")
key[0x400000e3] = n("lsuper")
key[0x400000e4] = n("rctrl")
key[0x400000e5] = n("rshift")
key[0x400000e6] = n("ralt")
key[0x400000e7] = n("rsuper")

function key.modifier(mask)
  local ret = {}
  if mask & 3 > 0 then
    table.insert(ret, "shift")
  end
  if mask & (3 << 6) > 0 then
    table.insert(ret, "ctrl")
  end
  if mask & (3 << 8) > 0 then
    table.insert(ret, "alt")
  end
  if mask & (3 << 10) > 0 then
    table.insert(ret, "super")
  end
  if mask & (1 << 13) > 0 then
    table.insert(ret, "capslock")
  end
  if mask & (1 << 14) > 0 then
    table.insert(ret, "altgr")
  end
  return ret
end

-- TODO: this is only QWERTY
key.shifted = {
  ['`'] = '~',
  ['1'] = '!',
  ['2'] = '@',
  ['3'] = '#',
  ['4'] = '$',
  ['5'] = '%',
  ['6'] = '^',
  ['7'] = '&',
  ['8'] = '*',
  ['9'] = '(',
  ['0'] = ')',
  ['-'] = '_',
  ['='] = '+',
  ['['] = '{',
  [']'] = '}',
  ['\\'] = '|',
  [';'] = ':',
  ['\''] = '"',
  [','] = '<',
  ['.'] = '>',
  ['/'] = '?',
  ['a'] = 'A',
  ['b'] = 'B',
  ['c'] = 'C',
  ['d'] = 'D',
  ['e'] = 'E',
  ['f'] = 'F',
  ['g'] = 'G',
  ['h'] = 'H',
  ['i'] = 'I',
  ['j'] = 'J',
  ['k'] = 'K',
  ['l'] = 'L',
  ['m'] = 'M',
  ['n'] = 'N',
  ['o'] = 'O',
  ['p'] = 'P',
  ['q'] = 'Q',
  ['r'] = 'R',
  ['s'] = 'S',
  ['t'] = 'T',
  ['u'] = 'U',
  ['v'] = 'V',
  ['w'] = 'X',
  ['x'] = 'W',
  ['y'] = 'Y',
  ['z'] = 'Z',
}

return key
