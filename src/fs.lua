local mkset       = require 'utilities.fuse'.mkset
local bit         = require 'bit'

local R_OK        = require 'constants.access'.R_OK
local W_OK        = require 'constants.access'.W_OK
local X_OK        = require 'constants.access'.X_OK

return function()

  local file = {}
  local fs = {file = file}

  fs.get = require 'ctx'(file)

  function fs.new(ctx, meta)
    if not ctx.file and (ctx.parent or ctx.path == "/") then
      file[ctx.path] = meta
      if not meta.access then meta.access = os.time() end
      if not meta.modification then meta.modification = os.time() end
      if meta.mode.dir then
        meta.size = 4096
        meta.nlink = 2
      else
        meta.size = 0
        meta.nlink = 1
        meta.data = ""
      end
      meta.name = ctx.tpath[#ctx.tpath]
      meta.uid = ctx.user.uid
      meta.gid = ctx.user.gid
      meta.children = {}
      meta.parent = ctx.parent and ctx.parent

      if meta.parent then
        meta.parent.children[ctx.file.name] = meta
      end
      return ctx
    end
  end

  function fs.move(ctx, newctx)
    local f = ctx.file
    if f then
      local newf = newctx.file
      if not newf then
        local parent = newctx.parent
        if parent and parent.mode.dir then
          parent.nlink = parent.nlink+1
          ctx.parent.nlink = ctx.parent.nlink - 1
          ctx.parent.children[f.name] = nil
          f.name = newctx.tpath[#newctx.tpath]
          parent.children[f.name] = f
          f.parent = newctx.parent
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
      if ctx.file.mode.dir then
        ctx.parent.nlink = ctx.parent.nlink - 1
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

    if f.uid == uid then
      if  (not R_REQ or f.mode.rusr) and
          (not W_REQ or f.mode.wusr) and
          (not X_REQ or f.mode.xusr) then
        return true
      end
    end

    if f.gid == gid then
      if  (not R_REQ or f.mode.rgrp) and
          (not W_REQ or f.mode.wgrp) and
          (not X_REQ or f.mode.xgrp) then
        return true
      end
    end

    if  (not R_REQ or f.mode.roth) and
        (not W_REQ or f.mode.woth) and
        (not X_REQ or f.mode.xoth) then
      return true
    end

    return false
  end

  local root = {
    mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }
  }
  fs.new(fs.get('/', {uid=0, gid=0}), root)

  return fs
end
