#!/usr/bin/env luajit
local folder = debug.getinfo(1).source:gsub('/[^/]+$', ''):match('^@(.*)$')
package.path = folder..'/?.lua;'..package.path

local flu = require 'flu'
local handle = require 'errorhandler'

local writer = require 'log.writer.file.by_day'.new('/var/log', 'lastfs.log', 5000)

local LOG = require"log".new(writer)

LOG.info("LastFs Mounted at "..select(1, ...))

local args = {"lastfs", ...}
local fs = require 'fs'
fs.LOG = LOG
flu.main(args, handle(fs))
