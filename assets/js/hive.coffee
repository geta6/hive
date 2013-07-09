$ -> new Hive()

_.unitconv = (size, mime, i = 0) ->
  return "#{size} items" if mime is 'text/directory'
  units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB']
  ++i while (size/=1024) >= 1024
  return "#{size.toFixed(2)} #{units[i+1]}"

_.mimeicon = (mime) ->
  return switch yes
    when mime is 'text/directory' then 'folder_open'
    when /video/.test mime        then 'facetime_video'
    when /audio/.test mime        then 'music'
    when /image/.test mime        then 'picture'
    when /pdf/.test mime          then 'book_open'
    when /text/.test mime         then 'notes'
    else                               'file'

_.mimethumb = (name, mime) ->
  return switch yes
    when mime is 'text/directory'   then '/img/directory.png'
    when /^audio/.test mime         then '/img/audio.png'
    when /^video/.test mime         then '/img/video.png'
    when /^image/.test mime         then '/img/image.png'
    when /pdf/.test mime            then '/img/pdf.png'
    when /image$/.test mime         then '/img/discimage.png'
    when /^text/.test mime          then '/img/text.png'
    when /(x-c|java)/.test mime     then '/img/text.png'
    when /font/.test mime           then '/img/font.png'
    when /(zip|compress)/.test mime then '/img/archive.png'
    else
      ext = name.replace /^.*\.([^\.]*)$/, '$1'
      switch yes
        when /^(txz|tgz|gz)$/i.test ext                    then '/img/archive.png'
        when /^(mdf|mds|cdr|bin)$/i.test ext               then '/img/discimage.png'
        when /^(app|exe|ipa)$/i.test ext                   then '/img/application.png'
        when /^(md|rtf|cue)$/i.test ext                    then '/img/text.png'
        when /^(ttf|otf)$/i.test ext                       then '/img/font.png'
        when /^(docx|doc|pages)$/i.test ext                then '/img/document.png'
        when /^(xls|xlsx|numbers)$/i.test ext              then '/img/spreadsheet.png'
        when /^(ppt|pptx|key)$/i.test ext                  then '/img/presentation.png'
        when /^(ac3|amr|flac|ra)$/i.test ext               then '/img/audio.png'
        when /^(ts|dvd|dvr-ms|wmv|rm|rmvb|ogm)$/i.test ext then '/img/video.png'
        else '/img/default.png'

_.playable = (mime) ->
  return 'audio' if /audio/.test mime
  return 'video' if /video/.test mime
  return 'pages' if /pdf/.test mime
  return no

_.templateSettings.interpolate = /\{\{(.+?)\}\}/g

