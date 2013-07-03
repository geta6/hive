# Dependencies

fs = require 'fs'
path = require 'path'
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
    gravatar: (mail, size = 80) ->
      hash = crypto.createHash('md5').update(_.str.trim mail.toLowerCase()).digest('hex')
      "//www.gravatar.com/avatar/#{hash}?size=#{size}"
    md5sum: (src) ->
      crypto.createHash('md5').update(src).digest('hex')
    sha1sum: (src) ->
      crypto.createHash('sha1').update(src).digest('hex')
    execsafe: (src) ->
      src.replace(/'/g, "'\\''")
    reject: (srcs) ->
      _.reject srcs, (src) ->
        return yes if /^(\.DS.+|Network Trash Folder|Temporary Items|\.Apple.*)$/.test src
        return yes if src.length is 0
    datasize: (size, i = 0) ->
      units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
      ++i while (size/=1024) >= 1024
      return "#{size.toFixed(1)} #{units[i+1]}"
    status: (src) ->
      stat = fs.statSync src
      if stat.isDirectory()
        stat.size = (_.util.reject fs.readdirSync src).length
        stat.mime = 'text/directory'
      else
        stat.mime = mime.lookup path.basename src
      path: src.replace /^\/media\/var/, ''
      name: path.basename src
      mime: stat.mime
      size: stat.size
      time: stat.mtime
)()

# Application

app = ( ->
  app = express()

  app.sessionStore = new ((require 'connect-redis') express)
    db: 1
    prefix: 'session'

  app.disable 'x-powered-by'
  app.set 'port', process.env.PORT
  app.set 'views', path.resolve 'views'
  app.set 'view engine', 'jade'
  app.use (req, res, next) ->
    req._startTime = new Date
    end = res.end
    res.end = (chunk, encoding) ->
      res.end = end
      res.end chunk, encoding
      req._endTime = new Date
      if 500 <= @statusCode
        message = '\x1b[31m'
      else if 400 <= @statusCode
        message = '\x1b[33m'
      else if 300 <= @statusCode
        message = '\x1b[36m'
      else if 200 <= @statusCode
        message = '\x1b[32m'
      message+= "#{@statusCode}\x1b[0m "
      message+= "\x1b[35m#{req.method.toUpperCase()} "
      message+= "\x1b[37m#{decodeURI req.url} "
      message+= "\x1b[90m("
      if req.route?.path
        message+= "#{req.route.path}"
      else if 399 > @statusCode
        message+= "Static"
      else
        message+= "\x1b[31mUnknown\x1b[90m"
      message+= " - #{req._endTime - req._startTime}ms)\x1b[0m"
      process.nextTick -> console.log message
    return next()
  app.use express.compress()
  app.use express.static path.resolve 'public'
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser()
  app.use express.session
    secret: process.env.CYPHERS
    store: app.sessionStore
  app.use passport.initialize()
  app.use passport.session()
  app.use (req, res, next) ->
    app.locals.req = req
    app.locals.res = res
    return next()
  app.use (req, res, next) ->
    res.stream = (src, opt) ->
      options = { headers: {}, complete: -> }
      options.complete = opt if typeof opt is 'function'
      if typeof opt is 'object'
        options.headers = opt.headers if opt.headers?
        options.complete = opt.complete if opt.complete?
      req.route or= {}
      req.route.path or= 'Stream'
      src = (path.join process.env.ROOTDIR, src) if '/' isnt src.substr 0, 1
      try
        throw new Error 'ENOEXISTS' unless fs.existsSync src
        fstat = fs.statSync src
        throw new Error 'ENOTFILE' unless fstat.isFile()
        mtime = fstat.mtime.getTime()
        since = (new Date req.headers['if-modified-since']).getTime()
        if since >= mtime
          options.complete null, 0, 1
          res.statusCode = 304
          return res.end()
        etags = "\"#{fstat.dev}-#{fstat.ino}-#{mtime}\""
        match = req.headers['if-none-match']
        if etags is match
          options.complete null, 0, 1
          res.statusCode = 304
          return res.end()
        options.headers['Cache-Control'] or= 'public'
        options.headers['Content-Type'] or= mime.lookup src
        options.headers['Last-Modified'] or= fstat.mtime.toUTCString()
        options.headers['ETag'] or= etags
        unless req.headers.range
          res.statusCode = 200
          [ini, end] = [0, fstat.size]
          options.headers['Content-Length'] = fstat.size
        else
          res.statusCode = 206
          total = fstat.size
          [ini, end] = ((parseInt n, 10) for n in (req.headers.range.replace 'bytes=', '').split '-')
          end = total - 1 if (isNaN end) or (end is 0)
          options.headers['Content-Length'] = end + 1 - ini
          options.headers['Content-Range'] = "bytes #{ini}-#{end}/#{total}"
          options.headers['Accept-Range'] = 'bytes'
          options.headers['Transfer-Encoding'] or= 'chunked'
        for key, value of options.headers
          res.setHeader key, value
        stream = fs.createReadStream src, { start: ini, end: end }
        stream.on 'end', ->
          # console.info "Streaming #{src} #{ini}-#{end}", process.memoryUsage()
          return options.complete null, ini, end
        stream.on 'error', (err) ->
          throw "ERRSTREAM #{src} #{ini}-#{end} #{err.stack || err.message}"
        return stream.pipe res
      catch e
        options.complete e, 0, 0
        res.statusCode = 500
        return next new Error "#{e}: #{src} (#{req.url})"
    return next()
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
  mongoose.connect 'mongodb://localhost/media'
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
          user = new User
            name: username
            mail: ''
          user.conf =
            view: 'lines'
        return user.save done
)()

