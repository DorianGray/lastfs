local flu       = require 'flu'
local bit       = require 'bit'
local ACCESS    = require 'constants.access'
local mkset     = require 'utilities.fuse'.mkset
local keys      = require 'utilities.fuse'.keys
local assert    = require 'utilities.fuse'.assert

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

return function(fs)
  local I = {}
  local descriptors = {}

  function I.getattr(path)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    return ctx.file
  end

  function I.mkdir(path, mode)
    local user = flu.get_context()
    local ctx = fs.get(path, user)
    local pctx = fs.get(ctx.ppath, user)
    assert(not ctx.file, EEXIST)
    assert(ctx.parent, ENOENT)
    assert(ctx.parent.mode.dir, ENOTDIR)
    assert(fs.check(pctx, W_OK), EACCES)
    if mode and not mode.dir then mode.dir = true end
    fs.new(ctx, {
      mode = mode or mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' },
    })
  end

  function I.rmdir(path)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(ctx.file.mode.dir, ENOTDIR)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.remove(ctx)
  end

  function I.opendir(path, fi)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(ctx.file.mode.dir, ENOTDIR)
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
    assert(newctx.parent.mode.dir, ENOTDIR)
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
    assert(ctx.parent.mode.dir, ENOTDIR)
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
    assert(ctx.parent.mode.dir, ENOTDIR)
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
    assert(not ctx.file.mode.dir, EISDIR)
    assert(fs.check(ctx, W_OK), EACCES)
    fs.remove(ctx)
  end

  function I.open(path, fi)
    local ctx = fs.get(path, flu.get_context())
    local file = ctx.file
    assert(file, ENOENT)
    assert(not file.mode.dir, EISDIR)
    fi.fh = #descriptors+1
    descriptors[fi.fh] = ctx
  end

  function I.release(path, fi)
    assert(fi.fh~=0, EINVAL)
    table.remove(descriptors, fi.fh)
  end

  function I.read(path, size, offset, fi)
    assert(fi.fh~=0, EINVAL)
    local ctx = descriptors[fi.fh]
    assert(ctx, EINVAL)
    assert(fs.check(ctx, R_OK), EACCES)
    local file = ctx.file
    if file.mode.dir then return '' end
    local filelen = #file.data
    if offset < filelen then
      if offset + size > filelen then
        size = filelen - offset
      end
      return file.data:sub(offset + 1, offset + size)
    end
    return ''
  end

  function I.write(path, buf, offset, fi)
    assert(fi.fh~=0, EINVAL)
    local ctx = descriptors[fi.fh]
    assert(ctx, EINVAL)
    assert(fs.check(ctx, W_OK), EACCES)
    local file = ctx.file
    if file.mode.dir then return 0 end
    local buflen = #buf
    local filelen = #file.data
    if offset < filelen then
      if offset + buflen >= filelen then
        file.size = offset + buflen - 1
        file.data = file.data:sub(1,offset)..buf
      else
        file.data = file.data:sub(1,offset)..buf..file.data:sub(offset+buflen)
      end
    else
      file.size = offset + buflen - 1
      file.data = file.data..string.rep('\0', offset-filelen)..buf
    end
    return #buf
  end

  function I.truncate(path, size)
    local ctx = fs.get(path, flu.get_context())
    local file = ctx.file
    assert(file, ENOENT)
    assert(not file.mode.dir, EISDIR)
    assert(fs.check(ctx, W_OK), EACCES)
    local filename = file.name
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

  function I.utimens(path, accessed, modified)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, W_OK), EACCES)
    local st = ctx.file
    st.access = accessed and accessed.sec or os.time()
    st.modification = modified and modified.sec or os.time()
  end

  function I.getxattr(path, name)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    local attrs = ctx.file.xattrs or error(ENOATTR)
    assert(fs.check(ctx, R_OK), EACCES)
    return attrs[name] or error(ENOATTR)
  end

  function I.setxattr(path, name, value, flags)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, W_OK), EACCES)
    local attrs = ctx.file.xattrs
    if not attrs then
      attrs = {}
      ctx.file.xattrs = attrs
    end
    attrs[name] = value
  end

  function I.removexattr(path, name)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    local attrs = ctx.file.xattrs or error(ENOATTR)
    assert(fs.check(ctx, W_OK), EACCES)
    attrs[name] = nil
    if next(attrs)==nil then
      ctx.file.xattrs = nil
    end
  end

  function I.listxattr(path)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, R_OK), EACCES)
    return keys(ctx.file.xattrs)
  end

  function I.chown(path, uid, gid)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, W_OK), EACCES)
    ctx.file.uid = uid
    ctx.file.gid = gid
  end

  function I.chmod(path, mode)
    local ctx = fs.get(path, flu.get_context())
    assert(ctx.file, ENOENT)
    assert(fs.check(ctx, W_OK), EACCES)
    ctx.file.mode = mode
  end

  function I.access(path, mask)
    local ctx = fs.get(path, flu.get_context())
    if not ctx.file then error(ENOENT) end
    return fs.check(ctx, mask) and 0 or error(EACCES)
  end

  return I
end
