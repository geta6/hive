
$ -> geta6 = new Geta6()

_.util =
  unitconv: (size, i = 0) ->
    units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    ++i while (size/=1024) >= 1024
    return "#{size.toFixed(1)} #{units[i+1]}"

class Geta6

  debug: no
  cached: {}
  template: {}

  user: {}
  socket: io.connect "http://#{location.host}"

  setting:
    view: 'lines' # block or lines
    sort: 'time'
    order: 'desc'

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
        if /::stream/.test @location()
          ($ '#stream').addClass 'selected'
          @setting.sort = 'time'
          @setting.order = 'desc'
        else
          ($ '#stream').removeClass 'selected'
        if (_.isArray data) and 0 is data.length
          console.log data
          @render 'void', {}, =>
            @flash "No result", 'failure'
        else
          if _.isArray data
            @render 'list', data
          else
            @render 'file', data

    # Element
    ($ document).on 'submit', 'form', (event) =>
      event.preventDefault()
      @negotiation ($ '#username').val(), ($ '#password').val()
    (@$ '#browse').on 'click', => @viewmode()
    (@$ '#stream').on 'click', =>
      if 'stream' isnt _.last window.location.hash.split '::'
        window.location.hash = "#{window.location.hash}::stream"
    (@$ '#sortby').on 'click', => (@$ '#sortby').siblings('.open').slideToggle @animationDuration
    (@$ '#sorby_time_asc').on 'click', => @viewsort 'time', 'asc'
    (@$ '#sorby_time_dsc').on 'click', => @viewsort 'time', 'desc'
    (@$ '#sorby_name_asc').on 'click', => @viewsort 'name', 'asc'
    (@$ '#sorby_name_dsc').on 'click', => @viewsort 'name', 'desc'
    (@$ '#search').on 'click', => (@$ '#search').siblings('.open').slideToggle @animationDuration

    # Global
    ($ window).on 'hashchange', =>
      @socket.emit 'fetch', @location()
    ($ document).on 'click', (event) =>
      unless ($ event.target).parents('header').size()
        (@$ '#sortby').siblings('.open').slideUp @animationDuration

    @socket.emit 'sync'

  initialize: ->
    unless @initialized
      @flash "initialize", 'debug'
      @initialized = yes
      @template.void = _.template ($ '#tp_void').html()
      @template.list = _.template ($ '#tp_list').html()
      @template.file = _.template ($ '#tp_file').html()
      @template.auth = _.template ($ '#tp_auth').html()

    unless @authorized = _.isObject @user
      @flash "unauthorized", 'failure'
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

  render: (layout, data = {}, done = ->) ->
    @load yes
    @lazyLoadedImages = no
    (@$ 'article').fadeOut @animationDuration, =>
      (@$ 'article').html ''
      if _.isArray data
        for chunk in data
          (@$ 'article').prepend chunk = ($ @template[layout] chunk)
          chunk.addClass @setting.view if @setting?.view?
      else
        (@$ 'article').prepend chunk = ($ @template[layout] data)
        chunk.addClass @setting.view if @setting?.view?
      @viewmode(@setting.view) if @authorized
      @viewsort(@setting.sort, @setting.order) if @authorized
      (@$ 'article').fadeIn @animationDuration, =>
        @load no, =>
          @lazyload() if @setting.view is 'block'
          @navigation()
          done()

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
        breads.push "Latest #{($ '.list').length}"
    for bread, i in breads
      divs.push ($ '<i>').html('/')
      if i+1 < breads.length
        divs.push ($ '<a>').attr(href: "#/#{breads.slice(0,i+1).join '/'}").html decodeURI bread
    divs.push (($ '<span>').html decodeURI bread) if bread
    (@$ 'nav').append div for div in divs
    (@$ 'nav').animate marginTop: (if bread then (@$ 'header').height() else -1), 240, => done()

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
          failure_limit: 3
          skip_invisible: yes
        setTimeout =>
          ($ window).resize()
        , @animationDuration * 2

  viewsort: (force = no, order = no) ->
    @setting or= {}
    @setting.sort or= 'time'
    @setting.sort = if @setting.sort is 'time' then 'name' else 'time'
    @setting.sort = force if force
    @setting.order = order || 'desc'
    if ($ '.list').size()
      (@$ 'article').html ($ '.list').sort (a, b) =>
        if (($ a).attr "x-#{@setting.sort}") > (($ b).attr  "x-#{@setting.sort}")
          return if @setting.order is 'asc' then 1 else -1
        else
          return if @setting.order is 'asc' then -1 else 1

    (@$ '.sortby').removeClass('selected')

    if @setting.sort is 'time'
      (@$ '#sortby .js_sort').removeClass('font').addClass('clock')
      if @setting.order is 'asc'
        (@$ '#sorby_time_asc').addClass 'selected'
        (@$ '#sortby .js_order').addClass('up_arrow').removeClass('down_arrow')
      else
        (@$ '#sorby_time_dsc').addClass 'selected'
        (@$ '#sortby .js_order').removeClass('up_arrow').addClass('down_arrow')
    else
      (@$ '#sortby .js_sort').addClass('font').removeClass('clock')
      if @setting.order is 'asc'
        (@$ '#sorby_name_asc').addClass 'selected'
        (@$ '#sortby .js_order').addClass('up_arrow').removeClass('down_arrow')
      else
        (@$ '#sorby_name_dsc').addClass 'selected'
        (@$ '#sortby .js_order').removeClass('up_arrow').addClass('down_arrow')

    @lazyLoadedImages = no
    @lazyload() if force
    @sync()

  viewmode: (force = no) ->
    @setting or= {}
    @setting.view or= 'lines'
    @setting.view = if @setting.view is 'lines' then 'block' else 'lines'
    @setting.view = force if force
    if @setting.view is 'block'
      (@$ '#browse i').addClass('show_thumbnails').removeClass('show_thumbnails_with_lines')
      ($ 'article .list').addClass('block').removeClass('lines')
      @lazyload() unless force
    else
      (@$ '#browse i').removeClass('show_thumbnails').addClass('show_thumbnails_with_lines')
      ($ 'article .list').removeClass('block').addClass('lines')
    @sync()
