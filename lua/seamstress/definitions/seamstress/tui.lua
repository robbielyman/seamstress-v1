---@meta
---@module 'seamstress.tui'

---@class seamstress.tui
seamstress.tui = require 'seamstress.tui'[1]

---@class Color userdata
---@operator unm(Color): Color
---@operator add(Color|number): Color
---@operator sub(Color|number): Color
---@operator mul(Color|number): Color
---@operator div(Color|number): Color
---@field r integer
---@field g integer
---@field b integer
local Color = {}

---@overload fun(r: number,g: number,b: number): Color
---@param hex integer|string? # if a string should begin with hash and contain six hex characters,
---if an integer, must be betreen 0 and 255
---@return Color
function seamstress.tui.Color(hex) end

---toggles whether seamstress is in the terminal "alt screen"
---@param alt_screen boolean
function seamstress.tui.setAltScreen(alt_screen) end

---tells seamstress to actually update the screen
---by default, automatically called at the end of a "draw" event
---unless a handler cancels the render by returning `false`
function seamstress.tui.renderCommit() end

---the terminal framebuffer
---@class seamstress.tui.buffer
seamstress.tui.buffer = {}

---@alias cols "fg" | "bg" | "ul"
---@alias mods "bold" | "dim" | "italic" | "blink" | "reverse" | "invisible" | "strikethrough"
---@alias ulstyle "off" | "single" | "double" | "curly" | "dotted" | "dashed"
---@alias cell {char: string?, [cols]: Color?, modifiers: {[mods]: boolean?}?, ul_style: ulstyle?}
---@alias location "top" | "right" | "bottom" | "left"
---@alias border "none" | "all" | location | {[1]: "none" | "all" | location, [2]: location?, [3]: location?, [4]: location?, style: { [cols]: Color?, modifiers: {[mods]: boolean?}?, ul_style: ulstyle? }?}
---@alias wrap "none" | "word" | "char"

---writes styled text to the framebuffer within the specified bounds
---@param x_box [integer, integer, integer?] # the last integer, if provided, is an offset into the bounding box
---@param y_box [integer, integer, integer?] # the last integer, if provided, is an offset into the bounding box
---@param text string
---@param style_opts {[cols]: Color?, modifiers: {[mods]: boolean?}?, ul_style: ulstyle?, border: border?, wrap: boolean|wrap?, dry_run: boolean? }?
---@return integer x # ending x-offset
---@return integer y # ending y-offset
function seamstress.tui.buffer.write(x_box, y_box, text, style_opts) end

---writes a cell to the framebuffer
---@param x integer|[integer, integer]
---@param y integer|[integer, integer]
---@param cell cell?
function seamstress.tui.buffer.set(x, y, cell) end

---reads a cell from the framebuffer
---@param x integer
---@param y integer
---@return {char: string, width: integer, [cols]: Color, modifiers: {[mods]: boolean}, ul_style: ulstyle}
function seamstress.tui.buffer.get(x, y) end

---places the cursor in the frame buffer
---@param x integer
---@param y integer
function seamstress.tui.buffer.placeCursor(x, y) end
