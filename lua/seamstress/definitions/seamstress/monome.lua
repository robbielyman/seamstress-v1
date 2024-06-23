---@meta
---@module 'seamstress.monome'

seamstress.monome = require 'seamstress.monome'[1]

---@class Grid
---@field dev userdata
---@field name string?
---@field serial string?
---@field prefix string?
---@field rows integer
---@field cols integer
---@field quads integer
---@field connected boolean
---@field key fun(x: integer, y: integer, z: 0 | 1)?
---@field tilt fun(n: integer, x: integer, y: integer, z: integer)?
local Grid = {}

---@return Grid
seamstress.monome.Grid.new = function() end

---sets grid led brightness
---@param x integer # 1-indexed
---@param y integer # 1-indexed
---@param val integer # 0-15
function Grid:led(x, y, val) end

---sets all grid leds
---@param val integer # 0-15
function Grid:all(val) end

---sets grid rotation
---@param val 0 | 90 | 180 | 270
function Grid:rotation(val) end

---limits led brightness
---@param val integer # 0-15
function Grid:intensity(val) end

---pushes led data to the grid
function Grid:refresh() end

---@class Arc
---@field dev userdata
---@field name string?
---@field serial string?
---@field prefix string?
---@field connected boolean
---@field key fun(n: integer,  z: 0 | 1)?
---@field delta fun(n: integer, d: integer)?
local Arc = {}

---@return Arc
seamstress.monome.Arc.new = function() end

---sets arc led brightness
---@param ring integer # 1-indexed
---@param n integer # 1-64
---@param val integer # 0-15
function Arc:led(ring, n, val) end

---sets all arc leds
---@param val integer # 0-15
function Arc:all(val) end

---draw a segment
---nb: this is calling down to Arc:led underneath
---@param ring integer # (1-4)
---@param from integer # first led (1-64)
---@param to integer # second led (1-64)
---@param level integer # (0-15)
function Arc:segment(ring, from, to, level) end

---pushes led data to the arc
function Arc:refresh() end