class Hive

  time: 120
  user: {}

  cache: {}

  socket: null
  resurrect: ->
  connected: no

  pkginfo: {}
  lastdata: {}

  authorized: no
  lazyloaded: no

  constructor: ->

    if typeof io is 'undefined'
      return (@$ '#leader').html @render 'errors', message: 'Server is down.'

    @socket = io.connect "http://#{window.location.host}"
    window.io = null

    @socket.on 'init', (@user, @pkginfo) =>
      @notify "#{pkginfo.name} version #{pkginfo.version}"

    @socket.on 'disconnect', =>
      @connected = no
      @notify 'socket disconnected', 'failure'

    @socket.on 'connect', =>
      @connected = yes
      @socket.emit 'init'
      @notify 'socket connected', 'success'
      @resurrect()
      unless @initialized
        $.ajax '/session',
          dataType: 'JSON'
          error: (xhr) =>
            (@$ '#leader').html @render 'unauth'
          success: (@user) =>
            @user.conf or= {}
            @user.conf = _.defaults @user.conf, { sort: '-time', view: 'lines' }
            @sync()
            @initialize()

    ($ document).on 'submit', (event) =>
      event.preventDefault() unless ($ event.target).hasClass 'passthrough'
      return @negotiate event if ($ event.target).hasClass 'negotiation'
      return @playstate event if ($ event.target).hasClass 'playstation'
      return @datafind event if ($ event.target).hasClass 'datafind'

  initialize: ->
    unless @initialized
      @initialized = yes
      @notify "Hello, #{@user.name}"

      (@$ '.navi, .site').fadeIn @time

      @socket.on 'sync', (@user) =>
        ($ window).trigger 'synchronized'

      @socket.on 'start', (data) =>
        @socket.current = window.location.hash
        title = _.last data.query.path.split '/'
        (@$ 'title').text "#{@pkginfo.name}"
        (@$ 'title').text "#{@pkginfo.name}・#{title}" if title
        (@$ '#header li').removeClass 'selected'
        (@$ '#latest50').addClass 'selected' if /stream/.test data.query.term
        (@$ '#datafind').addClass 'selected' if /^search\//.test data.query.term
        @navigate data

      @socket.on 'data', (stat) =>
        if @socket.current is window.location.hash
          (@$ '#leader').append @render 'leader', stat

      @socket.on 'end', (data) =>
        @loader no, =>
          return @lazyload() unless data # directory
          (@$ '#leader').append @render 'browse', data
          @lastdata = data

      @socket.on 'skip', (data) =>
        @lastdata = data
        @playstate null, data

      @socket.on 'error', (err) =>
        (@$ '#leader').append @render 'errors', message: err
        @loader no

      # View mode

      (@$ '#viewmode').on 'click', =>
        @user.conf.view = if @user.conf.view is 'thumb' then 'lines' else 'thumb'
        @viewmode()

      # Latest 50

      (@$ '#latest50').on 'click', =>
        location = @locate()
        if location.term is 'stream'
          window.location.hash = "#{location.path.replace /::stream$/, ''}"
        else
          window.location.hash = "#{location.path}::stream"

      # Search

      (@$ '#datafind a').on 'click', =>
        (@$ '#datafind').toggleClass 'focus'
        if 'block' is (@$ '#datafind input').css 'display'
          (@$ '#datafind input').focus()

      # Close Menu

      ($ document).on 'click', (event) =>
        if (__info = ($ event.target).parents('.info')).size()
          unless (__open = ($ event.target).parents('.open')).size()
            __info.siblings('.info').find('.open').slideUp @time
            return __info.find('.open').slideDown @time
        ($ '.open').slideUp @time

      # View Sort

      (@$ '#viewsort_timedsc').on 'click', (event) =>
        @user.conf.sort = '-time'
        @viewsort()

      (@$ '#viewsort_timeasc').on 'click', (event) =>
        @user.conf.sort = '+time'
        @viewsort()

      (@$ '#viewsort_namedsc').on 'click', (event) =>
        @user.conf.sort = '-name'
        @viewsort()

      (@$ '#viewsort_nameasc').on 'click', (event) =>
        @user.conf.sort = '+name'
        @viewsort()

      # Element

      (@$ '#handle_show').on 'click', => @player yes
      (@$ '#player').on 'click', (event) =>
        return null if ($ event.target).parents('form').size()
        return null if ($ event.target)[0].tagName is 'AUDIO'
        return null if ($ event.target)[0].tagName is 'VIDEO'
        return null if ($ event.target)[0].tagName is 'IMG'
        return null if ($ event.target)[0].tagName is 'INPUT'
        @player no

      # Media

      ($ document).on 'click', '.handle_play', =>
        if ($ '.handle_play').find('i').hasClass 'play'
          (@$ '#audio').get(0).play()
          (@$ '#video').get(0).play()
        else
          (@$ '#audio').get(0).pause()
          (@$ '#video').get(0).pause()

      ($ document).on 'click', '.handle_back', =>
        @socket.emit 'prev', @lastdata

      ($ document).on 'click', '.handle_next', =>
        @socket.emit 'next', @lastdata

      (@$ '#audio, #video').on 'play', (event) =>
        @loader no
        if 0 < ($ event.target).attr('src').length
          @notify "<i class='icon play'></i> #{_.last ($ event.target).attr('src').split '/'}"
          ($ '.handle_play').find('i').removeClass('play').addClass('pause')

      (@$ '#audio, #video').on 'pause', =>
        if 0 < ($ event.target).attr('src').length
          @notify "<i class='icon pause'></i> #{_.last ($ event.target).attr('src').split '/'}"
          ($ '.handle_play').find('i').removeClass('pause').addClass('play')

      (@$ '#audio, #video').on 'ended', =>
        @socket.emit 'next', @lastdata

      (@$ '#jumps').on 'keyup', (event) =>
        if event.keyCode is 13
          @pagejump (@$ '#jumps').val()

      (@$ '#pages').on 'click', (event) =>
        __target = ($ event.target)
        x = event.pageX - __target.offset().left
        w = __target.width()
        src = __target.attr 'src'
        page = src.replace(/^.*\?page=([0-9]*)$/, '$1')
        page = 1 if src is page
        page++ if w/2 < x
        page-- if w/2 > x
        @pagejump page

      # Image Viewer Size

      ($ window).on 'resize', =>
        (@$ '#pages').css maxHeight: ($ document).height() - 10

      # Location

      ($ window).on 'hashchange', =>
        @loader yes
        if /^search\//.test term = @locate().term
          (@$ '#datafind_field').val decodeURI (term.replace /^search\//, '')
          (@$ '#datafind').addClass 'focus'
        (@$ '#leader').fadeOut @time, =>
          (@$ '#leader').html('').show()
          @viewmode @user.conf.view
          @viewsort @user.conf.sort
          @lazyloaded = no
          if @connected
            @socket.emit 'fetch', _.extend @locate(), @user.conf
          else
            @resurrect = =>
              @resurrect = ->
              @socket.emit 'fetch', _.extend @locate(), @user.conf

      ($ window).trigger 'hashchange'
      ($ window).trigger 'resize'

  pagejump: (page = 1, src = null) ->
    @loader yes
    @notify "loading page #{page}"
    unless src
      src = (@$ '#pages').attr 'src'
    src = src.replace(/^(.*)\?page=[0-9]*$/, '$1') + "?page=#{page}"
    img = new Image
    img.onload = =>
      @loader no
      (@$ '#pages').attr 'src', src
    img.src = src
    (@$ '#jumps').val page

  datafind: (event) ->
    location = @locate()
    __search = (@$ '#datafind_field').val()
    if 0 < __search.length
      window.location.hash = "#{location.path}::search/#{encodeURI __search}"
      (@$ '#datafind').addClass 'focus'
    else
      window.location.hash = location.path
      (@$ '#datafind').removeClass 'focus'

  player: (show = yes, event = {}) ->
    if show
      (@$ '#player').fadeIn @time
      (@$ '#handle').animate marginBottom: -1*(@$ '#handle').height(), @time, =>
        (@$ '#handle').hide()
    else
      (@$ '#player').fadeOut @time, =>
      (@$ '#handle').show().animate marginBottom: 0, @time

  sync: (done = ->) ->
    ($ window).on 'synchronized', =>
      ($ window).off 'synchronized'
      done()
    @socket.emit 'sync', @user.conf

  navigate: (data, addr = '#') ->
    (@$ '#guides div').fadeOut @time, =>
      (@$ '#guides div').html ''
      if data.query.term
        if /stream/.test data.query.term
          data.query.path += "/Latest #{data.length}"
      navi = _.map (_.compact data.query.path.split '/'), (name, i) ->
        ($ '<a>').attr(href: addr += "/#{name}").html name
      navi.unshift ($ '<a>').attr(href: "#/").html 'index'
      navi.push ($ '<span>').html (navi.pop()).html()
      for nav, i in navi
        (@$ '#guides div').append(nav)
        (@$ '#guides div').append(($ '<span>').html ' / ') if i isnt navi.length - 1
      (@$ '#guides div').fadeIn(@time)
      (@$ '#guides').animate
        marginTop: if navi.length is 1 then 0 else (@$ '#header').height()
      , @time, =>

  negotiate: (event, success = ->) ->
    data = {}; for el in ($ event.target).find('input')
      data[($ el).attr 'name'] = ($ el).val()
    (@$ '.negotiation input, .negotiation button').attr 'disabled', yes
    @loader yes, =>
      $.ajax ($ event.target).attr('action'),
        type: ($ event.target).attr('method')
        data: data
        dataType: 'JSON'
        error: (res) =>
          (@$ '.negotiation input, .negotiation button').attr 'disabled', no
          @loader no
          @notify 'sign in failure', 'failure'
        success: (@user) => window.location.reload()

  playstate: (event, data) ->
    if event
      type = ($ event.target).attr 'method'
      src = ($ event.target).attr 'action'
    else
      type = 'audio' if /audio/.test data.mime
      type = 'video' if /video/.test data.mime
      type = 'pages' if /pdf/.test data.mime
      src = data.path
    if type is 'audio'
      (@$ '#pages').hide().attr 'src', ''
      (@$ '#video').hide().attr 'src', ''
      (@$ '#jumps').hide()
      __target = (@$ '#audio')
    if type is 'video'
      (@$ '#pages').hide().attr 'src', ''
      (@$ '#audio').hide().attr 'src', ''
      (@$ '#jumps').hide()
      __target = (@$ '#video')
    if type is 'pages'
      (@$ '#audio').hide().attr 'src', ''
      (@$ '#video').hide().attr 'src', ''
      (@$ '#jumps').show().val(1)
      __target = (@$ '#pages')
      @pagejump 1, src

    if src isnt __target.attr 'src'
      __target.show()
      if 'jumps' isnt __target.attr 'id'
        @loader yes
        __target.attr 'src', src
      @notify "loading #{_.last src.split '/'}"
      (@$ '#player .viewer').html @render 'viewer', @lastdata
      __target[0].play() if __target[0].play

    (@$ '#handle_show').css(backgroundImage: "url('#{src}.thumbnail')")
    @player yes

  $: (expr) ->
    @cache['dom'] or= {}
    return @cache['dom'][expr] or= ($ expr)

  render: (name, arg) ->
    @cache['template'] or= {}
    @cache['template'][name] or= _.template (@$ "#tp_#{name}").html().replace(/&lt;%/g, '<%').replace(/%&gt;/, '%>')
    return ($ @cache['template'][name] arg)

  locate: ->
    location =
      path: (window.location.hash.split '::')[0].substr 1
      term: (window.location.hash.split '::')[1]
    location.path = '/' if 0 is location.path.length
    try
      location.path = decodeURI location.path
    catch e
      location.path = decodeURI location.path.replace '%', '%25'
    finally
      return location

  loaderPosition: 0
  loaderInterval: null
  loader: (start = yes, callback = ->) ->
    @loaderPposition or= 0
    if start
      @loaderInterval = setInterval ->
        @loaderPosition = if ++@loaderPosition < 6 then @loaderPosition else 0
        (@$ '#loader').css 'background-position': "#{@loaderPosition}px 0"
      , 12
      (@$ '#loader').slideDown @time, => callback()
    else
      (@$ '#loader').slideUp @time, =>
        clearInterval @loaderInterval
        return callback()

  notify: (text = null, type = 'normal') ->
    (@$ '#notify').prepend $notify = @render 'notify', { type: type, text: text }
    return $notify.fadeIn @time, =>
      setTimeout =>
        $notify.fadeOut @time, => $notify.remove()
      , 2000

  viewmode: (force = no) ->
    @user.conf.view = force if force
    if @user.conf.view is 'thumb'
      (@$ '#viewmode i').addClass('show_thumbnails').removeClass('show_thumbnails_with_lines')
      ($ '.leader').addClass('thumb').removeClass('lines')
    else
      (@$ '#viewmode i').removeClass('show_thumbnails').addClass('show_thumbnails_with_lines')
      ($ '.leader').removeClass('thumb').addClass('lines')
    @lazyload()
    @sync()

  viewsort: (force = no) ->
    @user.conf.sort = force if force
    if '-' is @user.conf.sort.substr 0, 1
      (@$ '#viewsort .order i').removeClass('up_arrow').addClass('down_arrow')
    else
      (@$ '#viewsort .order i').removeClass('down_arrow').addClass('up_arrow')
    if 'time' is @user.conf.sort.substr 1
      (@$ '#viewsort .sort i').removeClass('font').addClass('clock')
    else
      (@$ '#viewsort .sort i').removeClass('clock').addClass('font')
    @sync =>
      ($ window).trigger('hashchange') unless force

  lazyload: ->
    if !@lazyloaded and @user.conf.view is 'thumb'
      @lazyloaded = yes
      ($ '.lazy').lazyload failure_limit: 3
      setTimeout (=> ($ window).resize()), @time * 2
