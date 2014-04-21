local mkset       = require 'utilities.fuse'.mkset
local bit         = require 'bit'

local R_OK        = require 'constants.access'.R_OK
local W_OK        = require 'constants.access'.W_OK
local X_OK        = require 'constants.access'.X_OK

return function(config, LOG)

  local file = {}
  local fs = {}

  fs.get = require 'backend.memory.ctx'(file)

  function fs.new(ctx, attr)
    if not ctx.file and (ctx.parent or ctx.path == "/") then
      local meta = {}
      file[ctx.path] = meta
      meta.attr = attr
      meta.attr.access        = os.time()
      meta.attr.modification  = os.time()
      meta.attr.uid           = ctx.user.uid
      meta.attr.gid           = ctx.user.gid

      meta.xattr = {}
      if meta.attr.mode.dir then
        meta.attr.size = 4096
        meta.attr.nlink = 2
      else
        meta.attr.size = 0
        meta.attr.nlink = 1
        meta.data = ""
      end
      meta.name = ctx.tpath[#ctx.tpath]
      meta.children = {}

      local parent = file[ctx.ppath]
      if parent then
        parent.children[ctx.file.name] = ctx.path
      end
      return ctx
    end
  end

  function fs.move(ctx, newctx)
    local f = ctx.file
    if f then
      local newf = newctx.file
      if not newf then
        local parent = file[newctx.ppath]
        if parent and parent.attr.mode.dir then
          parent.attr.nlink = parent.attr.nlink+1
          local oldparent = file[ctx.ppath]
          oldparent.attr.nlink = ctx.parent.attr.nlink - 1
          oldparent.children[f.name] = nil
          f.name = newctx.tpath[#newctx.tpath]
          parent.children[f.name] = true
          newctx.file = f
          file[newctx.path] = f
          file[ctx.path] = nil
          ctx.invalidate()
          return newctx
        end
      end
    end
  end

  function fs.remove(ctx)
    if ctx.parent and ctx.file then
      ctx.parent.children[ctx.file.name] = nil
      if ctx.file.attr.mode.dir then
        ctx.parent.attr.nlink = ctx.parent.attr.nlink - 1
      end
      file[ctx.path] = nil
      ctx.invalidate()
      return ctx
    end
  end

  function fs.check(ctx, mask)
    if mask == 0 and ctx.file then return true end

    local uid, gid = ctx.user.uid, ctx.user.gid

    if uid == 0 then return true end

    local f = ctx.file

    local R_REQ = bit.band(mask, R_OK) == R_OK
    local W_REQ = bit.band(mask, W_OK) == W_OK
    local X_REQ = bit.band(mask, X_OK) == X_OK

    if f.attr.uid == uid then
      if  (not R_REQ or f.attr.mode.rusr) and
          (not W_REQ or f.attr.mode.wusr) and
          (not X_REQ or f.attr.mode.xusr) then
        return true
      end
    end

    if f.attr.gid == gid then
      if  (not R_REQ or f.attr.mode.rgrp) and
          (not W_REQ or f.attr.mode.wgrp) and
          (not X_REQ or f.attr.mode.xgrp) then
        return true
      end
    end

    if  (not R_REQ or f.attr.mode.roth) and
        (not W_REQ or f.attr.mode.woth) and
        (not X_REQ or f.attr.mode.xoth) then
      return true
    end

    return false
  end

  function fs.write(ctx, buf, offset)
    offset = offset or 0
    local file = ctx.file
    local buflen = #buf
    local filelen = #file.data
    if offset < filelen then
      if offset + buflen >= filelen then
        file.attr.size = offset + buflen - 1
        file.data = file.data:sub(1,offset)..buf
      else
        file.data = file.data:sub(1,offset)..buf..file.data:sub(offset+buflen)
      end
    else
      file.attr.size = offset + buflen - 1
      file.data = file.data..string.rep('\0', offset-filelen)..buf
    end
    return #buf
  end

  function fs.truncate(ctx, size)
    size = size or 0
    local file = ctx.file
    local len = #file.data
    if size == 0 then
      file.data = ""
    elseif size > len then
      file.data = file.data..string.rep('\0', size - len)
    elseif size > len then
      file.data = file.data:sub(1, size)
    end
    file.size = size
  end

  function fs.read(ctx, size, offset)
    offset = offset or 0
    local filelen = ctx.file.attr.size
    if offset < filelen then
      if offset + size > filelen then
        size = filelen - offset
      end
      return ctx.file.data:sub(offset + 1, offset + size)
    end
    return ''
  end

  function fs.setxattr(ctx, xattr)
    for name, value in pairs(xattr) do
      ctx.file.xattr[name] = value
    end
  end

  function fs.setattr(ctx, attr)
    for name, value in pairs(attr) do
      if value ~= nil then
        ctx.file.attr[name] = value
      end
    end
  end

  function fs.getxattr(ctx, xattr)
    if xattr == nil then
      return ctx.file.xattr
    else
      local ret = {}
      for name, value in pairs(xattr) do
        ret[name] = value
      end
      return ret
    end
  end

  function fs.setmode(ctx, mode)
    ctx.file.attr.mode = mode
  end

  local root = {
    mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }
  }
  fs.new(fs.get('/', {uid=0, gid=0}), root)

  return fs
end
