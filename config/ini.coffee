fs = require 'fs'
path = require 'path'
mkdirp = require 'mkdirp'

unless fs.existsSync path.resolve 'tmp', 'thumb'
  mkdirp.sync path.resolve 'tmp', 'thumb'
