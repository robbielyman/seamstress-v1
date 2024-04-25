local t = testing

t.test("testing", function()
  local a = 13
  t.expect(a == 13)
  t.expect.eql(13, a)
  a = 14
  t.expect.not_to_be(a == 13)
  t.expect.not_to_be.eql(13, a)
  t.expect.same(14, a)
  a = { false, "string", 14, b = "named" }
  t.expect.same({ false, "string", 14, b = "named" }, a)
  t.expect.not_to_be.eql({ false, "string", 14, b = "named" }, a)
  t.expect.not_to_be.same({}, a)
end)
