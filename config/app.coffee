
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
    return res.end err.message
  return app
)()

# Database

{User, Note} = ( ->
  UserSchema = new mongoose.Schema
    name: { type: String, unique: yes, index: yes }
    conf: { type: mongoose.Schema.Types.Mixed }

  NoteSchema = new mongoose.Schema
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'users' }
    path: { type: String }
    type: { type: String }
    body: { type: String, default: '' }
    date: { type: Date }

  UserSchema.statics.findByName = (name, callback) ->
    @findOne name: name, {}, {}, (err, user) ->
      console.error err if err
      return callback err, user

  NoteSchema.statics.findByUser = (id, which, callback) ->
    query = user: id
    query.type = which if which
    @findOne query, {}, {}, (err, acts) ->
      console.error err if err
      return callback err, acts

  NoteSchema.statics.findByPath = (name, which, callback) ->
    query = path: name
    query.type = which if which
    @findOne query, {}, {}, (err, acts) ->
      console.error err if err
      return callback err, acts

  NoteSchema.pre 'save', (done) ->
    @date = new Date
    return done()

  User: mongoose.model 'users', UserSchema
  Note: mongoose.model 'notes', NoteSchema
)()

# Authentication

( ->
  passport.serializeUser (user, done) ->
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
      stdout = (eval (String stdout).trim().toLowerCase())
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
    return (res.json 401, {}) unless req.isAuthenticated()
    return res.json 200, req.user

  app.post '/session', (req, res, next) ->
    res.setHeader 'Cache-Control', 'no-cache, no-store, must-revalidate'
    (passport.authenticate 'local') req, res, ->
      return (res.json 201, req.user) if req.isAuthenticated()
      return res.json 401, {}

  app.delete '/session', (req, res, next) ->
    req.logout()
    return res.json 204, {}

  app.get /\/(.*)\.thumbnail$/, (req, res) ->
    ext = path.extname res._thumbnail.name
    res.redirect switch true
      when /(zip|lzh|rar|txz|tgz|gz)/i.test ext  then '/img/archive.png'
      when /(mdf|mds|cdr|iso|bin|dmg)/i.test ext then '/img/discimage.png'
      when /(app|exe)/i.test ext                 then '/img/application.png'
      when /(mp3|wav|wma)/i.test ext             then '/img/audio.png'
      when /(txt|md|rtf|sh)/i.test ext           then '/img/text.png'
      when /(ttf|otf)/i.test ext                 then '/img/font.png'
      else                                            '/img/unknown.png'

  app.get /.*/, (req, res) ->
    unless req.isAuthenticated()
      res.statusCode = 401
      return res.end 'Unauthorized'
    src = "#{process.env.ROOTDIR}#{decodeURI req._parsedUrl.pathname}"
    if (fs.existsSync src) and (fs.statSync src).isFile()
      if req.query.page and /\.pdf$/.test src
        return res.pdfsplit src, req.query.page
      return res.stream src
    res.statusCode = 404
    return res.end 'Not Found'
)()

# Export

return (module.exports = exports = app) if cluster.isMaster

# HTTP Server

http = ( ->
  http = (require 'http').createServer app
  return http.listen app.get 'port'
)()

# WebSocket Server

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

# Stat

( ->
  _.stat =
    mapdir: (src, recursive = no) ->
      return _.stat.status src unless (fs.statSync src).isDirectory()
      list = _.stat.listup src, recursive
      list = _.reject list, (src) -> return _.stat.reject src
      return _.map list, (src) -> _.stat.status src
    reject: (src) ->
      return /^(\.DS.+|Network Trash Folder|Temporary Items|\.Apple.*|Thumbs.db)$/i.test src
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

# WebSocket

( ->
  io.sockets.on 'connection', (socket) ->
    session = socket.handshake.user
    pkginfo = require path.resolve 'package.json'

    socket.on 'init', ->
      socket.emit 'init', session, pkginfo

    if session
      socket.on 'sync', (conf = {}) ->
        User.findById session._id, (err, user) ->
          user.conf = _.defaults conf, user.conf
          user.save -> socket.emit 'sync', user

      socket.on 'note', (type, body, data) ->
        note = new Note
          user: session._id
          path: data.path
          type: type
          body: body
          date: new Date
        note.save -> socket.emit 'note', note

      socket.on 'next', (data) ->
        src = path.dirname path.join process.env.ROOTDIR, data.path
        if fs.existsSync src
          index = i + 1 for stat, i in (stats = _.stat.mapdir src) when stat.name is data.name
          index = 0 if typeof stats[index] is 'undefined'
          return socket.emit 'skip', stats[index]
        return socket.emit 'skip', {}

      socket.on 'prev', (data) ->
        src = path.dirname path.join process.env.ROOTDIR, data.path
        if fs.existsSync src
          index = i - 1 for stat, i in (stats = _.stat.mapdir src) when stat.name is data.name
          index = 0 if typeof stats[index] is 'undefined'
          return socket.emit 'skip', stats[index]
        return socket.emit 'skip', {}

      socket.on 'fetch', (query) ->
        try
          src = socket.current = path.join process.env.ROOTDIR, query.path
          unless fs.existsSync src
            socket.emit 'start', { query: query, length: 0 }
            socket.emit 'error', 'No exists.'
            socket.emit 'end', null
          else if (fs.statSync src).isDirectory()
            if query.term is 'stream'
              res = _.reject (_.stat.mapdir src, yes), (stat) -> stat.mime is 'text/directory'
            else if /^search/.test query.term
              reg = new RegExp (decodeURI query.term.replace /^search\//, ''), 'gi'
              res = _.reject (_.stat.mapdir src, yes), (stat) -> yes unless reg.test stat.name
            else
              res = _.stat.mapdir src, no
            if res.length is 0
              socket.emit 'error', 'No result.'
              socket.emit 'end'
            else
              res = (_.sortBy res, (stat) -> stat.time) if 'time' is query.sort.slice 1, 5
              res = (_.sortBy res, (stat) -> stat.name) if 'name' is query.sort.slice 1, 5
              res = res.reverse() if '-' is query.sort.slice 0, 1
              res = (res.slice 0, 50) if 'stream' is query.term or /^search/.test query.term
              socket.emit 'start', { query: query, length: res.length }
              for stat, index in res
                do (stat, index, src) ->
                  setTimeout ->
                    if socket.current is src
                      socket.emit 'data', _.defaults stat, query
                      socket.emit 'end' if index + 1 is res.length
                  , 3 * index
          else
            socket.emit 'start', { query: query, length: 0 }
            socket.emit 'end', _.defaults (_.stat.status src), query
        catch e
          socket.emit 'start', { query: query, length: 0 }
          socket.emit 'error', 'Currently maintenance.'
          console.error e.stack

)()
