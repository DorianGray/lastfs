local splitpath   = require 'utilities.fuse'.splitpath

return function(file)

  local lazyctx = {
    path = function(self)
      self.path = '/'..table.concat(self.tpath, '/')
      return self.path
    end,
    tpath = function(self)
      self.tpath = splitpath(self.path)
      return self.tpath
    end,
    file = function(self)
      if file[self.path] then
        self.file = file[self.path]
      else
        return nil
      end
      return self.file
    end,
    tppath = function(self)
      if self.tpath and #self.tpath > 0 then
        self.tppath = {unpack(self.tpath)}
        table.remove(self.tppath)
      else
        return nil
      end
      return self.tppath
    end,
    ppath = function(self)
      if self.tppath then
        self.ppath = '/'..table.concat(self.tppath, '/')
      else
        return nil
      end
      return self.ppath
    end,
    parent = function(self)
      if self.file and self.file.parent then
        self.parent = self.file.parent
      elseif file[self.ppath] then
        self.parent = file[self.ppath]
      else
        return nil
      end
      return self.parent
    end
  }

  local ctxmeta = {
    __index = function(self, key)
      local lazy = lazyctx[key]
      return lazy and lazy(self) or nil
    end
  }

  local function ctx(path, user)
    local ctx = {}
    ctx.user = user
    if type(path) == "string" then
      ctx.path = path
    elseif type(path) == "table" then
      ctx.tpath = path
    end

    function ctx.invalidate()
      ctx.parent  = nil
      ctx.ppath   = nil
      ctx.tppath  = nil
      ctx.file    = nil
    end

    return setmetatable(ctx, ctxmeta)
  end
  return ctx
end
