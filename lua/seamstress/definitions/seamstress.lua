---@meta

---@class seamstress
---@field _prefix string location of seamstress lua files; override by setting SEAMSTRESS_LUA_PATH
---@field _loop lightuserdata opaque handle to the event loop
---@field _pwd string directory seamstress was launched from
seamstress = {}

---loads a module by name
---@param module string
function seamstress._load(module) end

---launches a module
---@param module string
function seamstress._launch(module) end

---quits seamstress
function seamstress.quit() end

---restarts seamstress
function seamstress.restart() end

---logs text to /tmp/seamstress.log
---@param text string|Line
function seamstress.log(text) end

---@type {[1]:integer, [2]:integer, [3]:integer, pre:string?, build:string?} # semantic version
seamstress.version = {}

seamstress.config = {}

---@type string|nil|"test"
seamstress.config.script_name = "test"

---says hello
---@param version {[1]:integer, [2]:integer, [3]:integer, pre:string?, build:string?} # semantic version
seamstress.hello = function(version) end
