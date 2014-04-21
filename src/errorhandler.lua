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
          local args = {...}
          --LOG.info(key.." - "..(type(args[1]) == "string" and args[1] or ""))
          local res = {
            xpcall(
              function() return v(unpack(args)) end,
              function(message)
                if type(message) == "userdata" then return message end
                if type(message) == "string" then
                  LOG.error(debug.traceback(message, 2))
                else
                  LOG.error(debug.traceback("", 2))
                end
                return flu.errno.EFAULT
              end
            )
          }
          local ok = res[1]
          local err = res[2]
          if not ok and err then
            error(err)
          end
          if #res > 1 then
            return unpack(res, 2)
          end
        end
        return cache[key]
      end
      return v
    end
  }
  return setmetatable({}, meta)
end
