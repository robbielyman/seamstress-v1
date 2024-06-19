---@meta
---@module 'seamstress.tui'

seamstress.tui = require'seamstress.tui'

---creates a Line or Lines from text
---@param str string|string[]
---@param style Style?
---@return Line[]
function seamstress.tui.Line(str, style) end

---@class Line userdata
---@operator len(Line): integer # width in characters
local Line = {}

---@return integer the width of the line in cells
function Line:width() end

---like string:sub but for Line objects
---@param start integer
---@param finish? integer|-1
---@return Line
function Line:sub(start, finish) end

---like string:find but for Line objects
---@param needle string|Line
---@param start integer
---@return integer? start index
---@return integer? end index
function Line:find(needle, start) end

---@class Color userdata
---@operator unm(Color): Color
---@operator add(Color|number): Color
---@operator sub(Color|number): Color
---@operator mul(Color|number): Color
---@operator div(Color|number): Color
---@field r integer
---@field g integer
---@field b integer
---@overload fun(self: Color, line: string|Line|Line[], which: 'fg'|'bg'|'ul'): Line|Line[]
local Color = {}

---@overload fun(r: number,g: number,b: number): Color
---@param hex string? should begin with hash and contain six hex characters
---@return Color
function seamstress.tui.Color(hex) end

---@alias UlStyle "single" | "double" | "curly" | "dotted" | "dashed"
---@alias Mods "bold" | "dim" | "italic" | "blink" | "reverse" | "invisible" | "strikethrough"
---@alias TextColor "fg" | "bg" | "ul"

---@class (exact) Style userdata
---@overload fun(self: Style, text: string|Line|Line[]): Line|Line[]
---@field fg Color
---@field bg Color
---@field ul Color
---@field ul_style "off"|UlStyle
---@field bold boolean
---@field dim boolean
---@field italic boolean
---@field blink boolean
---@field reverse boolean
---@field invisible boolean
---@field strikethrough boolean
local Style = {}

---@alias StyleSpec { [TextColor]: string|Color?, [Mods]: boolean, ul_style: "off"|UlStyle? }

---creates a new Style
---@param spec string|StyleSpec
---@return Style
function seamstress.tui.Style(spec) end

---@alias Location "top" | "right" | "bottom" | "left"
---@alias Border {[1]:"all"|Location,[2]:Location?,[3]:Location?,[4]:Location?, style?:Style}
---@alias Box {x:[integer,integer],y:[integer,integer],border:"all"|Location|Border?}

---draws to the terminal screen using the provided bounding box
---@param line (string | Line | Line[])
---@param box Box
---@param wrap boolean?
function seamstress.tui.drawInBox(line, box, wrap) end

---displays the cursor relative to the given box
---@param x integer
---@param y integer
---@param box Box
function seamstress.tui.showCursorInBox(x, y, box) end

---clears the box
---@param box Box
function seamstress.tui.clearBox(box) end
