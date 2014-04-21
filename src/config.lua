return {
  backend = {
    mongo = {
      timeout = 5000,
      host = '127.0.0.1',
      port = 27017,
      database = 'lastfs'
    },
  },
  fs = 'mongo',
  log = {
    dir = "/var/log",
    file = "lastfs.log"
  }
}
