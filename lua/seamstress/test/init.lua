local tests = {
  run = function()
    local ok, runner = pcall(require, 'busted.runner')
    if ok then
      os.exit = function(code, close)
        if code ~= 0 then error("exiting with code " .. code) end
        seamstress.quit()
      end
      test_runner = seamstress.async.Promise(function()
        runner()
        if seamstress.tui then require('seamstress.test.tui') end
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
