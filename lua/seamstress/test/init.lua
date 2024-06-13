local tests = {
  run = function()
    local ok, runner = pcall(require, 'busted.runner')
    if ok then
      local comp = require'busted.compatibility'
      local exit = comp.exit
      comp.exit = function(code, force)
        seamstress.quit()
      end
      test_runner = seamstress.async.Promise(function()
          runner()
        require('seamstress.test.tui')
        require('seamstress.test.async')
      end)
      return
    end
    print(runner)
    print('')
    local handle = io.popen 'luarocks path'
    if handle then
      local lines = {}
      local line = handle:read('*line')
      while line do
        line = line:gsub('"', '')
        line = line:gsub("'", '')
        table.insert(lines, line:sub(1, line:find('=')) .. "\'" .. line:sub(line:find('=') + 1) .. "\'")
        line = handle:read('*line')
      end
      handle:close()
      print("it might help to run the following commands and retry testing:\n")
      for _, txt in ipairs(lines) do print(txt) end
      print('')
      seamstress.quit()
    end
  end
}

return tests
