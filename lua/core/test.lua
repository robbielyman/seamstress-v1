local event = require 'seamstress.event'
local seamstress = require 'seamstress'

local function addAssertions()
  local say = require 'say'
  local assert = require 'luassert'
    local function is_callable(_, arguments)
        if type(arguments[1]) == 'function' then return true end
        if type(arguments[1]) ~= 'table' and type(arguments[1]) ~= 'userdata' then return false end
        return getmetatable(arguments[1]).__call ~= nil
    end

    say:set("assertion.is_callable.positive", "Expected %s \nto be callable")
    say:set("assertion.is_callable.negative", "Expected %s \nto not be callable")
    assert:register("assertion", "is_callable", is_callable, "assertion.is_callable.positive", "assertion.is_callable.negative")
end

local function runner()
  local s = require 'say'
  local pretty = require 'pl.pretty'
  local busted = require 'busted.core' ()

  busted.subscribe({ 'error' }, function(_, _, msg)
    print(msg)
    return nil, true
  end)

  require 'busted' (busted)

  addAssertions()

  local directory = os.getenv("SEAMSTRESS_LUA_PATH") .. package.config:sub(1, 1) .. "test"
  local loadTestFiles = require 'busted.modules.test_file_loader' (busted, { 'lua' })
  loadTestFiles({ directory }, { '_spec' }, { excludes = {}, verbose = true, })

  local handler = require 'busted.outputHandlers.base' ()

  local statusString = function()
    local success_string = s('output.success_plural')
    local failure_string = s('output.failure_plural')
    local pending_string = s('output.pending_plural')
    local error_string = s('output.error_plural')

    local sec = handler.getDuration()
    local successes = handler.successesCount
    local pendings = handler.pendingsCount
    local failures = handler.failuresCount
    local errors = handler.errorsCount

    if successes == 0 then
      success_string = s('output.success_zero')
    elseif successes == 1 then
      success_string = s('output.success_single')
    end

    if pendings == 0 then
      pending_string = s('output.pending_zero')
    elseif pendings == 1 then
      pending_string = s('output.pending_single')
    end

    if failures == 0 then
      failure_string = s('output.failure_zero')
    elseif failures == 1 then
      failure_string = s('output.failure_single')
    end

    if errors == 0 then
      error_string = s('output.error_zero')
    elseif errors == 1 then
      error_string = s('output.error_single')
    end

    local formatted_time = string.gsub(string.format("%.6f", sec), '([0-9])0+$', '%1')

    return successes .. ' ' .. success_string .. ' / ' ..
        failures .. ' ' .. failure_string .. ' / ' ..
        errors .. ' ' .. error_string .. ' / ' ..
        pendings .. ' ' .. pending_string .. ' : ' ..
        formatted_time .. ' ' .. s('output.seconds')
  end

  local pendingDescription = function(pending)
    local name = pending.name
    local str = s('output.pending') .. ' → ' ..
        pending.trace.short_src .. ' @ ' ..
        pending.trace.currentline .. '\n' .. name

    if type(pending.message) == 'string' then
      str = str .. '\n' .. pending.message
    elseif pending.message ~= nil then
      str = str .. '\n' .. pretty.write(pending.message)
    end
    return str
  end

  local failureMessage = function(failure)
    if type(failure.message) == 'string' then
      return failure.message
    elseif failure.message == nil then
      return 'Nil error'
    else
      return pretty.write(failure.message)
    end
  end

  local failureDescription = function(failure, is_error)
    local str = s('output.failure') .. ' → '
    if is_error then
      str = s('output.error') .. ' → '
    end

    if not failure.element.trace or not failure.element.trace.short_src then
      str = str .. failureMessage(failure) .. '\n' .. failure.name
    else
      str = str .. failure.element.trace.short_src .. ' @ ' ..
          failure.element.trace.currentline .. '\n' ..
          failure.name .. '\n' ..
          failureMessage(failure)
    end

    return str
  end

  handler.suiteEnd = function()
    io.write('\n')
    io.write(statusString() .. '\n')

    for _, pending in pairs(handler.pendings) do
      io.write('\n')
      io.write(pendingDescription(pending) .. '\n')
    end

    for _, err in pairs(handler.failures) do
      io.write('\n')
      io.write(failureDescription(err) .. '\n')
    end

    for _, err in pairs(handler.errors) do
      io.write('\n')
      io.write(failureDescription(err, true) .. '\n')
    end

    io.flush()
    return nil, true
  end
  handler:subscribe({ language = 'en' })
  busted.subscribe({ 'suite', 'end' }, handler.suiteEnd)

  local execute = require 'busted.execute' (busted)
  execute(1, {})
  seamstress:stop()
end

event.addSubscriber({ 'init' }, function()
  local ok, busted = pcall(require, 'busted')
  if ok then
    seamstress.async(runner)()
    return false
  end
  print(busted)
  seamstress:stop()
  return false
end)
