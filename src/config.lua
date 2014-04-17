return {
  db = {
    timeout = 5000,
    host = '127.0.0.1',
    port = 27017,
    database = 'lastfs',
    collection = 'metadata'
  },
  log = {
    dir = "/var/log",
    file = "lastfs.log"
  }
}
