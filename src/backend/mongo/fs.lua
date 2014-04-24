local mkset       = require 'utilities.fuse'.mkset
local bit         = require 'bit'

local R_OK        = require 'constants.access'.R_OK
local W_OK        = require 'constants.access'.W_OK
local X_OK        = require 'constants.access'.X_OK

return function(config, LOG)
  local db = require 'backend.mongo.connection'(config.backend.mongo)

  local data = db:get_gridfs("fs")
  local fscol = db:get_col("fs.files")
  local ccol = db:get_col("fs.chunks")

  local fs = {}

  fs.get = require 'backend.mongo.ctx'(data)

  function fs.new(ctx, attr)
    local file = {}
    file.attr = attr
    file.attr.access        = os.time()
    file.attr.modification  = os.time()
    file.attr.uid           = ctx.user.uid
    file.attr.gid           = ctx.user.gid

    file.xattr = {}
    if file.attr.mode.dir then
      file.attr.nlink = 2
      file.children = {}
    else
      file.attr.nlink = 1
    end

    file.attr.size = 0
    file.name = ctx.tpath[#ctx.tpath]

    local meta = {
      _id = ctx.path,
      chunkSize = 64*1024,
      filename = file.name,
      metadata = file
    }
    local ok, err = data:new(meta, true)
    if not ok then error(err) end
    ctx.file = file
    ctx.rawfile = ok
    if ctx.path ~= '/' then
      local query = {
        ['$set']={
          ['metadata.children.'..ctx.file.name:gsub('%.','/')]=ctx.path
        }
      }
      if file.attr.mode.dir then
        query["$inc"] = {
          ['metadata.attr.nlink'] = 1
        }
      end
      local ok, err = fscol:update({
        _id=ctx.ppath
      }, query, 0, 1)
      if not ok then error(err) end
    end
    return ctx
  end

  function fs.move(ctx, newctx)
    --get original file
    if ctx.file then
      fs.fsync(ctx)
      local f = ctx.rawfile
      local oldfilename = ctx.file.name
      local newfilename = newctx.tpath[#newctx.tpath]

      ctx.file.name = newfilename
      --move file
      local newfile = {
        _id = newctx.path,
        chunkSize = f.chunk_size,
        length = f.file_size,
        md5 = f.file_md5,
        filename = newfilename,
        metadata = ctx.file
      }
      local ok, err = fscol:insert({newfile}, false)
      if not ok then error(err) end
      newctx.file = ctx.file

      --move chunks
      local ok, err = ccol:update({files_id=ctx.path}, {files_id=newctx.path}, 1, 1, false)

      --delete old file
      local ok, err = fscol:delete({_id=ctx.path}, false)
      if not ok then error(err) end

      --decrement old parent nlink and remove child
      local query = {
        ['$unset']={
          ['metadata.children.'..oldfilename:gsub('%.','/')]=""
        }
      }
      if ctx.file.attr.mode.dir then
        query["$inc"] = {
          ['metadata.attr.nlink'] = -1
        }
      end
      local ok, err = fscol:update({
        _id=ctx.ppath
      }, query, 0, 1, false)

      --increment new parent nlink and set child
      local query = {
        ['$set']={
          ['metadata.children.'..newfilename:gsub('%.','/')]=newctx.path
        }
      }
      if ctx.file.attr.mode.dir then
        query["$inc"] = {
          ['metadata.attr.nlink'] = 1
        }
      end
      local ok, err = fscol:update({
        _id=newctx.ppath
      }, query, 0, 1, false)
      ctx.invalidate()
    end
  end

  function fs.remove(ctx)
    local query = {
      ['$unset']={
        ['metadata.children.'..ctx.file.name:gsub('%.','/')]=""
      }
    }
    if ctx.file.attr.mode.dir then
      query["$inc"] = {
        ['metadata.attr.nlink'] = -1
      }
    end
    local ok, err = fscol:update({
      _id=ctx.ppath
    }, query, 0, 1, false)
    if not ok then error(err) end
    local ok, err = data:remove({_id=ctx.path}, 0, 1, false)
    if not ok then error(err) end
    ctx.invalidate()
    return ctx
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
    if ctx.file then
      local res, err = ctx.rawfile:write(buf, offset, false)
      if not res then error(err) end
      return #buf
    end
    return 0
  end

  function fs.fsync(ctx)
    if ctx.rawfile then
      ctx.rawfile:flush()
    end
  end

  function fs.truncate(ctx, size)
    size = size or 0
    local file = ctx.file and ctx.rawfile
    file:flush()
    local lastChunk = math.ceil(size/file.chunk_size)-1
    local ok, err = ccol:delete({files_id=ctx.path, n = {['$gt']=lastChunk}}, false)
    if not ok then error(err) end
    local ok, err = fscol:update({
      _id=ctx.path
    },
    {
      ['$set']={
        length = size
      }
    }, 0, 1, false)
    if not ok then error(err) end
  end

  function fs.read(ctx, size, offset)
    local bytes = nil
    if ctx.file then
      local file = ctx.rawfile
      offset = offset or 0
      size = size or file.file_size
      bytes = file:read(size, offset)
    end
    return bytes or ''
  end

  function fs.setxattr(ctx, xattr)
    local set = {}
    for name, value in pairs(xattr) do
      ctx.file.xattr[name] = value
      set['metadata.xattr.'..name] = value
    end
    local ok, err = fscol:update({
      _id=ctx.path
    },
    {
      ['$set']=set
    }, 0, 1, false)
    if not ok then error(err) end
  end

  function fs.setattr(ctx, attr)
    local set = {}
    for name, value in pairs(attr) do
      if value ~= nil then
        ctx.file.attr[name] = value
        set['metadata.attr.'..name] = value
      end
    end
    local ok, err = fscol:update({
      _id=ctx.path
    },
    {
      ['$set']=set
    }, 0, 1, false)
    if not ok then error(err) end
  end

  function fs.getxattr(ctx, xattr)
    if xattr == nil then
      return ctx.file.xattr
    else
      local ret = {}
      for name in pairs(xattr) do
        ret[name] = ctx.file.xattr[name]
      end
      return ret
    end
  end

  function fs.setmode(ctx, mode)
    ctx.file.attr.mode = mode
    local ok, err = fscol:update({
      _id=ctx.path
    },
    {
      ['$set']={
        ['metadata.attr.mode'] = mode
      }
    }, 0, 1, false)
    if not ok then error(err) end
  end

  function fs.statfs(ctx)
    local q = {["$regex"]="^"..ctx.path..'(/|$)'}
    return {
      bsize = 255*1024,
      blocks = ccol:count({files_id=q}),
      files = fscol:count({_id=q})
    }
  end

  local root = {
    mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }
  }
  local ctx = fs.get('/', {uid=0, gid=0})
  if not ctx.file then
    fs.new(ctx, root)
  end

  return fs
end
