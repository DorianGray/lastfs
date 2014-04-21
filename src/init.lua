#!/usr/bin/env luajit

local folder = debug.getinfo(1).source:gsub('/[^/]+$', ''):match('^@(.*)$')
package.path = folder..'/?.lua;'..package.path

local flu = require 'flu'
local handle = require 'errorhandler'
local config = require 'config'

local writer = require 'log.writer.file.roll'.new(config.log.dir, config.log.file, 5000)
local LOG = require"log".new(writer)

local fs = require ('backend.'..config.fs..'.fs')(config, LOG)

LOG.info("LastFs Mounted at "..select(1, ...))

local args = {"lastfs", "-o", "allow_other", ...}

local interface = require 'fuse.interface'(fs, LOG)
flu.main(args, handle(interface, LOG))
