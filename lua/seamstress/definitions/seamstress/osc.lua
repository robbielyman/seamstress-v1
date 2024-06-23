---@meta

---@module 'seamstress.osc'

seamstress.osc = require 'seamstress.osc'[1]

---sends an OSC message
---@param address string|integer|[string, string|integer] # {host, port}, where host defaults to 'localhost'
---and port can be expressed as a string or an integer
---@param path string|[string,string] # an /osc/path/like/this, optionally with a string describing the types of the arguments to follow
---@param ... any? # arguments to be appended to the message
function seamstress.osc.send(address, path, ...) end

---matches an OSC path against a liblo "glob-style" pattern
---@param pattern string
---@param path string
---@return boolean
function seamstress.osc.match(pattern, path) end
