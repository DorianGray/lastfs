local fs = {}
fs.LOG = {} --stub

local flu = require 'flu'
local bit = require 'bit'
local access = require 'access'
local errno = flu.errno

local function mkset(array)
  local set = {}
  for _,flag in ipairs(array) do
    set[flag] = true
  end
  return set
end

local assert = function(...)
  local value,err = ...
  if not value then
    error(err, 2)
  else
    return ...
  end
end

local attr = {
  ['/'] = {
    uid = 0,
    gid = 0,
    size = 4096,
    nlink = 2,
    mode = mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' }
  }
}

local xattrs = {}
-- :NOTE: since the filesystem is a pure tree (not a DAG), use the path to find attribs

local root = {}

local function splitpath(path)
  local elements = {}
  for element in path:gmatch("[^/]+") do
    table.insert(elements, element)
  end
  return elements
end

local function getfile(apath)
  local path = apath
  if type(path) == "string" then
    path = splitpath(path)
  end
  local node = root
  local parent = nil
  for _,file in ipairs(path) do
    if type(node)~='table' then return nil end
    parent = node
    node = node[file]
    if not node then break end
  end
  return node, parent
end

function fs.getattr(apath)
  local path = apath
  local file = getfile(path)
  if file then
    if type(path) == "table" then
      path = '/'..table.concat(path, '/')
    end
    local st = attr[path]
    if not st then
      error(errno.EINVAL)
    end
    return st
  else
    error(errno.ENOENT)
  end
end

local descriptors = {}

