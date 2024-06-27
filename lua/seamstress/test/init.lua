local tests = {
  run = function()
    local ok, runner = pcall(require, 'busted.runner')
    if ok then
      seamstress.async.Promise(function()
        runner({ output = seamstress._prefix .. '/seamstress/test/seamstress_output.lua' })
        require('seamstress.test.osc')
        require('seamstress.test.async')
        require('seamstress.test.timer')
        require('seamstress.test.monome')
        require('seamstress.test.clock')
        require('seamstress.test.midi')
        if seamstress.tui then require('seamstress.test.tui') end
        os.exit = seamstress.quit
      end)
      return
    end
    if seamstress.tui then seamstress.tui.setAltScreen(false) end
    print(runner)
    print('')
    local handle = io.popen 'luarocks path'
    if handle then
      local lines = {}
      local line = handle:read('*line')
      while line do
        line = line:gsub('"', '')
        line = line:gsub("'", '')
        if line:find('=') then
          table.insert(lines, line:sub(1, line:find('=')) .. "\'" .. line:sub(line:find('=') + 1) .. "\'")
        end
        line = handle:read('*line')
      end
      handle:close()
      print("it might help to run the following commands and retry testing:")
      print('')
      for _, txt in ipairs(lines) do print(txt) end
      print('')
      seamstress.quit()
    end
  end
}

return tests
