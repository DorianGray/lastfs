#!/usr/bin/env luajit

local folder = debug.getinfo(1).source:gsub('/[^/]+$', ''):match('^@(.*)$')
package.path = folder..'/?.lua;'..package.path

local flu = require 'flu'
local config = require 'config'


local writer = require 'log.writer.file.by_day'.new(config.log.dir, config.log.file, 5000)

local LOG = require "log".new(writer)

local fs = require ('backend.'..config.fs..'.fs')(config, LOG)
LOG.info("LastFs Started")

flu.main({"lastfs", "-o", "allow_other", ...}, require 'fuse.interface'(fs, LOG))
