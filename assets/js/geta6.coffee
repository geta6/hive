$ -> geta6 = new Geta6()

_.unitconv = (size, mime, i = 0) ->
  # return "#{size} items" if mime is 'text/directory'
  units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
  ++i while (size/=1024) >= 1024
  return "#{size.toFixed(2)} #{units[i+1]}"

_.mimeicon = (mime) ->
  if mime is 'text/directory' then return 'folder_open'
  if /video/.test mime then return 'facetime_video'
  if /audio/.test mime then return 'music'
  if /image/.test mime then return 'picture'
  if /pdf/.test mime   then return 'book_open'
  if /text/.test mime  then return 'notes'
  return 'file'

_.playable = (mime) ->
  return 'audio' if /audio/.test mime
  # return 'video' if /video/.test mime
  return no

_.templateSettings.interpolate = /\{\{(.+?)\}\}/g

class Geta6

  time: 120
  user: {}

  cache: {}

  socket: io.connect "http://#{window.location.host}"
  window.io = null

  initialized: no
  imageloaded: no

  constructor: ->
    @socket.on 'disconnect', =>
      @notify 'socket disconnected', 'failure'

    @socket.on 'connect', =>
      @notify 'socket connected', 'success'
      unless @initialized
        $.ajax '/session',
          type: 'GET'
          dataType: 'JSON'
          error: =>
            (@$ '#leader').html @render 'visits'
          success: (@user) =>
            @user.conf or= {}
            @user.conf.sort or= '-time'
            @user.conf.view or= 'lines'
            @sync()
            @initialize()

    ($ document).on 'submit', (event) =>
      if ($ event.target).hasClass 'negotiation'
        event.preventDefault()
        return @negotiate event
      if ($ event.target).hasClass 'playstation'
        event.preventDefault()
        return @playstate event

  initialize: ->
    unless @initialized
      @initialized = yes
      @notify "Hello, #{@user.name}"

      (@$ '.navi, .site').fadeIn @time

      @socket.on 'sync', (err, @user) =>
        console.log @user
        ($ window).trigger 'synchronized'

      @socket.on 'start', (data) =>
        (@$ '#header li').removeClass 'selected'
        (@$ '#stream').addClass 'selected' if /stream/.test data.query.term
        @navigate data

      @socket.on 'data', (stat) =>
        (@$ '#leader').append @render 'leader', stat

      @socket.on 'end', (data) =>
        @loader no, =>
          return @lazyload() unless data # directory
          (@$ '#leader').append @render 'browse', data

      @socket.on 'error', (err) =>
        (@$ '#leader').append @render 'errors'

      (@$ '#stream').on 'click', =>
        location = @locate()
        if location.term is 'stream'
          window.location.hash = "#{location.path.replace /::stream$/, ''}"
        else
          window.location.hash = "#{location.path}::stream"

      (@$ '#viewmode').on 'click', =>
        @user.conf.view = if @user.conf.view is 'thumb' then 'lines' else 'thumb'
        @viewmode()

      ($ document).on 'click', (event) =>
        if (__info = ($ event.target).parents('.info')).size()
          unless (__open = ($ event.target).parents('.open')).size()
            __info.siblings('.info').find('.open').slideUp @time
            return __info.find('.open').slideDown @time
        ($ '.open').slideUp @time

      # Sort

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

      # Media element

      (@$ '#player_wrap').on 'click', (event) =>
        (@$ '#floats').fadeIn @time

      (@$ '#player_play').on 'click', =>
        if (@$ '#player_play').find('i').hasClass 'play'
          (@$ 'audio, video').get(0).play()
        else
          (@$ 'audio, video').get(0).pause()

      (@$ 'audio, video').on 'play', (event) =>
        @notify "<i class='icon play'></i> #{_.last ($ event.target).attr('src').split '/'}"
        (@$ '#player_play').find('i').removeClass('play').addClass('pause')

      (@$ 'audio, video').on 'pause', =>
        @notify "<i class='icon pause'></i> #{_.last ($ event.target).attr('src').split '/'}"
        (@$ '#player_play').find('i').removeClass('pause').addClass('play')

      # Location

      ($ window).on 'hashchange', =>
        @loader yes
        (@$ '#leader').fadeOut @time, =>
          (@$ '#leader').html('').show()
          @viewmode @user.conf.view
          @viewsort @user.conf.sort
          @imageloaded = no
          @socket.emit 'fetch', _.extend @locate(), @user.conf

      ($ window).trigger('hashchange')

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

  playstate: (event) ->
    type = ($ event.target).attr 'method'
    src = ($ event.target).attr 'action'
    @notify "loading #{_.last src.split '/'}"
    if type is 'audio'
      (@$ 'video').attr 'src', ''
      (@$ 'audio').attr 'src', src
    if type is 'video'
      (@$ 'audio').attr 'src', ''
      (@$ 'video').attr 'src', src
    (@$ '#player_wrap')
      .attr(href: "##{src}")
      .css(backgroundImage: "url('#{src}.thumbnail')")
    (@$ '#player').animate marginBottom: 0, @time

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
    return location

  loader: (start = yes, callback = ->) ->
    @loader.position or= 0
    if start
      @loader.interval = setInterval ->
        @loader.position = if ++@loader.position < 6 then @loader.position else 0
        (@$ '#loader').css 'background-position': "#{@loader.position}px 0"
      , 12
      (@$ '#loader').slideDown @time, => callback()
    else
      (@$ '#loader').slideUp @time, =>
        clearInterval @loader.interval
        return callback()

  notify: (text = null, type = 'normal') ->
    (@$ '#notify').prepend $notify = @render 'notify', { type: type, text: text }
    return $notify.fadeIn @time, =>
      setTimeout =>
        $notify.fadeOut @time, => #$notify.remove()
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
    if !@imageloaded and @user.conf.view is 'thumb'
      @imageloaded = yes
      ($ '.lazy').lazyload failure_limit: 3
      setTimeout (=> ($ window).resize()), @time * 2