function fs.mkdir(path, mode)
  local file, parent = getfile(path)
  assert(not file, errno.EEXIST)
  assert(parent, errno.ENOENT)
  local tpath = splitpath(path)
  local filename = tpath[#tpath] or error(errno.EINVAL)
  assert(type(parent)=='table', errno.ENOTDIR)
  local file = {}
  table.remove(tpath)
  fs.access(tpath, access.W_OK)
  parent[filename] = file
  local pattr = fs.getattr(tpath)
  pattr.nlink = pattr.nlink+1

  local context = flu.get_context()
  if mode and not mode.dir then mode.dir = true end
  attr[path] = {
    nlink = 2,
    size = 4096,
    mode = mode or mkset{ 'dir', 'rusr', 'wusr', 'xusr', 'rgrp', 'wgrp', 'xgrp', 'roth', 'xoth' },
    uid = context.uid,
    gid = context.gid,
    access = os.time(),
    modification = os.time()
  }
end

function fs.rmdir(path)
  local file,parent = getfile(path)
  assert(file, errno.ENOENT)
  assert(type(file)=='table', errno.ENOTDIR)
  local tpath = splitpath(path)
  local filename = tpath[#tpath] or error(errno.EINVAL)
  fs.access(tpath, access.W_OK)
  table.remove(tpath)
  local pattr = fs.getattr(tpath)
  pattr.nlink = pattr.nlink-1
  parent[filename] = nil
  attr[path] = nil
  xattrs[path] = nil
end

function fs.opendir(path, fi)
  local file, parent = getfile(path)
  assert(file, errno.ENOENT)
  assert(type(file)=='table', errno.ENOTDIR)
  local tpath = splitpath(path)
  local filename = tpath[#tpath]
  if not filename and path~="/" then
    error(errno.EINVAL)
  end
  fi.fh = #descriptors+1
  descriptors[fi.fh] = {path=path, parent=parent, filename=filename, file=file}
end

function fs.releasedir(path, fi)
  assert(fi.fh~=0, errno.EINVAL)
  table.remove(descriptors, fi.fh)
end

function fs.readdir(path, filler, fi)
  assert(fi.fh~=0, errno.EINVAL)
  fs.access(path, access.R_OK)
  local file = descriptors[fi.fh].file
  filler(".")
  filler("..")
  for name in pairs(file) do
    filler(name)
  end
end

function fs.rename(oldpath, newpath)
  local old = splitpath(oldpath)
  local new = splitpath(newpath)
  local oldparent, oldname
  local oldnode = root
  for _, v in ipairs(old) do
    if type(oldnode)~='table' then error(errno.ENOENT) end
    oldparent = oldnode
    oldnode = oldnode[v]
    oldname = v
    if not oldnode then error(errno.ENOENT) end
  end

  local newparent, newname
  local newnode = root
  for _, v in ipairs(new) do
    if type(newnode)~='table' then error(errno.ENOENT) end
    newparent = newnode
    newnode = newnode[v]
    newname = v
  end

  table.remove(new)
  fs.access(old, access.W_OK)
  fs.access(new, access.W_OK)
  table.remove(old)

  local oldparentattr = fs.getattr(old)
  local newparentattr = fs.getattr(new)

  oldparentattr.nlink = oldparentattr.nlink - 1
  newparentattr.nlink = newparentattr.nlink + 1

  attr[newpath] = attr[oldpath]
  attr[oldpath] = nil
  xattrs[newpath] = xattrs[oldpath]
  xattrs[oldpath] = nil
  oldparent[oldname] = nil
  newparent[newname] = oldnode
end

function fs.mknod(path, mode, dev)
  local file, parent = getfile(path)
  assert(not file, errno.EEXIST)
  assert(parent, errno.ENOENT)
  local tpath = splitpath(path)
  local filename = tpath[#tpath] or error(errno.EINVAL)
  assert(type(parent)=='table', errno.ENOTDIR)
  table.remove(tpath)
  fs.access(tpath, access.W_OK)
  local file = ""
  parent[filename] = file
  local context = flu.get_context()
  attr[path] = {
    size = 0,
    nlink = 1,
    mode = mode or mkset{ 'reg', 'rusr', 'wusr', 'rgrp', 'wgrp', 'roth' },
    uid = context.uid,
    gid = context.gid,
    access = os.time(),
    modification = os.time()
  }
end

function fs.create(path, mode, fi)
  fs.mknod(path, mode, 'file')
  fs.open(path, fi)
end

function fs.unlink(path)
  local file, parent = getfile(path)
  assert(file, errno.ENOENT)
  assert(type(file)~='table', errno.EISDIR)
  local tpath = splitpath(path)
  local filename = tpath[#tpath] or error(errno.EINVAL)
  fs.access(tpath, access.W_OK)
  parent[filename] = nil
  attr[path] = nil
  xattrs[path] = nil
end

function fs.open(path, fi)
  local file, parent = getfile(path)
  assert(file, errno.ENOENT)
  assert(type(file)~='table', errno.EISDIR)
  local tpath = splitpath(path)
  local filename = tpath[#tpath] or error(errno.EINVAL)
  fi.fh = #descriptors+1
  descriptors[fi.fh] = {path=path, parent=parent, filename=filename, file=file}
end

function fs.release(path, fi)
  assert(fi.fh~=0, errno.EINVAL)
  descriptors[fi.fh] = nil
end

function fs.read(path, size, offset, fi)
  assert(fi.fh~=0, errno.EINVAL)
  fs.access(path, access.R_OK)
  local file = descriptors[fi.fh].file
  if type(file)=='string' then
    local filelen = #file
    if offset<filelen then
      if offset + size > filelen then
        size = filelen - offset
      end
      return file:sub(offset+1, offset+size)
    end
  end
  return ''
end

function fs.write(path, buf, offset, fi)
  fs.access(path, access.W_OK)
  assert(fi.fh~=0, errno.EINVAL)
  local descriptor = descriptors[fi.fh]
  local file, filename, parent = descriptor.file,descriptor.filename,descriptor.parent
  if type(file)=='string' then
    local buflen = #buf
    local filelen = #file
    if offset<filelen then
      if offset + buflen >= filelen then
        file = file:sub(1,offset)..buf
      else
        file = file:sub(1,offset)..buf..file:sub(offset+buflen)
      end
    else
      file = file..string.rep('\0', offset-filelen)..buf
    end
    attr[path].size = file:len()
    parent[filename] = file
    descriptor.file = file
    return #buf
  else
    return 0
  end
end

-- truncate is necessary to rewrite a file
function fs.truncate(path, size)
  local file,parent = getfile(path)
  assert(file, errno.ENOENT)
  assert(type(file)~='table', errno.EISDIR)
  local tpath = splitpath(path)
  fs.access(tpath, access.W_OK)
  local filename = tpath[#tpath] or error(errno.EINVAL)
  local len = #file
  if size > len then
    parent[filename] = file..string.rep('\0', size - len)
  else
    parent[filename] = file:sub(1, size)
  end
  attr[path].size = size
end

-- utimens necessary for 'touch'
function fs.utimens(path, accessed, modified)
  fs.access(path, access.W_OK)
  local st = attr[path]
  st.access = accessed and accessed.sec or os.time()
  st.modification = modified and modified.sec or os.time()
end

function fs.getxattr(path, name)
  local attrs = xattrs[path] or error(errno.ENOATTR)
  fs.access(path, access.R_OK)
  return attrs[name] or error(errno.ENOATTR)
end

function fs.setxattr(path, name, value, flags)
  fs.access(path, access.W_OK)
  local attrs = xattrs[path]
  if not attrs then
    attrs = {}
    xattrs[path] = attrs
  end
  attrs[name] = value
end

function fs.removexattr(path, name)
  local attrs = xattrs[path] or error(errno.ENOATTR)
  fs.access(path, access.W_OK)
  attrs[name] = nil
  if next(attrs)==nil then
    xattrs[path] = nil
  end
end

function fs.listxattr(path)
  fs.access(path, access.R_OK)
  local attrs = xattrs[path]
  if attrs then
    local names = {}
    for name in pairs(attrs) do
      table.insert(names, name)
    end
    return names
  else
    return {}
  end
end

function fs.chown(path, uid, gid)
  fs.access(path, access.W_OK)
  local st = attr[path]
  st.uid = uid
  st.gid = gid
end

function fs.chmod(path, mode)
  fs.access(path, access.W_OK)
  attr[path].mode = mode
end

function fs.access(path, mask)
  local file = getfile(path)
  if not file then error(errno.ENOENT) end
  if mask == 0 then return 0 end

  local context = flu.get_context()
  if context.uid == 0 then return 0 end

  local st = fs.getattr(path)

  local R_REQ = bit.band(mask, access.R_OK) == access.R_OK
  local W_REQ = bit.band(mask, access.W_OK) == access.W_OK
  local X_REQ = bit.band(mask, access.X_OK) == access.X_OK

  if st.uid == context.uid then
    if  (not R_REQ or st.mode.rusr) and
        (not W_REQ or st.mode.wusr) and
        (not X_REQ or st.mode.xusr) then
      return 0
    end
  end

  if st.gid == context.gid then
    if  (not R_REQ or st.mode.rgrp) and
        (not W_REQ or st.mode.wgrp) and
        (not X_REQ or st.mode.xgrp) then
      return 0
    end
  end

  if  (not R_REQ or st.mode.roth) and
      (not W_REQ or st.mode.woth) and
      (not X_REQ or st.mode.xoth) then
    return 0
  end

  error(errno.EACCES)
end

return fs
