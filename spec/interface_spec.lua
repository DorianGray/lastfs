local fs = require 'backend.memory.fs'
local interface = require 'fuse.interface'

describe("Fuse Interface should work", function()
  it("getattr /", function()
    local afs = fs()
    local i = interface(afs)
    local attr = i.getattr('/')
    assert(attr)
    assert(attr.mode)
    assert(attr.mode.dir)
 end)
end)
