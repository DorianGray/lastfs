local mongo = require "resty-mongol"
return function(config)
  local conn = mongo()
  conn:set_timeout(config.timeout)
  local ok, err = conn:connect(config.host, config.port)

  if not ok then
    error(err)
  end

  local db = conn:new_db_handle(config.database)

  if config.secure then
    ok, err = db:auth(config.username, config.password)

    if not ok then
      error(err)
    end
  end

  return db:get_col(config.collection)
end