# Routing

( ->
  app.all '/session', (req, res, next) ->
    if req.isAuthenticated()
      req.logout()
      res.statusCode = 204
      return res.end 'ok'
    return (passport.authenticate 'local', (err, user, info) ->
      if err
        res.statusCode = 401
        return res.end 'ng'
      unless user
        res.statusCode = 401
        return res.end 'ng'
      req.logIn user, (err) ->
        if err
          res.statusCode = 500
          return res.end 'ng'
        res.statusCode = 201
        return res.end 'ok'
    )(req, res, next)

  app.get '/', (req, res) ->
    return switch req.query.view
      when 'stream'
        res.render 'index'
      else res.render 'index'

  app.get /^(.*)\.thumbnail$/, (req, res) ->
    src = "/media/var#{_.util.execsafe req.params[0]}"
    tag = _.util.sha1sum src

    res.setHeader 'ETag', tag
    req.connection.setTimeout 5000

    if tag is req.headers['if-none-match']
      res.statusCode = 304
      return res.end()

    exec "find '#{src}' -type f | grep -v '/\\.' | head -1", (err, stdout) ->
      src = _.str.trim stdout
      dst = path.resolve 'tmp', 'thumb', "#{_.util.sha1sum src}.jpg"
      img = { mime: 'application/octet-stream', data: new Buffer 0 }
      mim = mime.lookup src
      tmp = ''
      if fs.existsSync dst
        img.mime = mime.lookup 'jpg'
        img.data = new Buffer fs.readFileSync dst
      if 0 < img.data.length
        res.setHeader 'Cache-Control', 'public'
        res.setHeader 'Content-Type', img.mime
        res.setHeader 'Content-Length', img.data.length
        res.statusCode = 200
        return res.end img.data
      async.series [
        (next) ->
          exec "mktemp '#{path.resolve 'tmp', 'XXXXXX.jpg'}'", (err, stdout) ->
            tmp = "#{_.str.trim stdout}"
            return next null
        (next) ->
          if /^audio/.test mim
            return (new meta fs.createReadStream src).on 'metadata', (id3) ->
              img.mime = mime.lookup id3.picture[0].format
              img.data = id3.picture[0].data
              return next null
          if /^video/.test mim
            return exec "ffmpeg -y -ss 180 -vframes 1 -i '#{src}' -f image2 '#{tmp}'", (err, stdout) ->
              img.mime = mime.lookup tmp
              img.data = new Buffer fs.readFileSync tmp
              return next null
          if /^image/.test mim
            img.mime = mim
            img.data = new Buffer fs.readFileSync src
            return next null
          if /pdf$/.test mim
            return exec "convert -define jpeg -density 24 '#{src}[0]' '#{tmp}'", (err, stdout) ->
              img.mime = mime.lookup tmp
              img.data = new Buffer fs.readFileSync tmp
              return next null
          return next new Error 'no thumbnail'
        (next) ->
          exec "mktemp '#{path.resolve 'tmp', 'XXXXXX.jpg'}'", (err, stdout) ->
            _tmpsrc = _.str.trim stdout
            exec "mktemp '#{path.resolve 'tmp', 'XXXXXX.jpg'}'", (err, stdout) ->
              _tmpdst = _.str.trim stdout
              fs.writeFileSync _tmpsrc, img.data
              exec "convert -define jpeg:size=160x160 -resize 160x160 '#{_tmpsrc}' '#{_tmpdst}'", (err, stdout) ->
                img.data = new Buffer fs.readFileSync _tmpdst
                fs.unlinkSync _tmpsrc
                fs.renameSync _tmpdst, dst
                return next null

      ], (err) ->
        fs.unlinkSync tmp if fs.existsSync tmp
        if err
          console.error err, src
          res.writeHead 404
          return res.end err.message
        res.setHeader 'Cache-Control', 'public'
        res.setHeader 'Content-Type', img.mime
        res.setHeader 'Content-Length', img.data.length
        res.statusCode = 200
        return res.end img.data

  app.get /.*/, (req, res) ->
    if req.isAuthenticated()
      src = "/media/var#{decodeURI req.url}"
      if (fs.existsSync src) and (fs.statSync src).isFile()
        return res.stream src
    return res.redirect "/##{req.url}"
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
        return accept err, no if err
        data.user = session.passport.user
        return accept null, yes
  return io
)()

