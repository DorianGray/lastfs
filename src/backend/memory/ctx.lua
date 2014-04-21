return function(file)

  local lazyctx = {
    path = function(self)
      self.path = '/'..table.concat(self.tpath, '/')
      return self.path
    end,
    tpath = function(self)
      local tpath = {}
      self.path:gsub("([^/]+)", function(c) tpath[#tpath+1] = c end)
      self.tpath = tpath
      return tpath
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
      local tpath = self.tpath
      if tpath and #tpath > 0 then
        self.tppath = {unpack(tpath, 1, #tpath - 1)}
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
      if file[self.ppath] then
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
    local ret = {}
    ret.user = user
    if type(path) == "string" then
      ret.path = path
    elseif type(path) == "table" then
      ret.tpath = path
    end

    function ret.invalidate()
      ret.parent  = nil
      ret.ppath   = nil
      ret.tppath  = nil
      ret.file    = nil
    end

    return setmetatable(ret, ctxmeta)
  end
  return ctx
end
