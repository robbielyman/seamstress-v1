--- random utils
-- @module util
local Util = {}

--- check whether a file exists
-- @tparam string name filename
-- @treturn bool true if the file exists
-- @function util.exists
function Util.exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

--- clamp values to min max.
-- @tparam number n value
-- @tparam number min minimum
-- @tparam number max maximum
-- @treturn number clamped value
function Util.clamp(n, min, max)
  return math.min(max, (math.max(n, min)))
end

-- linlin, linexp, explin, expexp ripped from SC source code
-- https://github.com/supercollider/supercollider/blob/cca12ff02a774a9ea212e8883551d3565bb24a6f/lang/LangSource/MiscInlineMath.h

--- convert a linear range to an exponential range
-- @tparam number slo lower limit of input range
-- @tparam number shi upper limit of input range
-- @tparam number dlo lower limit of output range (must be non-zero and of the same sign as dhi)
-- @tparam number dhi upper limit of output range (must be non-zero and of the same sign as dlo)
-- @tparam number f input to convert
-- @treturn number
function Util.linexp(slo, shi, dlo, dhi, f)
  if f <= slo then
    return dlo
  elseif f >= shi then
    return dhi
  else
    return ((dhi / dlo) ^ ((f - slo) / (shi - slo))) * dlo
  end
end

--- map a linear range to another linear range.
-- @tparam number slo lower limit of input range
-- @tparam number shi upper limit of input range
-- @tparam number dlo lower limit of output range
-- @tparam number dhi upper limit of output range
-- @tparam number f input to convert
-- @treturn number
function Util.linlin(slo, shi, dlo, dhi, f)
  if f <= slo then
    return dlo
  elseif f >= shi then
    return dhi
  else
    return (f - slo) / (shi - slo) * (dhi - dlo) + dlo
  end
end

--- convert an exponential range to a linear range.
-- @tparam number slo lower limit of input range (must be non-zero and of the same sign as shi)
-- @tparam number shi upper limit of input range (must be non-zero and of the same sign as slo)
-- @tparam number dlo lower limit of output range
-- @tparam number dhi upper limit of output range
-- @tparam number f input to convert
-- @treturn number
function Util.explin(slo, shi, dlo, dhi, f)
  if f <= slo then
    return dlo
  elseif f >= shi then
    return dhi
  else
    return math.log(f / slo) / math.log(shi / slo) * (dhi - dlo) + dlo
  end
end

--- map an exponential range to another exponential range.
-- @tparam number slo lower limit of input range (must be non-zero and of the same sign as shi)
-- @tparam number shi upper limit of input range (must be non-zero and of the same sign as slo)
-- @tparam number dlo lower limit of output range (must be non-zero and of the same sign as dhi)
-- @tparam number dhi upper limit of output range (must be non-zero and of the same sign as dlo)
-- @tparam number f input to convert
-- @treturn number
function Util.expexp(slo, shi, dlo, dhi, f)
  if f <= slo then
    return dlo
  elseif f >= shi then
    return dhi
  else
    return ((dhi / dlo) ^ (math.log(f / slo) / math.log(shi / slo))) * dlo
  end
end

--- round a number with optional quantization
-- @tparam number number a number
-- @tparam number quant quantization
-- @function util.round
function Util.round(number, quant)
  if quant == 0 then
    return number
  else
    return math.floor(number / (quant or 1) + 0.5) * (quant or 1)
  end
end

--- clear the terminal window
-- @function util.clear_screen
function Util.clear_screen()
  Util.os_capture("clear")
end

--- execute OS command
-- @tparam string cmd command to execute
-- @tparam[opt] bool raw flag whether to clean up output
-- @treturn string output from executing the command
-- @function util.os_capture
function Util.os_capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
end

--- convert string to acronym
-- @tparam string name
-- @treturn string acronym
-- @function util.acronym
function Util.acronym(name)
  name = name:gsub("[%w']+", function(word)
    if not word:find("%U") then return word end
    return word:sub(1, 1)
  end)
  return (name:gsub("%s+", ""))
end

--- convert degrees to radians
-- @tparam number degrees
-- @treturn number radians
-- @function util.degs_to_rads
function Util.degs_to_rads(degrees)
  return degrees * (math.pi / 180)
end

--- convert radians to degrees
-- @tparam number radians
-- @treturn number degrees
-- @function util.rads_to_degs
function Util.rads_to_degs(radians)
  return radians * (180 / math.pi)
end

--- wrap a integer to a positive min/max range
-- @tparam integer n
-- @tparam integer min
-- @tparam integer max
-- @treturn integer cycled value
-- @function util.wrap
function Util.wrap(n, min, max)
  if max < min then
    local temp = min
    min = max
    max = temp
  end
  if n >= min and n <= max then
    return n
  end
  local d = max - min + 1
  y = (n - min) % d
  return y + min
end

return Util
