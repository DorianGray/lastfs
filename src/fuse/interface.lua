local flu       = require 'flu'
local bit       = require 'bit'
local ACCESS    = require 'constants.access'
local mkset     = require 'utilities.fuse'.mkset
local assert    = require 'utilities.fuse'.assert
local keys      = require 'utilities.fuse'.keys

local EEXIST    = flu.errno.EEXIST
local EINVAL    = flu.errno.EINVAL
local ENOTDIR   = flu.errno.ENOTDIR
local ENOENT    = flu.errno.ENOENT
local EACCES    = flu.errno.EACCES
local EISDIR    = flu.errno.EISDIR
local ENOATTR   = flu.errno.ENOATTR

local R_OK        = require 'constants.access'.R_OK
local W_OK        = require 'constants.access'.W_OK
local X_OK        = require 'constants.access'.X_OK

return function(fs, LOG)
  local I = {}
  local descriptors = {}

  function I.getattr(path)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    return ctx.file.attr
  end

  function I.mkdir(path, mode)
    local user = flu.get_context()
    local ctx = fs.get(path, user)
    local pctx = fs.get(ctx.ppath, user)
    assert(not ctx.file, EEXIST)
    assert(ctx.parent, ENOENT)
    assert(ctx.parent.attr.mode.dir, ENOTDIR)
    assert(fs.check(pctx, W_OK), EACCES)
    if mode and not mode.dir then mode.dir = true end
    fs.new(ctx, {
      mode = mode or mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' },
    })
  end

  function I.rmdir(path)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(ctx.file.attr.mode.dir, ENOTDIR)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.remove(ctx)
  end

  function I.opendir(path, fi)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(ctx.file.attr.mode.dir, ENOTDIR)
    assert(ctx.file.name or ctx.path == "/", EINVAL)
    fi.fh = #descriptors+1
    descriptors[fi.fh] = ctx
  end

  function I.releasedir(path, fi)
    assert(fi.fh~=0, EINVAL)
    table.remove(descriptors, fi.fh)
  end

  function I.readdir(path, filler, fi)
    assert(fi.fh~=0, EINVAL)
    local ctx = descriptors[fi.fh]
    assert(ctx, EINVAL)
    assert(fs.check(ctx, R_OK + X_OK), EACCES)
    filler(".")
    filler("..")
    for name in pairs(ctx.file.children) do
      filler(name)
    end
  end

  function I.rename(oldpath, newpath)
    local user = flu.get_context()
    local oldctx, newctx = fs.get(oldpath, user), fs.get(newpath, user)
    assert(oldctx.file, ENOENT)
    assert(newctx.parent, ENOENT)
    assert(newctx.parent.attr.mode.dir, ENOTDIR)
    assert(fs.check(oldctx, W_OK), EACCES)
    local newpctx = fs.get(newctx.ppath, user)
    assert(fs.check(newpctx, W_OK), EACCES)
    fs.move(oldctx, newctx)
  end

  function I.mknod(path, mode, dev)
    local user = flu.get_context()
    local ctx = fs.get(path, user)
    assert(not ctx.file, EEXIST)
    assert(ctx.parent, ENOENT)
    assert(ctx.parent.attr.mode.dir, ENOTDIR)
    local pctx = fs.get(ctx.ppath, user)
    assert(fs.check(pctx, W_OK), EACCES)
    fs.new(ctx, {
      mode = mode or mkset{ 'reg', 'rusr', 'wusr', 'rgrp', 'wgrp', 'roth' },
    })
  end

  function I.create(path, mode, fi)
    local user = flu.get_context()
    local ctx = fs.get(path, user)
    assert(not ctx.file, EEXIST)
    assert(ctx.parent, ENOENT)
    assert(ctx.parent.attr.mode.dir, ENOTDIR)
    local pctx = fs.get(ctx.ppath, user)
    assert(fs.check(pctx, W_OK), EACCES)
    fs.new(ctx, {
      mode = mode or mkset{ 'reg', 'rusr', 'wusr', 'rgrp', 'wgrp', 'roth' },
    })
    assert(ctx.file, ENOENT)
    fi.fh = #descriptors+1
    descriptors[fi.fh] = ctx
  end

  function I.unlink(path)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(not ctx.file.attr.mode.dir, EISDIR)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.remove(ctx)
  end

  function I.open(path, fi)
    local ctx = fs.get(path, flu.get_context())
    local file = ctx.file
    assert(file, ENOENT)
    assert(not file.attr.mode.dir, EISDIR)
    fi.fh = #descriptors+1
    descriptors[fi.fh] = ctx
  end

  function I.release(path, fi)
    assert(fi.fh~=0, EINVAL)
    local ctx = descriptors[fi.fh]
    assert(ctx, EINVAL)
    fs.fsync(ctx)
    table.remove(descriptors, fi.fh)
  end

  function I.read(path, size, offset, fi)
    assert(fi.fh~=0, EINVAL)
    local ctx = descriptors[fi.fh]
    assert(ctx, EINVAL)
    if ctx.file.attr.mode.dir then return '' end
    return fs.read(ctx, size, offset)
  end

  function I.write(path, buf, offset, fi)
    assert(fi.fh~=0, EINVAL)
    local ctx = descriptors[fi.fh]
    assert(ctx, EINVAL)
    if ctx.file.attr.mode.dir then return 0 end
    return fs.write(ctx, buf, offset)
  end

  function I.fsync(path, datasync, fi)
    assert(fi.fh~=0, EINVAL)
    local ctx = descriptors[fi.fh]
    assert(ctx, EINVAL)
    fs.fsync(ctx)
  end

  function I.truncate(path, size)
    local ctx = fs.get(path, flu.get_context())
    local file = ctx.file
    assert(file, ENOENT)
    assert(not file.attr.mode.dir, EISDIR)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.truncate(ctx, size)
  end

  function I.utimens(path, accessed, modified)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.setattr(ctx, {
      access = accessed and accessed.sec or os.time(),
      modification = modified and modified.sec or os.time(),
    })
  end

  function I.getxattr(path, name)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(next(ctx.file.xattr) ~= nil, ENOATTR)
    assert(fs.check(ctx, R_OK), EACCES)
    return fs.getxattr(ctx, {[name] = true})[name] or error(ENOATTR)
  end

  function I.setxattr(path, name, value, flags)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, W_OK), EACCES)
    assert(not flags.create or ctx.file.xattr[name] == nil, EEXIST)
    assert(not flags.replace or ctx.file.xattr[name] ~= nil, ENOATTR)
    fs.setxattr(ctx, {[name] = value})
  end

  function I.removexattr(path, name)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(next(ctx.file.xattr) ~= nil, ENOATTR)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.setxattr(ctx, {[name] = nil})
  end

  function I.listxattr(path)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, R_OK), EACCES)
    return keys(fs.getxattr(ctx))
  end

  function I.chown(path, uid, gid)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.setattr(ctx, {uid = uid, gid = gid})
  end

  function I.chmod(path, mode)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.setmode(ctx, mode)
  end

  function I.access(path, mask)
    local ctx = fs.get(path, flu.get_context())
    if not ctx.file then error(ENOENT) end
    return fs.check(ctx, mask) and 0 or error(EACCES)
  end

  return I
end
