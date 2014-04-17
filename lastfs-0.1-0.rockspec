package = "lastfs"
version = "0.1-0"
source = {
  url = "https://github.com/DorianGray/lastfs/archive/v0.1.tar.gz",
  dir = "lastfs-0.1"
}
description = {
  summary = "Fast distributed database.",
  detailed = [[
    Fast distributed database.
  ]],
  homepage = "http://olivinelabs.com/lastfs/",
  license = "MIT <http://opensource.org/licenses/MIT>"
}
dependencies = {
  "lua >= 5.1",
  "log-lua >= 1.3-1",
  "resty-mongol >= 0.7-3",
  "luasocket >= 3.0rc1-1",
  "md5 >= 1.1.2-2",
  "busted >= 1.7-1"
}
build = {
  type = "builtin",
  modules = {
    ["lastfs.init"]                     = "src/init.lua",
    ["lastfs.fs"]                       = "src/fs.lua",
    ["lastfs.config"]                   = "src/config.lua",
    ["lastfs.constants.access"]         = "src/constants/access.lua",
 }
}
