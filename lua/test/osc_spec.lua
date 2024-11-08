describe('seamstress.osc',
  function()
    local osc = require 'seamstress.osc'
    describe('seamstress.osc.Message',
      function()
        it('is callable', function()
          assert.is.callable(osc.Message)
        end)
        describe('returns a value', function()
          local m = osc.Message()
          it('which is a Message', function()
            assert.is.userdata(m)
            assert.is(m.__name, 'seamstress.osc.Message')
          end)
          it('which has a path', function()
            assert.are.same(m.path, nil)
            m.path = "/an/osc/path"
            assert.are.same(m.path, "/an/osc/path")
          end)
          it('arguments can be added and changed', function()
            assert.are.same(#m, 0)
            m[1] = 15
            assert.are.same('i', m.types)
            m[2] = 1.5
            m[3] = "string"
            assert.are.same('ifs', m.types)
            m[3] = true
            assert.are.same('ifT', m.types)
          end)
          it('can be converted to bytes', function()
            local bytes = m:bytes()
            assert.are.same(#bytes % 4, 0)
          end)
        end)
      end)
  end
)
