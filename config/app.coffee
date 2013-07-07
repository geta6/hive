# Dependencies

fs = require 'fs'
path = require 'path'
util = require 'util'
mime = require 'mime'
meta = require 'musicmetadata'
async = require 'async'
crypto = require 'crypto'
cluster = require 'cluster'
{exec, spawn} = require 'child_process'

passport = require 'passport'
strategy = (require 'passport-local').Strategy
mongoose = require 'mongoose'
express = require 'express'

# Env

( ->
  process.env.ROOTDIR = '/media/var'
  process.env.CYPHERS = 'keyboardcat'

  global._ = require 'underscore'
  _.str = require 'underscore.string'
  _.date = require 'moment'

  _.util =
    sha1sum: (src) ->
      crypto.createHash('sha1').update(src).digest('hex')
    execsafe: (src) ->
      src.replace(/'/g, "'\\''")

  _.stat =
    map: (src, recursive = no) ->
      return _.stat.status src unless (fs.statSync src).isDirectory()
      list = _.stat.listup src, recursive
      list = _.reject list, (src) -> return _.stat.reject src
      return _.map list, (src) -> _.stat.status src
    reject: (src) ->
      return /^(\.DS.+|Network Trash Folder|Temporary Items|\.Apple.*)$/.test src
    status: (src) ->
      stat = fs.statSync src
      path: src.replace /^\/media\/var/, ''
      name: path.basename src
      mime: if stat.isDirectory() then 'text/directory' else mime.lookup src
      size: if stat.isDirectory() then (_.reject (fs.readdirSync src), (src) -> _.stat.reject src).length else stat.size
      time: stat.mtime
    listup: (src, recursive = no) ->
      return src unless (fs.statSync src).isDirectory()
      data = []
      list = _.reject (fs.readdirSync src), (src) -> _.stat.reject src
      for file in list
        data.push next = path.join src, file
        if fs.statSync(next).isDirectory() and recursive
          data = data.concat arguments.callee next, recursive
      return data
)()

# Application

app = ( ->
  app = express()

  mongoose.connect 'mongodb://localhost/media'

  app.sessionStore = new ((require 'connect-mongo') express)
    mongoose_connection: mongoose.connections[0]

  app.disable 'x-powered-by'
  app.set 'port', process.env.PORT
  app.set 'views', path.resolve 'views'
  app.set 'view engine', 'jade'
  app.use (require 'connect-thumbnail')
    path: '/media/var'
    cache: path.resolve 'tmp', 'thumb'
  app.use express.logger format: 'dev'
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser()
  app.use express.session
    secret: process.env.CYPHERS
    store: app.sessionStore
  app.use passport.initialize()
  app.use passport.session()
  app.use require 'connect-stream'
  app.use app.router
  app.use (err, req, res, next) ->
    console.error "ERROR: #{err.message}"
    res.statusCode = 500
    return res.render 'error'
  app.use (req, res) ->
    res.statusCode = 404 if res.statusCode is 200
    return res.render 'error'
  return app
)()

# Database

{User} = ( ->
  UserSchema = new mongoose.Schema
    name: { type: String, unique: yes, index: yes }
    mail: { type: String }
    conf: { type: mongoose.Schema.Types.Mixed }

  UserSchema.statics.findByName = (name, callback) ->
    @findOne name: name, {}, {}, (err, user) ->
      console.error err if err
      return callback err, user

  return {
    User: mongoose.model 'users', UserSchema
  }
)()

# Authentication

( ->
  passport.serializeUser (user, done)   ->
    done null, user

  passport.deserializeUser (user, done) ->
    User.findById user._id, (err, user) ->
      return (done err, no) unless user
      return done err, user

  passport.use new strategy (username, password, done) ->
    pycode = """
      from draxoft.auth import pam
      h = pam.handle()
      h.user = '#{username}'
      h.conv = lambda style,msg,data: '#{password}'
      print h.authenticate(),
      """
    exec "python -c \"#{pycode}\"", (err, stdout, stderr) ->
      console.error err if err
      stdout = (eval (_.str.trim stdout).toLowerCase())
      unless (success = if err then no else stdout)
        return setTimeout (-> return done err, no), 2500 unless success
      User.findByName username, (err, user) ->
        unless user
          user = new User { name: username, mail: '' }
          user.conf = { view: 'lines', sort: '-time' }
        return user.save done
)()

# Routing

( ->
  app.all '/session', (req, res, next) ->
    res.setHeader 'Cache-Control', 'no-cache, no-store, must-revalidate'
    switch req.method
      when 'POST'
        if req.isAuthenticated()
          User.findByName req.body.name, (err, user) ->
            user.mail = mail
            user.save -> res.json 200, user
        else
          return (passport.authenticate 'local') req, res, ->
            if req.isAuthenticated()
              return res.json 201, req.user
            return res.json 401, {}
      when 'DELETE'
        req.logout()
        return res.json 204, {}
      else
        if req.isAuthenticated()
          return res.json 200, req.user
        return res.json 401, {}

  app.get /.*/, (req, res) ->
    unless req.isAuthenticated()
      res.statusCode = 401
      return res.render 'error'
    src = "/media/var#{decodeURI req._parsedUrl.pathname}"
    if (fs.existsSync src) and (fs.statSync src).isFile()
      return res.stream src
    res.statusCode = 404
    return res.render 'error'
)()

# Export

if cluster.isMaster
  return module.exports = exports = app

# Servers

http = ( ->
  http = (require 'http').createServer app
  http.listen app.get 'port'
  return http
)()

io = ( ->
  redis = require 'socket.io/node_modules/redis'
  io = (require 'socket.io').listen http, log: no
  io.set 'store', new (require 'socket.io/lib/stores/redis')
    redisPub: redis.createClient()
    residSub: redis.createClient()
    redisClient: redis.createClient()
  io.set 'browser client minification', yes
  io.set 'browser client etag', yes
  io.set 'authorization', (data, accept) ->
    data.user = {}
    unless data.headers?.cookie?
      return accept null, no
    (express.cookieParser process.env.CYPHERS) data, {}, (err) ->
      return accept err, no if err
      return app.sessionStore.load data.signedCookies['connect.sid'], (err, session) ->
        console.error err if err
        return accept err, no if err
        if session
          data.user = session.passport.user
        return accept null, yes
  return io
)()

# WebSocket

( ->
  io.sockets.on 'connection', (socket) ->
    session = socket.handshake.user

    if session
      socket.on 'fetch', (query) ->
        query.path = decodeURI query.path
        src = socket.current = path.join '/media', 'var', query.path
        if !fs.existsSync src
          res = []
        else if query.term is 'stream'
          res = _.reject (_.stat.map src, yes), (stat) -> stat.mime is 'text/directory'
        else
          res = _.stat.map src, no
        if _.isArray res
          res = _.sortBy res, (stat) ->
            return stat.time if /time/.test query.sort
            return stat.name if /name/.test query.sort
          res.reverse() if '-' is query.sort.substr 0, 1
          if query.term is 'stream'
            res = res.slice 0, 50
        socket.emit 'start', { query: query, length: res.length }
        if _.isArray res
          unless 0 < res.length
            socket.emit 'error', new Error 'no result'
            return socket.emit 'end'
          for stat, index in res
            do (stat, index, src) ->
              setTimeout ->
                if socket.current is src
                  socket.emit 'data', _.defaults stat, query
                  socket.emit 'end' if index + 1 is res.length
              , 3 * index
        else
          socket.emit 'end', _.defaults res, query

      socket.on 'sync', (conf = no) ->
        console.log "sync from #{session.name}"
        User.findById session._id, (err, user) ->
          if user and conf
            user.conf = conf
            return user.save (err, user) ->
              socket.emit 'sync', err, user
          socket.emit 'sync', err, user
)()
