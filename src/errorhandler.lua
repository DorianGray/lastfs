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
          if LOG then LOG.info(key.." - "..(type(args[1]) == "string" and args[1] or "")) end
          local res = {
            xpcall(
              function() return v(unpack(args)) end,
              function(message)
                if type(message) == "userdata" then
                  local found = false
                  for k, v in pairs(flu.errno) do
                    if v == message then
                      found = true
                      if LOG then LOG.info(key..' returned '..k) end
                      break
                    end
                  end
                  return message
                end
                if type(message) == "string" then
                  if LOG then LOG.error(debug.traceback(message, 2)) end
                else
                  if LOG then LOG.error(debug.traceback("", 2)) end
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
            if LOG then LOG.info(require 'cjson'.encode(unpack(res, 2))) end
            return unpack(res, 2)
          end
          if LOG then LOG.info("null") end
        end
        return cache[key]
      end
      return v
    end
  }
  return setmetatable({}, meta)
end
