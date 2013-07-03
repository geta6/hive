
$ -> geta6 = new Geta6()

_.util =
  unitconv: (size, i = 0) ->
    units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    ++i while (size/=1024) >= 1024
    return "#{size.toFixed(1)} #{units[i+1]}"

class Geta6

  debug: yes
  cached: {}
  template: {}

  user: {}
  socket: io.connect "http://#{location.host}"

  setting:
    view: 'lines' # block or lines

  authorized: no
  initialized: no
  authinitialized: no

  messageTimeout: 2000
  animationDuration: 120
  loadbarInterval: null
  loadbarIntervalTime: 12
  loadbarCurrentPosition: 0
  lazyLoadedImages: no

  $: (expr) ->
    return @cached[expr] if @cached[expr]
    return @cached[expr] = ($ expr)

  constructor: ->
    @flash "constructor", 'debug'

    # Socket
    @socket.on 'connect', =>
      ($ '.socket').attr 'disabled', no
      @flash 'socket.io connected', 'success'
    @socket.on 'disconnect', =>
      ($ '.socket').attr 'disabled', yes
      @flash 'socket.io disconnected', 'failure'
    @socket.on 'sync', (user) =>
      @user = user
      @setting = user.conf if user?
      @initialize()
    @socket.on 'fetch', (data) =>
      if @authorized
        @render 'list', data, =>
          @lazyload()
          @navigation()

    # Element
    ($ window).on 'hashchange', =>
      console.log 'hc'
      @socket.emit 'fetch', @location()
    ($ document).on 'submit', 'form', (event) =>
      event.preventDefault()
      @negotiation ($ '#user').val(), ($ '#pass').val()
    (@$ '#browse').on 'click', =>
      @viewmode()
    (@$ '#stream').on 'click', =>
      if 'stream' isnt _.last window.location.hash.split '::'
        window.location.hash = "#{window.location.hash}::stream"

    @socket.emit 'sync'

  initialize: ->
    unless @initialized
      @flash "initialize", 'debug'
      @initialized = yes
      @template.list = _.template ($ '#tp_list').html()
      @template.file = _.template ($ '#tp_file').html()
      @template.auth = _.template ($ '#tp_auth').html()

    unless @authorized = _.isObject @user
      @render 'auth', null
    else
      unless @authinitialized
        @authinitialized = yes
        @flash "authorize", 'debug'
        @flash "Hello, #{@user.name}"
        (@$ '.page, .site').fadeIn @animationDuration
        @socket.emit 'fetch', @location()

  flash: (msg, type = null) ->
    return if type is 'debug' and !@debug
    (@$ 'aside').prepend $tip = ($ '<div>')
      .append(($ '<div>').addClass('flash').addClass(type).html(msg))
      .append(($ '<div>').addClass('clear'))
    return $tip.animate opacity: 1, @animationDuration, =>
      setTimeout =>
        $tip.animate opacity: 0, @animationDuration, -> ($ @).remove()
      , @messageTimeout

  sync: ->
    if @authorized
      @socket.emit 'sync', @setting

  load: (start = yes, next = ->) ->
    if start
      @loadbarInterval = setInterval ->
        @loadbarCurrentPosition = if ++@loadbarCurrentPosition < 6 then @loadbarCurrentPosition else 0
        (@$ 'header .load').css 'background-position': "#{@loadbarCurrentPosition}px 0"
      , @loadbarIntervalTime
      (@$ 'header .load').slideDown @animationDuration, =>
        next()
    else
      (@$ 'header .load').slideUp @animationDuration, =>
        next()
        clearInterval @loadbarInterval

  render: (layout, data = null, done = ->) ->
    @load yes
    @lazyLoadedImages = no
    (@$ 'article').fadeOut @animationDuration, =>
      (@$ 'article').html ''
      if _.isArray data
        for chunk in data
          (@$ 'article').prepend chunk = ($ @template[layout] chunk)
          chunk.addClass @setting.view
      else
        (@$ 'article').prepend chunk = ($ @template[layout] data)
        chunk.addClass @setting.view
      @viewmode @setting.view
      (@$ 'article').fadeIn @animationDuration, =>
        @load no, => done()

  location: ->
    return window.location.hash.substr 1

  navigation: (done = ->) ->
    (@$ 'nav').html ''
    divs = []
    divs.push (@$ 'nav').append ($ '<a>').attr(href: "#/").html 'index'
    breads = _.compact @location().split '/'
    prefix = @location().split '::'
    if 1 < prefix.length
      breads = _.compact @location().replace(/::.*$/, '').split '/'
      if 'stream' is _.last prefix
        console.log ($ '.list')
        breads.push "Latest #{($ '.list').length}"
    for bread, i in breads
      divs.push ($ '<i>').html('/')
      if i+1 < breads.length
        divs.push ($ '<a>').attr(href: "#/#{breads.slice(0,i+1).join '/'}").html decodeURI bread
    divs.push (($ '<span>').html decodeURI bread) if bread
    (@$ 'nav').append div for div in divs
    (@$ 'nav').animate marginTop: (if bread then (@$ 'header').height() else 0), 240, => done()

  negotiation: (user, pass, done = ->) ->
    @load yes
    $.ajax '/session',
      type: 'POST'
      data: { username: user, password: pass }
      complete: (xhr, body) =>
        @load no
        if body is 'success'
          return window.location.reload()
        if 500 > xhr.status
          @flash 'Name or Pass Mismatch', 'failure'
        else
          @flash 'Server error', 'failure'

  lazyload: ->
    unless @lazyLoadedImages
      if @setting.view is 'block'
        @lazyLoadedImages = yes
        ($ '.lazy').lazyload
          threshold: 100
        setTimeout =>
          ($ window).resize()
        , @animationDuration * 2
          # skip_invisible: no

  viewmode: (force = no) ->
    @setting.view = if @setting.view is 'lines' then 'block' else 'lines'
    @setting.view = force if force
    @flash "#{@setting.view} mode" unless force
    if @setting.view is 'block'
      (@$ '#browse i').addClass('show_thumbnails').removeClass('show_thumbnails_with_lines')
      ($ 'article .list').addClass('block').removeClass('lines')
    else
      (@$ '#browse i').removeClass('show_thumbnails').addClass('show_thumbnails_with_lines')
      ($ 'article .list').removeClass('block').addClass('lines')
    @sync()
