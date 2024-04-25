local testing = {
  tests_list = {},
  overrides_list = {},
}

testing.test = function(name, f)
  if testing.tests_list[name] then
    table.insert(testing.tests_list[name], f)
  else
    testing.tests_list[name] = { f }
  end
end

local function run_test(f)
  local ok, msg = pcall(f)
  for _, override in ipairs(testing.overrides_list) do
    override()
  end
  return ok, msg
end

testing.run = function()
  local num_errors, num_success = 0, 0
  for name, list in pairs(testing.tests_list) do
    for idx, f in ipairs(list) do
      local ok, msg = run_test(f)
      if not ok then
        local testname = name .. (idx > 1 and (" #" .. idx) or "")
        print("test " .. testname .. " failed!")
        print(msg)
        num_errors = num_errors + 1
      else
        num_success = num_success + 1
      end
    end
  end
  if num_errors > 0 then
    error("tests failed: " .. num_errors .. " failed, " .. num_success .. " succeeded.")
  else
    print("all " .. num_success .. " tests succeeded.")
  end
end

testing.override = function(key, new_value)
  local old_value = key
  table.insert(testing.overrides_list, function() key = old_value end)
  key = new_value
end

testing.report = function(value)
  return value
end

testing.wait_for = function(value)
  local old_report = testing.report
  local coro = coroutine.create(function()
    return coroutine.yield()
  end)
  testing.report = function(val)
    coroutine.resume(coro, val)
  end
  local got = coroutine.resume(coro)
  testing.report = old_report
  testing.expect.same(value, got)
end

testing.expect = setmetatable({
  same = function(expected, actual, msg)
    msg = msg or "expect.same:"
    if type(expected) == "table" and type(actual) == "table" then
      for key, value in pairs(expected) do
        testing.expect.same(value, actual[key], msg .. " " .. key .. ":")
      end
      for key, value in pairs(actual) do
        testing.expect.same(expected[key], value, msg .. " " .. key .. ":")
      end
    else
      testing.expect.eql(expected, actual, msg .. "expected " .. expected .. "; got " .. actual .. "!")
    end
  end,

  eql = function(expected, actual, msg)
    msg = msg or ("expected " .. expected .. "; got " .. actual .. "!")
    testing.expect(expected == actual, msg)
  end,

  not_to_be = setmetatable({
    eql = function(expected, actual, msg)
      msg = msg or ("expected different: " .. expected .. " and " .. actual .. "!")
      testing.expect.not_to_be(expected == actual, msg)
    end,

    same = function(expected, actual, msg)
      local ok = pcall(testing.expect.same, expected, actual)
      if ok then
        msg = msg or ("expected different: " .. expected .. " and " .. actual .. "!")
        testing.expect(false, msg)
      end
    end,
  }, {
    __call = function(ok, msg)
      if ok then
        error(debug.traceback(msg or ("expected falsey value! got " .. tostring(ok))))
      end
    end,
  }),
}, {
  __call = function(ok, msg)
    if not ok then
      error(debug.traceback(msg or ("expected truthy value! got " .. tostring(ok))))
    end
  end,
})

return testing
