local fs = require 'backend.memory.fs'
local mkset = require 'utilities.fuse'.mkset

describe("FS should work", function()
  it("gets the root node context", function()
    local afs = fs()
    local ctx = afs.get('/', {uid = 0, gid = 0})
    assert.are.equal(ctx.path, '/')
    assert.are.equal(ctx.ppath, nil)
    assert.are.same(ctx.tpath, {})
    assert.are.equal(ctx.tppath, nil)
  end)

  it("gets a child node context", function()
    local afs = fs()
    local ctx = afs.get('/test', {uid = 0, gid = 0})
    afs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    assert.are.equal(ctx.path, '/test')
    assert.are.equal(ctx.file.name, 'test')
    assert.are.same(ctx.tpath, {'test'})
    assert.are.equal(ctx.ppath, '/')
    assert.are.same(ctx.tppath, {})
  end)

  it("gets a grandchild node context", function()
    local afs = fs()
    local ctx = afs.get('/test', {uid = 0, gid = 0})
    afs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    ctx = afs.get('/test/foo', {uid = 0, gid = 0})
    afs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    assert.are.equal(ctx.path, '/test/foo')
    assert.are.same(ctx.tpath, {'test', 'foo'})
    assert.are.equal(ctx.ppath, '/test')
    assert.are.same(ctx.tppath, {'test'})
  end)

  it("can remove a node", function()
    local afs = fs()
    local ctx = afs.get('/test', {uid = 0, gid = 0})
    afs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    ctx = afs.get('/test/foo.txt', {uid = 0, gid = 0})
    afs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    local ctx = afs.get('/test/foo.txt', {uid=0,gid=0})
    assert.are.same(ctx.parent.children['foo.txt'], ctx.path)
    afs.remove(ctx)
    local ctx = afs.get('/test', {uid = 0, gid = 0})
    assert.are.same(ctx.file.children, {})
  end)
end)