# WebSocket

( ->
  io.sockets.on 'connection', (socket) ->
    session = socket.handshake.user

    socket.on 'sync', (conf = null) ->
      console.log "sync from #{session?.name}"
      return (socket.emit 'sync', null) unless session
      User.findById session._id, (err, user) ->
        user.conf = conf if conf
        user.save -> socket.emit 'sync', user

    socket.on 'fetch', (uri) ->
      return null unless session
      fix = if (1 < (_uri = uri.split '::').length) then _uri[1] else null
      uri = if (1 < _uri.length) then _uri[0] else uri
      dst = path.join '/media', 'var', decodeURI uri
      console.log "fetch from #{session?.name}", dst, fix
      unless fix
        data = []
        if (fs.existsSync dst)
          if (fs.statSync dst).isDirectory()
            data = _.util.reject fs.readdirSync dst
            data = _.map data, (src) -> _.util.status path.join dst, src
            data = _.sortBy data, (stat) -> stat.time
          else
            data = _.util.status dst
        socket.emit 'fetch', data
      if fix is 'stream'
        exec "find '#{_.util.execsafe dst}' -type f -print0 | xargs -0 stat --format '%Y %n' | grep -v '/\\.' | sort -k 1 | tail -50", (err, stdout) ->
          console.error err if err
          data = _.util.reject _.map (_.str.trim(stdout).split '\n'), (src) -> src.replace /^[0-9]+ /, ''
          data = _.map data, (src) ->
            _.util.status src.replace /\/\//g, '/'
          data = _.sortBy data, (stat) -> stat.time
          socket.emit 'fetch', data
      if /search/.test fix
        val = fix.replace /^search\//, ''
        exec "find '#{_.util.execsafe dst}' -iname '*#{_.util.execsafe val}*' -print0 | xargs -0 stat --format '%Y %n' | grep -v '/\\.' | sort -k 1", (err, stdout) ->
          console.error err if err
          data = _.util.reject _.map (_.str.trim(stdout).split '\n'), (src) -> src.replace /^[0-9]+ /, ''
          data = _.map data, (src) ->
            _.util.status src.replace /\/\//g, '/'
          data = _.sortBy data, (stat) -> stat.time
          socket.emit 'fetch', data
)()
