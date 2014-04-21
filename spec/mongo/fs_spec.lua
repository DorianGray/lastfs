local FS = require 'backend.mongo.fs'
local mkset = require 'utilities.fuse'.mkset
local config ={
  backend = {
    mongo = {
      timeout = 5000,
      host = '127.0.0.1',
      port = 27017,
      database = 'tests'
    }
  }
}

local connection = require 'backend.mongo.connection'(config.backend.mongo)

describe("FS should work", function()
  local fcol = connection:get_col("fs.files")
  local ccol = connection:get_col("fs.chunks")

  before_each(function()
    fcol:delete({})
    ccol:delete({})
  end)

  after_each(function()
    fcol:delete({})
    ccol:delete({})
  end)

  it("gets the root node context", function()
    local fs = FS(config)
    local ctx = fs.get('/', {uid = 0, gid = 0})
    assert.are.equal(ctx.path, '/')
    assert.are.equal(ctx.ppath, nil)
    assert.are.same(ctx.tpath, {})
    assert.are.equal(ctx.tppath, nil)
  end)

  it("can create a child node", function()
    local fs = FS(config)
    local ctx = fs.get('/test', {uid = 0, gid = 0})
    local oldnlink = ctx.parent.attr.nlink
    fs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    ctx.invalidate()
    assert.are.equal(oldnlink+1, ctx.parent.attr.nlink)
    assert.are.equal(ctx.path, '/test')
    assert.are.equal(ctx.file.name, 'test')
    assert.are.same(ctx.tpath, {'test'})
    assert.are.equal(ctx.ppath, '/')
    assert.are.same(ctx.tppath, {})
  end)

  it("gets a child node context", function()
    local fs = FS(config)
    local ctx = fs.get('/test', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    assert.are.equal(ctx.path, '/test')
    assert.are.equal(ctx.file.name, 'test')
    assert.are.same(ctx.tpath, {'test'})
    assert.are.equal(ctx.ppath, '/')
    assert.are.same(ctx.tppath, {})
  end)

  it("gets a grandchild node context", function()
    local fs = FS(config)
    local ctx = fs.get('/test', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    ctx = fs.get('/test/foo', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    assert.are.equal(ctx.path, '/test/foo')
    assert.are.same(ctx.tpath, {'test', 'foo'})
    assert.are.equal(ctx.ppath, '/test')
    assert.are.same(ctx.tppath, {'test'})
  end)

  it("can remove a node", function()
    local fs = FS(config)
    local ctx = fs.get('/test', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    ctx = fs.get('/test/foo.txt~', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    local ctx = fs.get('/test/foo.txt~', {uid=0,gid=0})
    assert.are.same(ctx.parent.children['foo.txt~'], ctx.path)
    fs.remove(ctx)
    assert.are.same(ctx.parent.children, {})
  end)

  it("can move a node", function()
    local fs = FS(config)
    local ctx = fs.get('/test', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    ctx = fs.get('/test/foo.txt', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    ctx = fs.get('/test2', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    local ctx = fs.get('/test/foo.txt', {uid=0,gid=0})
    local newctx = fs.get('/test2/bar.txt')
    fs.move(ctx, newctx)
    assert.are.equal(ctx.parent.children['foo.txt'], nil)
    assert.are.same(newctx.parent.children['bar.txt'], newctx.path)
  end)

  it("can read a blank file", function()
    local fs = FS(config)
    local ctx = fs.get('/test', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    ctx = fs.get('/test/foo.txt', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    local content = fs.read(ctx)
    assert.are.equal(content, "")
  end)

  it("can write to a blank file", function()
    local fs = FS(config)
    local ctx = fs.get('/test.txt', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    local count = fs.write(ctx, "test")
    fs.fsync(ctx)
    ctx.invalidate()
    assert.are.equal(count, 4)
    assert.are.equal(ctx.file.attr.size, 4)
    local bytes = fs.read(ctx)
    assert.are.equal(bytes, "test")
  end)

  it("can write to an existing file", function()
    local fs = FS(config)
    local ctx = fs.get('/test.txt', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    local count = fs.write(ctx, "I've lost =(")
    fs.fsync(ctx)
    ctx.invalidate()
    assert.are.equal(count, 12)
    assert.are.equal(ctx.file.attr.size, 12)
    local bytes = fs.read(ctx)
    assert.are.equal(bytes, "I've lost =(")
    fs.write(ctx, "won!", 5)
    fs.write(ctx, ")", 11)
    fs.fsync(ctx)
    assert.are.equal(fs.read(ctx), "I've won! =)")
  end)

  it("can rewrite an existing file", function()
    local fs = FS(config)
    local ctx = fs.get('/test.txt', {uid = 0, gid = 0})
    fs.new(ctx, {mode = mkset{'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }})
    local count = fs.write(ctx, "I've lost =(")
    fs.fsync(ctx)
    ctx.invalidate()
    assert.are.equal(count, 12)
    assert.are.equal(ctx.file.attr.size, 12)
    local bytes = fs.read(ctx)
    assert.are.equal(bytes, "I've lost =(")
    fs.truncate(ctx)
    assert.are.equal(fs.read(ctx), '')
    fs.write(ctx, "I've won! =)")
    fs.fsync(ctx)
    assert.are.equal(fs.read(ctx), "I've won! =)")
  end)
end)
