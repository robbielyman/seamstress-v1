---@meta

---@module 'seamstress.midi'

---@class seamstress.midi
---@field list {inputs: string[], outputs: string[]}
seamstress.midi = {}

---updates seamstress.midi.list regardless of how much time has passed
function seamstress.midi.rescan() end

---opens a MIDI port for output
---@param name string|integer
---@return MidiOut?
function seamstress.midi.connectOutput(name) end

---opens a MIDI port for input; call disconnectInput to close
---@param name string|integer
function seamstress.midi.connectInput(name) end

---closes a MIDI port, stopping receipt of messgaes sent to it
---@param name string|integer
function seamstress.midi.disconnectInput(name) end

---to be used as in for msg in seamstress.midi.messages(str) do...
---@param str string
---@return fun(): MidiMsg?
function seamstress.midi.messages(str) end

---encodes a midi message as bytes
---@param msg MidiMsg
---@return string
function seamstress.midi.encode(msg) end

---encodes a midi message as bytes
---@param msgs MidiMsg[]
---@return string
function seamstress.midi.encodeAll(msgs) end


---@alias MsgKind 'note_off' | 'note_on' | 'aftertouch' | 'control_change' | 'program_change' | 'channel_pressure' | 'pitch_wheel' | 'sysex' | 'quarter_frame' | 'song_position' | 'song_select' | 'tune_request ' | '10ms_tick' | 'start' | 'stop' | 'continue' | 'clock' | 'active_sense' | 'reset'

---@alias MidiMsg [MsgKind, ...] # typically  kind, channel, data1 data2

---@class MidiOut
---@field [MsgKind] fun(...) # alias for send({kind, ...})
local MidiOut = {}

---sends a midi message
---@param msg MidiMsg|string
function MidiOut.send(msg) end

---sends a chunk of midi messages
---@param msgs MidiMsg[]|string
function MidiOut.sendAll(msgs) end
