local flu = require 'flu'

return function(fs, LOG)
  local cache = {}
  local meta = {
    __index = function(self, key)
      local v = cache[key]
      if v then return v end
      v = fs[key]
      if type(v) == 'function' then

        cache[key] = function(...)

          LOG.info(key)
          local res = {pcall(v, ...)}
          local ok = res[1]
          if not ok then
            local err = res[2]
            local errType = type(err)
            if errType == "userdata" then
              error(err)
            end
            if errType == "string" then
              LOG.error(err)
            else
              LOG.error("An error occurred that could not be logged")
            end
            error(flu.errno.EFAULT)
          end
          table.remove(res, 1)
          return unpack(res)
        end
        return cache[key]
      end
      return v
    end
  }
  return setmetatable({}, meta)
end
