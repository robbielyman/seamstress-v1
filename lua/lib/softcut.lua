--- softcut module
--
-- API for controlling softcut-client over OSC
-- mirrors the norns Lua API for softcut
-- but note some differences:
-- softcut-client is a separate install from seamstress
-- so this library is not `require`'d by default
-- softcut must be manually or programmatically initialized,
-- and the non-realtime capabilities are not yet at parity.
--
-- the below assumes that `softcut-client` is available on your $PATH.
-- to install it, see the instructions at
-- https://github.com/ryleelyman/softcut-zig
--
-- @module softcut

local softcut = {}

--[[
  based on norns' softcut.lua
  norns softcut.lua first committed by @catfact Dec 31, 2018
  rewritten for seamstress by @ryleelyman Jan 16, 2024
]]

local controlspec = require("controlspec")

-------
-- @section constants
-- (or parameters, if you'd prefer)

-- @field number of voices
softcut.VOICE_COUNT = 6
-- @field length of buffer in seconds
softcut.BUFFER_SIZE = (2 ^ 24) / 48000
-- @field OSC port that softcut-client is listening on
-- (you should update this in your script if you change it on your machine)
softcut.SOFTCUT_PORT = "9999"

-- sends to softcut over OSC
local function s(path, args)
  if args == nil then
    args = {}
  end
  osc.send({ "127.0.0.1", softcut.SOFTCUT_PORT }, path, args)
end

------
-- @section setters

--- set output level of each voice
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.level = function(voice, amp)
  s("/set/level/cut", { voice - 1, amp })
end

--- set pan position of each voice
-- -1 = full left, +1 == full right, 0 == centered
-- @tparam int voice voice index
-- @tparam number pos position in [-1,1]
softcut.pan = function(voice, pos)
  s("/set/pan/cut", { voice - 1, (pos + 1) * 0.5 })
end

--- set input level to each voice / channel
-- @tparam int ch audio input channel index (1, 2)
-- @tparam voice voice index
-- @tparam number amp linear amplitude
softcut.level_input_cut = function(ch, voice, amp)
  s("/set/level/in_cut", { ch - 1, voice - 1, amp })
end

--- set mix matrix, voice output to voice input.
-- @tparam int src source voice index
-- @tparam int dst destination voice index
-- @tparam number amp linear amplitude
softcut.level_cut_cut = function(src, dst, amp)
  s("/set/level/cut_cut", { src - 1, dst - 1, amp })
end

--- set play status
-- @tparam voice voice index
-- @tparam int state off/on (0, 1)
softcut.play = function(voice, state)
  s("/set/param/cut/play_flag", { voice - 1, state })
end

--- set playback rate
-- @tparam int voice voice index
-- @tparam number rate sate of speed of read/write head (1 == normal)
softcut.rate = function(voice, rate)
  s("/set/param/cut/rate", { voice - 1, rate })
end

--- set loop start
-- @tparam int voice voice index
-- @tparam number pos loop start position in seconds
softcut.loop_start = function(voice, pos)
  s("/set/param/cut/loop_start", { voice - 1, pos })
end

--- set loop end
-- @tparam int voice voice index
-- @tparam number pos loop end position in seconds
softcut.loop_end = function(voice, pos)
  s("/set/param/cut/loop_end", { voice - 1, pos })
end

--- set loop mode
-- "0" indicates one-shot mode: voice will play to the loop point, fadeout and stop.
-- "1" indicates crossfaded looping mode
-- @tparam int voice voice index
-- @tparam int state off/on (0, 1)
softcut.loop = function(voice, state)
  s("/set/param/cut/loop_flag", { voice - 1, state })
end

--- set fade time
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.rec_level = function(voice, amp)
  s("/set/param/cut/rec_level", { voice - 1, amp })
end

--- set _pre_serve level (overdub preservation)
-- this sets the realtime-modulated "preserve" level,
-- by which existing material is scaled on each pass of the write head.
-- `recpre` slew level applies
-- @tparam int voice voice index
-- @tparam number amp linear amplitude of preserved signal
softcut.pre_level = function(voice, amp)
  s("/set/param/cut/pre_level", { voice - 1, amp })
end

--- set record state
-- @tparam int voice voice number
-- @tparam int state off/on (0, 1)
softcut.rec = function(voice, state)
  s("/set/param/cut/rec_flag", { voice - 1, state })
end

--- set record head offset
-- @tparam int voice voice number
-- @tparam number sec seconds
softcut.rec_offset = function(voice, sec)
  s("/set/param/cut/rec_offset", { voice - 1, sec })
end

--- set play position
-- @tparam int voice voice number
-- @tparam number pos set play position
softcut.position = function(voice, pos)
  s("/set/param/cut/position", { voice - 1, pos })
end

--- specify buffer used by voice
-- @tparam int voice voice number
-- @tparam int buffer buffer number
softcut.buffer = function(voice, buffer)
  s("/set/param/cut/buffer", { voice - 1, buffer - 1 })
end

--- synchronize two voices
-- position of "dst" will immediately be set to that of "source" (with offset)
-- @tparam int dst destination voice
-- @tparam int src source voice index
-- @tparam number offset additional offset in seconds
softcut.voice_sync = function(dst, src, offset)
  s("/set/param/cut/voice_sync", { src - 1, dst - 1, offset })
end

--- set pre_filter cutoff frequency
-- @tparam int voice voice index
-- @tparam number fc cutoff frequency in Hz
softcut.pre_filter_fc = function(voice, fc)
  s("/set/param/cut/pre_filter_fc", { voice - 1, fc })
end

--- set pre_filter amount of rate modulation
-- this parameter controls the amount by which the current rate affects filter cutoff ffrequency
-- (always in a negative direction, towards zero.)
-- with mod == 1, setting rate = 0 will also fully close the filter.
-- this can be useful as a crude anti-aliasing method.
-- @tparam int voice voice index
-- @tparam number amount modulation amount in [0, 1]
softcut.pre_filter_fc_mod = function(voice, amount)
  s("/set/param/cut/pre_filter_fc_mod", { voice - 1, amount })
end

--- set the reciprocal of the filter's Q-factor is a measure of bandwidth
-- that is independent of the center frequency.
-- RQ near 0 will result in self-oscillation;
-- RQ == 4 gives a bandwidth of 2 octaves
-- @tparam int voice voice index
-- @tparam number rq reciprocal of filter Q-factor
softcut.pre_filter_rq = function(voice, rq)
  s("/set/param/cut/pre_filter_rq", { voice - 1, rq })
end

--- set pre_filter lowpass output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.pre_filter_lp = function(voice, amp)
  s("/set/param/cut/pre_filter_lp", { voice - 1, amp })
end

--- set pre_filter highpass output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.pre_filter_hp = function(voice, amp)
  s("/set/param/cut/pre_filter_hp", { voice - 1, amp })
end

--- set pre_filter bandpass output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.pre_filter_bp = function(voice, amp)
  s("/set/param/cut/pre_filter_bp", { voice - 1, amp })
end

--- set pre_filter band-reject output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.pre_filter_br = function(voice, amp)
  s("/set/param/cut/pre_filter_br", { voice - 1, amp })
end

--- set pre_filter dry output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.pre_filter_dry = function(voice, amp)
  s("/set/param/cut/pre_filter_dry", { voice - 1, amp })
end

--- set post_filter cutoff
-- @tparam int voice voice index
-- @tparam number fc cutoff frequency in hz
softcut.post_filter_fc = function(voice, fc)
  s("/set/param/cut/post_filter_fc", { voice - 1, fc })
end

--- set post_filter reciprocal of Q
-- the reciprocal of the filter's Q factor is a measure of bandwidth,
-- that is independent of center frequency.
-- RQ ~= 0 will result in self oscillation;
-- RQ == 4 gives a bandwidth of 2 octaves.
-- @tparam int voice : voice index
-- @tparam number rq : reciprocal of filter Q-factor for voice
softcut.post_filter_rq = function(voice, amp)
  s("/set/param/cut/post_filter_rq", { voice - 1, amp })
end

--- set post_filter lowpass output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.post_filter_lp = function(voice, amp)
  s("/set/param/cut/post_filter_lp", { voice - 1, amp })
end

--- set post_filter highpass output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.post_filter_hp = function(voice, amp)
  s("/set/param/cut/post_filter_hp", { voice - 1, amp })
end

--- set post_filter bandpass output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.post_filter_bp = function(voice, amp)
  s("/set/param/cut/post_filter_bp", { voice - 1, amp })
end

--- set post_filter band-reject output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.post_filter_br = function(voice, amp)
  s("/set/param/cut/post_filter_br", { voice - 1, amp })
end

--- set post_filter dry output level
-- @tparam int voice voice index
-- @tparam number amp linear amplitude
softcut.post_filter_dry = function(voice, amp)
  s("/set/param/cut/post_filter_dry", { voice - 1, amp })
end

--- set level slew time
-- this slew time applies to level at all mix points (input->voice, voice->voice, etc)
-- @tparam int voice voice index
-- @tparam number time exponential slew time in seconds (~60db convergence)
softcut.level_slew_time = function(voice, time)
  s("/set/param/cut/level_slew_time", { voice - 1, time })
end

--- set rec/pre slew time
-- this slew time applies to record and preserve levels
-- @tparam int voice voice index
-- @tparam number time exponential slew time in seconds (~60db convergence)
softcut.recpre_slew_time = function(voice, time)
  s("/set/param/cut/recpre_slew_time", { voice - 1, time })
end

--- set rate slew time
-- this slew time applies to rate
-- @tparam int voice voice index
-- @tparam number time exponential slew time in seconds (~60db convergence)
softcut.rate_slew_time = function(voice, time)
  s("/set/param/cut/rate_slew_time", { voice - 1, time })
end

--- set phase poll quantum
-- e.g. 0.25 will produce 4 updates per second with rate=1
-- judicious use of this parameter is preferable to using a very fast poll (for performance,)
-- or polling at arbitrary rate (for accuracy when rate is slewed.)
-- @tparam int voice : voice index
-- @tparam number quantum : phase reporting interval, in seconds
softcut.phase_quant = function(voice, quantum)
  s("/set/param/cut/phase_quant", { voice - 1, quantum })
end

--- set phase poll offset in frames
-- @tparam int voice : voice index
-- @tparam number offset : phase poll offset in seconds
softcut.phase_offset = function(voice, offset)
  s("/set/param/cut/phase_offset", { voice - 1, offset })
end

--- start phase poll
-- @tparam int port OSC port number for the poll to be sent to
-- (defaults to seamstress's listening port)
softcut.poll_start_phase = function(port)
  if port == nil then
    port = _seamstress.local_port
  end
  s("/poll/start/cut/phase", { port })
end

--- start vu poll
-- @tparam int port OSC port number for the poll to be sent to
-- (defaults to seamstress's listening port)
softcut.poll_start_vu = function(port)
  if port == nil then
    port = _seamstress.local_port
  end
  s("/poll/start/vu", { port })
end

--- stop phase poll
softcut.poll_stop_phase = function()
  s("/poll/stop/cut/phase")
end

--- stop vu poll
softcut.poll_stop_vu = function()
  s("/poll/stop/vu")
end

--- set voice enable
-- @tparam int voice voice number
-- @tparam int state off/on (0, 1)
softcut.enable = function(voice, state)
  s("/set/enabled/cut", { voice - 1, state })
end

--- clear all buffers completel
softcut.buffer_clear = function()
  s("/softcut/buffer/clear")
end

--- clear one buffer completely
-- @tparam int channel buffer channel index (1-based)
softcut.buffer_clear_channel = function(channel)
  s("/softcut/buffer/clear_channel", { channel - 1 })
end

--- clear region (both channels)
-- @tparam start start point in seconds
-- @tparam dur duration in seconds
softcut.buffer_clear_region = function(start, dur)
  s("/softcut/buffer/clear_region", { start, dur })
end

--- clear region of single channel
-- @tparam int channel buffer channel (1-based)
-- @tparam number start start point in seconds
-- @tparam number dur duration in seconds
softcut.buffer_clear_region_channel = function(channel, start, dur)
  s("/softcut/buffer/clear_region_channel", { channel, start, dur })
end

--- read mono soundfile to arbitrary region of single buffer
-- @tparam string file : input file path
-- @tparam number start_src : start point in source, in seconds
-- @tparam number start_dst : start point in destination, in seconds
-- @tparam number dur : duration in seconds. if -1, read as much as possible.
-- @tparam int ch_src : soundfile channel to read
-- @tparam int ch_dst : buffer channel to write
softcut.buffer_read_mono = function(file, start_src, start_dst, dur, ch_src, ch_dst)
  s(
    "/softcut/buffer/read_mono",
    { file, start_src or 0, start_dst or 0, dur or -1, ch_src and ch_src - 1 or 0, ch_dst and ch_dst - 1 or 0 }
  )
end

--- read stereo soundfile to an arbitrary region in both buffers
-- @tparam string file : input file path
-- @tparam number start_src : start point in source, in seconds
-- @tparam number start_dst : start point in destination, in seconds
-- @tparam number dur : duration in seconds. if -1, read as much as possible
softcut.buffer_read_stereo = function(file, start_src, start_dst, dur)
  s("/softcut/buffer/read_stereo", { file, start_src or 0, start_dst or 0, dur or -1 })
end

--- write an arbitrary buffer region to soundfile (mono)
-- @tparam string file : output file path
-- @tparam number start : start point in seconds
-- @tparam number dur : duration in seconds. if -1, read as much as possible
-- @tparam int ch : buffer channel index (1-based)
softcut.buffer_write_mono = function(file, start, dur, ch)
  s("/softcut/buffer/write_mono", { file, start or 0, dur or -1, ch and ch - 1 or 0 })
end

--- write an arbitrary region from both buffers to stereo soundfile
-- @tparam string file : output file path
-- @tparam number start : start point in seconds
-- @tparam number dur : duration in seconds. if -1, read as much as possible
softcut.buffer_write_stereo = function(file, start, dur)
  s("softcut/buffer/write_stereo", { file, start or 0, dur or -1 })
end

--- set function for phase poll
-- @tparam function(voice, phase) func : callback function. this function should take two parameters  (voice, phase)
softcut.event_phase = function(func)
  osc.register("/poll/softcut/phase", func, "if")
end

--- set function for vu poll
-- @tparam function(left, right) func callback function. this function should take two parameters (left, right)
softcut.event_vu = function(func)
  osc.register("/poll/softcut/vu", func, "ff")
end

-------
-- @section utilities

--- starts a new softcut process with -i, -o, and -p set
-- @tparam int i input device number
-- @tparam int o output device number
-- @tparam int p port number (defaults to softcut.SOFTCUT_PORT)
-- @tparam string c command to execute (defaults to "softcut-client")
function softcut.init(i, o, p, c)
  if c == nil then
    c = "softcut-client"
  end
  if p == nil then
    p = softcut.SOFTCUT_PORT
  end
  _seamstress.child_process(c, { "-i", i, "-o", o, "-p", p })
end

--- reset state of softcut process
function softcut.reset()
  s("/softcut/reset")
  osc.delete("/poll/softcut/phase", "if")
end

--- get the default state of the softcut system
-- this returns a table for each voice,
-- in which each key corresponds to the name of one of the setter functions defined above.
-- for parameters with one value per voice, the corresponding entry is also a single value.
-- for parameters with multiple values (e.g. matrix indices), the entry is a table.
-- NB: these values are synchronized by hand with those specified in the softcut cpp sources
-- @treturn table table of parameter states for each voice
function softcut.defaults()
  zeros = {}
  for i = 1, softcut.VOICE_COUNT do
    zeros[i] = 0
  end
  local state = {}
  for i = 1, softcut.VOICE_COUNT do
    state[i] = {
      enable = 0,
      play = 0,
      record = 0,

      buffer = (i % 2 + 1),
      level = 0,
      pan = 0,

      level_input_cut = { 0, 0 },
      level_cut_cut = zeros,

      rate = 1,
      loop_start = (i - 1) * 2,
      loop_end = (i - 1) * 2 + 1,
      loop = 1,

      fade_time = 0.0005,
      rec_level = 0,
      pre_level = 0,
      rec = 0,
      rec_offset = -0.00015,
      position = 0,

      pre_filter_fc = 16000,
      pre_filter_fc_mod = 1,
      pre_filter_dry = 0,
      pre_filter_lp = 1,
      pre_filter_hp = 0,
      pre_filter_bp = 0,
      pre_filter_br = 0,

      post_filter_fc = 12000,
      post_filter_dry = 0,
      post_filter_lp = 0,
      post_filter_hp = 0,
      post_filter_bp = 0,
      post_filter_br = 0,

      level_slew_time = 0.001,
      rate_slew_time = 0.001,
      phase_quant = 1,
      phase_offset = 0,
    }
  end
  return state
end

--- controlspec factory
-- each table contains an entry for each softcut parameter.
-- each entry is a parameter argument list configured for that voice+param
-- @return an array of tables, one per voice.
function softcut.params()
  -- @fixme should memoize
  local specs = {}
  local voice = 1
  while voice <= softcut.VOICE_COUNT do
    local spec = {
      -- voice enable
      enable = { type = "number", min = 0, max = 1, default = 0 },
      -- levels
      -- @fixme: use dB / taper?
      level = { type = "control", controlspec = controlspec.new(0, 0, "lin", 0, 0.25, "") },
      pan = { type = "control", controlspec = controlspec.new(-1, 1, "lin", 0, 0, "") },
      level_input_cut = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0.5, "") },
      level_cut_cut = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      -- timing
      rate = { type = "control", controlspec = controlspec.new(-8, 8, "lin", 0, 0, "") },
      loop_start = {
        type = "control",
        controlspec = controlspec.new(0, softcut.BUFFER_SIZE, "lin", 0, voice * 2.5, "sec"),
      },
      loop_end = {
        type = "control",
        controlspec = controlspec.new(0, softcut.BUFFER_SIZE, "lin", 0, voice * 2.5 + 2, "sec"),
      },
      loop = { type = "number", min = 0, max = 1, default = 1 },
      fade_time = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      -- recording parameters
      rec_level = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      pre_level = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      play = { type = "number", min = 0, max = 1, default = 1 },
      rec = { type = "number", min = 0, max = 1, default = 1 },
      rec_offset = { type = "number", min = -100, max = 100, default = -8 },
      -- jump to position
      position = {
        type = "control",
        controlspec = controlspec.new(0, softcut.BUFFER_SIZE, "lin", 0, voice * 2.5, "sec"),
      },
      -- pre filter
      pre_filter_fc = { type = "control", controlspec = controlspec.new(10, 12000, "exp", 1, 12000, "Hz") },
      pre_filter_fc_mod = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 1, "") },
      pre_filter_rq = { type = "control", controlspec = controlspec.new(0.0005, 8.0, "exp", 0, 2.0, "") },
      -- @fixme use dB / taper?
      pre_filter_lp = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 1, "") },
      pre_filter_hp = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      pre_filter_bp = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      pre_filter_br = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      pre_filter_dry = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      -- post filter
      post_filter_fc = { type = "control", controlspec = controlspec.new(10, 12000, "exp", 1, 12000, "Hz") },
      post_filter_rq = { type = "control", controlspec = controlspec.new(0.0005, 8.0, "exp", 0, 2.0, "") },
      -- @fixme use dB / taper?
      post_filter_lp = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 1, "") },
      post_filter_hp = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      post_filter_bp = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      post_filter_br = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },
      post_filter_dry = { type = "control", controlspec = controlspec.new(0, 1, "lin", 0, 0, "") },

      -- slew times
      level_slew_time = { type = "control", controlspec = controlspec.new(0, 8, "lin", 0, 0, "") },
      rate_slew_time = { type = "control", controlspec = controlspec.new(0, 8, "lin", 0, 0, "") },
      -- poll quantization unit
      phase_quant = { type = "control", controlspec = controlspec.new(0, 8, "lin", 0, 0.125, "") },
    }
    -- assign name, id and action
    for k, v in pairs(spec) do
      local z = voice
      spec[k].id = k
      spec[k].name = "cut" .. z .. k
      local act = softcut[k]
      if act == nil then
        print("warning: didn't find SoftCut voice method: " .. k)
      end
      spec[k].action = function(x)
        act(z, x)
      end
    end
    specs[voice] = spec
    voice = voice + 1
  end

  return specs
end

return softcut
