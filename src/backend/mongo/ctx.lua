return function(data)

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
      local file = data:find_one({_id=self.path})
      if file then
        self.rawfile = file
        self.file = file.file_metadata
        self.file.attr.size = file.file_size
        if self.file.children then
          local newchildren = {}
          for key, value in pairs(self.file.children) do
            local newkey = key:gsub('/', '.')
            newchildren[newkey] = value
          end
          self.file.children = newchildren
        end
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
      local file = self.path ~= '/' and data:find_one({_id=self.ppath})
      if file then
        self.rawparent = file
        self.parent = file.file_metadata
        self.parent.attr.size = file.file_size
        if self.parent.children then
          local newchildren = {}
          for key, value in pairs(self.parent.children) do
            local newkey = key:gsub('/', '.')
            newchildren[newkey] = value
          end
          self.parent.children = newchildren
        end
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
      ret.parent    = nil
      ret.rawparent = nil
      ret.ppath     = nil
      ret.tppath    = nil
      ret.file      = nil
      ret.rawfile   = nil
    end

    return setmetatable(ret, ctxmeta)
  end
  return ctx
end
