
# Dependencies

fs = require 'fs'
url = require 'url'
path = require 'path'
util = require 'util'
mime = require 'mime'
async = require 'async'
crypto = require 'crypto'
cluster = require 'cluster'
{exec} = require 'child_process'

_ = require 'underscore'
_.str = require 'underscore.string'

passport = require 'passport'
strategy = (require 'passport-local').Strategy
mongoose = require 'mongoose'
express = require 'express'

( ->
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
      regex = new RegExp '^'+process.env.ROOTDIR.replace /\//g, '\\/'
      path: src.replace regex, ''
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

  mongoose.connect process.env.MONGODB

  app.sessionStore = new ((require 'connect-mongo') express)
    mongoose_connection: mongoose.connections[0]

  app.disable 'x-powered-by'
  app.set 'port', process.env.PORT
  app.set 'views', path.resolve 'views'
  app.set 'view engine', 'jade'
  app.use (require 'connect-thumbnail')
    path: process.env.ROOTDIR
    cache: path.resolve 'tmp', 'thumb'
  app.use (require 'connect-pdfsplit')
    cache: path.resolve 'tmp', 'pages'
    density: 144
  app.use require 'connect-stream'
  app.use (require 'connect-logger') format: '%status %method %url (%route - %time)'
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser()
  app.use express.session
    secret: process.env.SESSION_SECRET
    store: app.sessionStore
  app.use passport.initialize()
  app.use passport.session()
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
  app.get '/session', (req, res, next) ->
    res.setHeader 'Cache-Control', 'no-cache, no-store, must-revalidate'
    if req.isAuthenticated()
      return res.json 200, req.user
    return res.json 401, {}

  app.post '/session', (req, res, next) ->
    res.setHeader 'Cache-Control', 'no-cache, no-store, must-revalidate'
    if req.isAuthenticated()
      return User.findByName req.body.name, (err, user) ->
        user.mail = mail
        user.save -> res.json 200, user
    return (passport.authenticate 'local') req, res, ->
      if req.isAuthenticated()
        return res.json 201, req.user
      return res.json 401, {}

  app.delete '/session', (req, res, next) ->
    req.logout()
    return res.json 204, {}

  app.get /.*/, (req, res) ->
    unless req.isAuthenticated()
      res.statusCode = 401
      return res.render 'error'
    src = "#{process.env.ROOTDIR}#{decodeURI req._parsedUrl.pathname}"
    if (fs.existsSync src) and (fs.statSync src).isFile()
      if req.query.page and /pdf/.test mime.lookup src
        return res.pdfsplit src, req.query.page
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
  return http.listen app.get 'port'
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
    return accept null, yes unless data.headers?.cookie?
    (express.cookieParser process.env.SESSION_SECRET) data, {}, (err) ->
      return accept err, no if err
      return app.sessionStore.load data.signedCookies['connect.sid'], (err, session) ->
        console.error err if err
        return accept err, no if err
        data.user = session.passport.user if session
        return accept null, yes
  return io
)()

# WebSocket

( ->
  io.sockets.on 'connection', (socket) ->
    session = socket.handshake.user

    socket.on 'init', ->
      socket.emit 'init',
        version: '4.0.2'
        sitename: process.env.SITENAME

    if session
      socket.on 'sync', (conf = no) ->
        User.findById session._id, (err, user) ->
          if user and conf
            user.conf = conf
            return user.save (err, user) ->
              socket.emit 'sync', err, user
          socket.emit 'sync', err, user

      socket.on 'skip', (query) ->
        query.dest or= 'next'
        src = (path.join process.env.ROOTDIR, query.path).split '/'
        src.pop()
        if fs.existsSync src = src.join('/')
          index = 0
          for stat, i in stats = _.stat.map src
            if (String stat.name) is (String query.name)
              index = if query.dest is 'next' then i + 1 else i - 1
              break
          index = stats.length - 1 if 0 > index
          index = 0 if typeof stats[index] is 'undefined'
          return socket.emit 'skip', stats[index]
        return socket.emit 'skip', {}

      socket.on 'next', (src) ->
        try
          src = decodeURI src
        catch e
          src = decodeURI src.replace /%/g, '%25'
        finally

      socket.on 'fetch', (query) ->
        try
          query.path = decodeURI query.path
        catch e
          query.path = decodeURI query.path.replace /%/g, '%25'
        finally
          src = socket.current = path.join process.env.ROOTDIR, query.path
          if !fs.existsSync src
            res = []
          else if query.term is 'stream'
            res = _.reject (_.stat.map src, yes), (stat) -> stat.mime is 'text/directory'
          else if /^search\//.test query.term
            tip = new RegExp (decodeURI query.term.replace /^search\//, ''), 'gi'
            res = _.reject (_.stat.map src, yes), (stat) ->
              return yes unless tip.test stat.name
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
)()
