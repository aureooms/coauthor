sharejsEditor = 'cm'  ## 'ace' or 'cm'; also change template used in message.jade

switch sharejsEditor
  when 'cm'
    editorMode = (editor, format) ->
      editor.setOption 'backdrop',
        switch format
          when 'markdown'
            'gfm-math'  ## Git-flavored Markdown, plus our math extensions
          when 'html'
            'html-math'
          when 'latex'
            'stex'
          else
            format
      editor.setOption 'mode', 'spell-checker'
    editorKeyboard = (editor, keyboard) ->
      editor.setOption 'keyMap',
        switch keyboard
          when 'normal'
            'default'
          else
            keyboard
  when 'ace'
    editorMode = (editor, format) ->
      editor.getSession().setMode "ace/mode/#{format}"
    editorKeyboard = (editor, keyboard) ->
      editor.setKeyboardHandler(
        switch keyboard
          when 'normal'
            ''
          else
            "ace/keyboard/#{keyboard}"
      )

@dropdownToggle = (e) ->
  #$(e.target).parent().dropdown 'toggle'
  $(e.target).parents('.dropdown-menu').first().parent().find('.dropdown-toggle').dropdown 'toggle'

@routeMessage = ->
  Router.current()?.params?.message

Template.registerHelper 'titleOrUntitled', ->
  titleOrUntitled @

Template.registerHelper 'childrenCount', ->
  return 0 unless @children and @children.length > 0
  msgs = Messages.find
    _id: $in: @children
  .fetch()
  msgs = (msg for msg in msgs when canSee msg)
  msgs.length

Template.registerHelper 'childLookup', (index) ->
  ## Usage:
  ##   each children
  ##     with childLookup @index
  ## Assumes `this` is a String object whose value is a message ID,
  ## and the argument is the index of interation.  Fetches the message,
  ## and populates it with additional `index` and `parent` fields.
  ## In this careful usage, we don't spill reactive dependencies
  ## between parents and children.
  #console.log 'looking up', @valueOf()
  msg = Messages.findOne @valueOf()
  return msg unless msg
  ## Use canSee to properly fake non-superuser mode.
  return unless canSee msg
  ## Import _id information from parent nonreactively.
  ## If we get reparented, a totally new template should get created,
  ## so we don't need to be reactive to changes to parentData.
  parentData = Tracker.nonreactive -> Template.parentData()
  msg.parent = parentData._id
  #msg.depth = parentData.depth
  msg.index = index
  msg

Template.registerHelper 'tags', ->
  sortTags @tags

Template.registerHelper 'linkToTag', ->
  #pathFor 'tag',
  #  group: Template.parentData().group
  #  tag: @key
  pathFor 'search',
    group: Template.parentData().group
    search: "tag:#{@key}"

Template.registerHelper 'folded', ->
  (not here @_id) and messageFolded.get @_id

Template.rootHeader.helpers
  root: ->
    if @root
      Messages.findOne @root

Template.registerHelper 'formatTitle', ->
  formatTitleOrFilename @, false

Template.registerHelper 'formatTitleOrUntitled', ->
  formatTitleOrFilename @, true

Template.registerHelper 'formatBody', ->
  formatBody @format, @body

Template.registerHelper 'formatFile', ->
  formatFile @

Template.messageBad.helpers
  message: -> Router.current().params.message

orphans = (message) ->
  descendants = []
  Messages.find
    $or: [
      root: message
    , _id: message
    ]
  .forEach (descendant) ->
    descendants.push descendant.children... if descendant.children?
  Messages.find
    root: message
    _id: $nin: descendants

authorCountHelper = (field) -> ->
  authors =
    for username, count of Session.get field
      continue unless count
      user: findUsername(username) ? username: username
      count: count
  authors = _.sortBy authors, (author) -> userSortKey author.user
  authors = _.sortBy authors, (author) -> -author.count
  authors =
    for author in authors
      "#{linkToAuthor @group, author.user} (#{author.count})"
  authors.join ', '

Template.message.helpers
  authors: authorCountHelper 'threadAuthors'
  mentions: authorCountHelper 'threadMentions'
  subscribers: ->
    users =
      for user in sortedMessageSubscribers @_id
        linkToAuthor @group, user
    if users.length > 0
      users.join ', '
    else
      '(none)'
  nonsubscribers: ->
    subscribers = messageSubscribers @_id,
      fields: username: true
    subscribed = {}
    for user in subscribers
      subscribed[user.username] = true
    users = sortedMessageReaders @_id,
      fields:
        username: true
        emails: true
        roles: true
        rolesPartial: true
        'profile.notifications': true
    (for user in users when user.username not of subscribed
      unless user.emails?[0]?
        title = "No email address"
      else if not user.emails[0].verified
        title = "Unverified email address #{user.emails[0].address}"
      else if not (user.profile.notifications?.on ? defaultNotificationsOn)
        title = "Notifications turned off"
      else if not autosubscribe @group, user
        title = "Autosubscribe turned off, and not explicitly subscribed to thread"
      else
        title = "Explicitly unsubscribed from thread"
      linkToAuthor @group, user.username, title
    ).join ', '
  orphans: ->
    orphans @_id
  orphanCount: ->
    count = orphans(@_id).count()
    if count > 0
      pluralize count, 'orphaned subthread'

Template.message.onCreated ->
  @autorun ->
    setTitle titleOrUntitled Template.currentData()

Template.message.onRendered ->
  $('body').scrollspy
    target: 'nav.contents'
  $('nav.contents').affix
    offset: top: $('#top').outerHeight true
  $('.affix-top').height $(window).height() - $('#top').outerHeight true
  $(window).resize ->
    $('.affix-top').height $(window).height() - $('#top').outerHeight true
  $('nav.contents').on 'affixed.bs.affix', ->
    $('.affix').height $(window).height()
  $('nav.contents').on 'affixed-top.bs.affix', ->
    $('.affix-top').height $(window).height() - $('#top').outerHeight true
  tooltipInit()

  ## Give focus to first Title input, if there is one.
  setTimeout ->
    $('input.title').first().focus()
  , 100

editing = (self) ->
  Meteor.user()? and Meteor.user().username in (self.editing ? [])

idle = 1000   ## one second

messageClass = ->
  if @deleted
    'deleted'
  else if not @published
    'unpublished'
  else if @private
    'private'
  else if @minimized
    'minimized'
  else
    'published'

Template.registerHelper 'messageClass', messageClass

submessageCount = 0

messageRaw = new ReactiveDict
export messageFolded = new ReactiveDict
messageHistory = new ReactiveDict
messageKeyboard = new ReactiveDict
messagePreview = new ReactiveDict
@messagePreviewDefault = ->
  profile = Meteor.user().profile?.preview
  on: profile?.on ? true
  sideBySide: profile?.sideBySide ? false
## The following helpers should only be called when editing.
## They can be called in two settings:
##   * Within the submessage template, and possibly within a `with nothing`
##     data environment.  In this case, we use the `editing` ReactiveVar
##     to get the message ID, because we should be editing.
##   * From the betweenEditorAndBody subtemplate.  Then we can use `_id` data.
messagePreviewGet = ->
  if Template.instance().editing?
    id = Template.instance().editing.get()
  else
    id = Template.currentData()._id
  return unless id
  messagePreview.get(id) ? messagePreviewDefault()
messagePreviewSet = (change) ->
  if Template.instance().editing?
    id = Template.instance().editing.get()
  else
    id = Template.currentData()._id
  return unless id
  preview = messagePreview.get(id) ? messagePreviewDefault()
  messagePreview.set id, change preview

export messageFoldHandler = (e, t) ->
  e.preventDefault()
  e.stopPropagation()
  messageFolded.set @_id, not messageFolded.get @_id

threadAuthors = {}
threadMentions = {}

Template.submessage.onCreated ->
  @count = submessageCount++
  @editing = new ReactiveVar null
  @editTitle = new ReactiveVar null
  @editBody = new ReactiveVar null
  @autorun =>
    data = Template.currentData()
    return unless data?
    #@myid = data._id
    if editing data
      @editing.set data._id
      @editTitle.set data.title
      @editBody.set data.body
    else
      @editing.set null

    threadAuthors[author] -= 1 for author in @authors if @authors?
    threadMentions[author] -= 1 for author in @mentions if @mentions?
    @authors = (unescapeUser author for author of data.authors)
    for author in @authors
      threadAuthors[author] ?= 0
      threadAuthors[author] += 1
    Session.set 'threadAuthors', threadAuthors
    @mentions = atMentions data
    for author in @mentions
      threadMentions[author] ?= 0
      threadMentions[author] += 1
    Session.set 'threadMentions', threadMentions

    #console.log 'automathjax'
    automathjax()

#Session.setDefault 'images', {}
images = {}
imagesInternal = {}
id2template = {}
scrollToLater = null
fileQuery = null

updateFileQuery = _.debounce ->
  fileQuery.stop() if fileQuery?
  fileQuery = Messages.find
    _id: $in: _.keys images
  ,
    fields: file: true
  .observeChanges
    added: (id, fields) ->
      images[id].file = fields.file
      initImageInternal images[id].file, id if images[id].file?
    changed: (id, fields) ->
      if fields.file? and images[id].file != fields.file
        if fileType(fields.file) in ['image', 'video']
          forceImgReload urlToFile id
        imagesInternal[images[id].file].image = null if images[id].file?
        images[id].file = fields.file
        initImageInternal images[id].file, id if images[id].file?
, 50

initImage = (id) ->
  if id not of images
    images[id] =
      count: 0
      file: null
    updateFileQuery()

initImageInternal = (id, image = null) ->
  if id not of imagesInternal
    imagesInternal[id] =
      count: 0
      image: image
  else if image?
    imagesInternal[id].image = image

checkImage = (id) ->
  return unless id of images
  ## Image gets unnaturally folded if it's referenced at least once.
  messageFolded.set id, images[id].naturallyFolded or
    images[id].count > 0 or
    (imagesInternal[images[id].file]? and
     imagesInternal[images[id].file].count > 0)
  ## No longer care about this image if it's not referenced and doesn't have
  ## a rendered template.
  if images[id].count == 0 and id not of id2template
    delete images[id]
    updateFileQuery()

checkImageInternal = (id) ->
  image = imagesInternal[id].image
  checkImage image if image?

messageDrag = (target, bodyToo = true, old) ->
  return unless target
  onDragStart = (e) =>
    #url = "coauthor:#{@data._id}"
    url = urlFor 'message',
      group: @data.group
      message: @data._id
    e.dataTransfer.effectAllowed = 'linkMove'
    e.dataTransfer.setData 'text/plain', url
    e.dataTransfer.setData 'application/coauthor-id', @data._id
    e.dataTransfer.setData 'application/coauthor-type', type
  type = 'message'
  if @data.file
    type = fileType @data.file
    #console.log @data.file, type
    #if "class='odd-file'" not in formatted and
    #   "class='bad-file'" not in formatted
    #  url = formatted
    if bodyToo
      $(@find '.message-file')?.find('img, video, a, canvas')?.each (i, elt) =>
        elt.removeEventListener 'dragstart', old if old?
        elt.addEventListener 'dragstart', onDragStart
  target.removeEventListener 'dragstart', old if old?
  target.addEventListener 'dragstart', onDragStart
  onDragStart

## A message is "naturally" folded if it is flagged as minimized or deleted.
## It still will be default-folded if it's an image referenced in another
## message that is not naturally folded.
export naturallyFolded = (data) -> data.minimized or data.deleted

Template.submessage.onRendered ->
  ## Random message background color (to show nesting).
  #@firstNode.style.backgroundColor = '#' +
  #  Math.floor(Math.random() * 25 + 255 - 25).toString(16) +
  #  Math.floor(Math.random() * 25 + 255 - 25).toString(16) +
  #  Math.floor(Math.random() * 25 + 255 - 25).toString(16)

  ## Drag/drop support.
  focusButton = $(@find '.message-left-buttons').find('.focusButton')[0]
  @autorun =>
    listener = messageDrag.call @, focusButton, true, listener

  ## Fold naturally folded (minimized and deleted) messages
  ## by default on initial load.
  messageFolded.set @data._id, true if natural = naturallyFolded @data

  ## Fold referenced attached files by default on initial load.
  #@$.children('.panel').children('.panel-body').find('a[href|="/file/"]')
  #console.log @$ 'a[href|="/file/"]'
  scrollToMessage @data._id if scrollToLater == @data._id
  #images = Session.get 'images'
  @images = {}
  @imagesInternal = {}
  @autorun =>
    data = Template.currentData()
    return unless data._id
    initImage data._id
    ## initImage calls updateFileQuery which will do this:
    #images[data._id].file = data.file
    #initImageInternal data.file if data.file?
    id2template[data._id] = @
    ## If message is naturally folded, don't count images it references.
    images[data._id].naturallyFolded = naturallyFolded data
    if images[data._id].naturallyFolded
      for id of @images
        images[id].count -= 1
        checkImage id
      @images = {}
      for id of @imagesInternal
        imagesInternal[id].count -= 1
        checkImageInternal id
      @imagesInternal = {}
    else
      newImages = {}
      newImagesInternal = {}
      $($.parseHTML("<div>#{formatBody data.format, data.body}</div>"))
      .find """
        img[src^="#{fileUrlPrefix}"],
        img[src^="#{fileAbsoluteUrlPrefix}"],
        img[src^="#{internalFileUrlPrefix}"],
        img[src^="#{internalFileAbsoluteUrlPrefix}"],
        video source[src^="#{fileUrlPrefix}"],
        video source[src^="#{fileAbsoluteUrlPrefix}"],
        video source[src^="#{internalFileUrlPrefix}"],
        video source[src^="#{internalFileAbsoluteUrlPrefix}"]
      """
      .each ->
        src = @getAttribute('src')
        if 0 <= src.indexOf 'gridfs'
          newImagesInternal[url2internalFile src] = true
        else
          newImages[url2file src] = true
      for id of @images
        unless id of newImages
          images[id].count -= 1
          checkImage id
      for id of newImages
        unless id of @images
          #console.log 'source', id
          initImage id
          images[id].count += 1
          checkImage id
      @images = newImages
      for id of @imagesInternal
        unless id of newImagesInternal
          imagesInternal[id].count -= 1
          checkImageInternal id
      for id of newImagesInternal
        unless id of @imagesInternal
          #console.log 'source', id
          initImageInternal id
          imagesInternal[id].count += 1
          checkImageInternal id
      @imagesInternal = newImagesInternal

  ## Image rotation
  @autorun =>
    data = Template.currentData()
    messageImageTransform.call @
  window.addEventListener 'resize',
    _.debounce (=> messageImageTransform.call @), 100

## Cache EXIF orientations, as files should be static
image2orientation = {}
@messageRotate = (data) ->
  if data.file not of image2orientation
    file = findFile data.file
    if file
      image2orientation[data.file] = file.metadata?.exif?.Orientation
  exifRotate = Orientation2rotate[image2orientation[data.file]]
  (data.rotate ? 0) + (exifRotate ? 0)

## Callable from `submessage` and `readMessage` templates
@messageImageTransform = ->
  return unless @data?

  ## Transform any images embedded within message body
  for img in @findAll """
    .message-body img[src^="#{fileUrlPrefix}"],
    .message-body img[src^="#{fileAbsoluteUrlPrefix}"]
  """
    message = findMessage url2file img.src
    continue unless message
    imageTransform img, messageRotate message

  ## Transform image file, respecting history
  data = messageHistory.get(@data._id) ? @data
  if data.file and 'image' == fileType data.file
    image = @find '.message-file img'
    return unless image?
    imageTransform image, messageRotate data

scrollDelay = 750

@scrollToMessage = (id) ->
  if id of id2template
    template = id2template[id]
    $.scrollTo template.firstNode, scrollDelay,
      easing: 'swing'
      onAfter: ->
        $(template.find 'input.title').focus()
  else
    scrollToLater = id

Template.submessage.onDestroyed ->
  delete id2template[@data._id]
  checkImage @data._id
  for id of @images ? {}
    if id of images
      images[id].count -= 1
      checkImage id

  threadAuthors[author] -= 1 for author in @authors if @authors?
  Session.set 'threadAuthors', threadAuthors
  threadMentions[author] -= 1 for author in @mentions if @mentions?
  Session.set 'threadMentions', threadMentions

historify = (x, post) -> () ->
  history = messageHistory.get @_id
  value =
    if history?
      history[x]
    else
      @[x]
  if post?
    value = post value
  value

tabindex = (i) -> 
  1 + 20 * Template.instance().count + parseInt(i ? 0)

absentTags = ->
  data = Template.currentData()
  Tags.find
    group: data.group
    key: $nin: _.keys data.tags ? {}
    deleted: false
  ,
    sort: ['key']

here = (id) ->
  id? and Router.current().route?.getName() == 'message' and
  Router.current().params?.message == id

Template.submessage.helpers
  canReply: -> canPost @group, @_id
  tabindex: tabindex
  tabindex5: -> tabindex 5
  tabindex7: -> tabindex 7
  tabindex9: -> tabindex 9
  here: -> here @_id
  nothing: {}
  editingRV: -> Template.instance().editing.get()
  editingNR: -> Tracker.nonreactive -> Template.instance().editing.get()
  editData: ->
    #_.extend @,
    _id: @_id
    title: @title
    body: @body
    group: @group
    editing: @editing  ## to list other editors
    editTitle: Template.instance().editTitle.get()
    editBody: Template.instance().editBody.get()
  hideIfEditing: ->
    if Template.instance().editing.get()
      'hidden'
    else
      ''
  #myid: -> Tracker.nonreactive -> Template.instance().myid
  #editing: -> editing @
  config: ->
    ti = Tracker.nonreactive -> Template.instance()
    (editor) =>
      #console.log 'config', editor.getValue(), '.'
      ti.editor = editor
      switch sharejsEditor
        when 'cm'
          editor.getInputField().setAttribute 'tabindex', 1 + 20 * ti.count + 19
          ## styleActiveLine is currently buggy on Android.
          if 0 > navigator.userAgent.toLowerCase().indexOf 'android'
            editor.setOption 'styleActiveLine', true
          editor.setOption 'matchBrackets', true
          editor.setOption 'lineWrapping', true
          editor.setOption 'lineNumbers', true
          editor.setOption 'showCursorWhenSelecting', true
          editor.setOption 'matchBrackets', true
          editor.setOption 'foldGutter', true
          editor.setOption 'gutters', [
            'CodeMirror-linenumbers'
            'CodeMirror-foldgutter'
          ]
          editor.setOption 'theme',
            switch theme()
              when 'dark'
                'blackboard'
              when 'light'
                'eclipse'
              else
                theme()
          editor.setOption 'extraKeys',
            Enter: 'newlineAndIndentContinueMarkdownList'
            End: 'goLineRight'
            Home: 'goLineLeft'
          cmDrop = editor.display.dragFunctions.drop
          editor.setOption 'dragDrop', false
          editor.display.dragFunctions.drop = (e) ->
            #text = e.dataTransfer.getData 'text'
            id = e.dataTransfer?.getData 'application/coauthor-id'
            username = e.dataTransfer?.getData 'application/coauthor-username'
            type = e.dataTransfer?.getData 'application/coauthor-type'
            if id or username
              e.preventDefault()
              e = _.omit e, 'dataTransfer', 'preventDefault'
              e.defaultPrevented = false
              e.preventDefault = ->
              e.dataTransfer =
                getData: ->
                  if username
                    return "@#{username}"
                  switch type
                    when 'image', 'video', 'pdf'
                      switch ti.data.format
                        when 'markdown'
                          "![](coauthor:#{id})"
                        when 'latex'
                          "\\includegraphics{coauthor:#{id}}"
                        when 'html'
                          """<img src="coauthor:#{id}">"""
                    #when 'video'
                    #  """<video controls><source src="coauthor:#{id}"></video>"""
                    else
                      "coauthor:#{id}"
            cmDrop e
          editor.setOption 'dragDrop', true

          paste = null
          editor.on 'paste', (cm, e) ->
            paste = null
            if 'text/html' in e.clipboardData.types
              paste = e.clipboardData.getData 'text/html'
              .replace /<!--.*?-->/g, ''
              .replace /<\/?(html|head|body|meta)\b[^<>]*>/ig, ''
              .replace /<b\s+style="font-weight:\s*normal[^<>]*>([^]*?)<\/b>/ig, '$1'
              .replace /<span\s+style="([^"]*)"[^<>]*>([^]*?)<\/span>/ig, (match, style, body) ->
                body = "<i>#{body}</i>" if style.match /font-style:\s*italic/
                body = "<b>#{body}</b>" if style.match /font-weight:\s*[6789]00/
                body
              .replace /(\s+)(<\/i>(<\/b>)?|<\/b>)/, '$2$1'
              .replace /<(p|li) dir="ltr"/ig, '<$1'
              .replace /<(\w+[^<>]*) class=("[^"]*"|'[^']*')/ig, '<$1'
              .replace /<(p|li|ul|pre) style=("[^"]*"|'[^']*')/ig, '<$1'
              .replace /<\/(p|li)>/ig, ''
              .replace /(<li[^<>]*>)<p>/ig, '$1'
              .replace /<(li|ul|\/ul|br|p)\b/ig, '\n$&'
              .replace /&quot;/ig, '"'
              if (match = /^\s*<pre[^<>]*>([^]*)<\/pre>\s*$/.exec paste) and
                 0 > match[1].indexOf '<pre>'
                ## Treat a single <pre> block (such as pasted from Raw view)
                ## like a text paste, after parsing basic &chars;
                paste = match[1]
                .replace /&lt;/g, '<'
                .replace /&gt;/g, '>'
                .replace /&amp;/g, '&'
                .split /\r\n?|\n/
              else
                paste = paste.split /\r\n?|\n/
                ## Remove blank lines
                paste = (line for line in paste when line.length)
            else if 'text/plain' in e.clipboardData.types
              text = e.clipboardData.getData 'text/plain'
              if match = parseCoauthorMessageUrl text
                paste = ["coauthor:#{match.message}"]
              else if match = parseCoauthorAuthorUrl text
                paste = ["@#{match.author}"]
          editor.on 'beforeChange', (cm, change) ->
            if change.origin == 'paste' and paste?
              change.text = paste
              paste = null

        when 'ace'
          editor.textInput.getElement().setAttribute 'tabindex', 1 + 20 * ti.count + 19
          #editor.meteorData = @  ## currently not needed, also dunno if works
          editor.$blockScrolling = Infinity
          #editor.on 'change', onChange
          editor.setTheme 'ace/theme/' +
            switch theme()
              when 'dark'
                'vibrant_ink'
              when 'light'
                'chrome'
              else
                theme()
          editor.setShowPrintMargin false
          editor.setBehavioursEnabled true
          editor.setShowFoldWidgets true
          editor.getSession().setUseWrapMode true
          #editor.setOption 'spellcheck', true
          #editor.container.addEventListener 'drop', (e) =>
          #  e.preventDefault()
          #  if id = e.dataTransfer.getData('application/coauthor')
          #    #switch @format
          #    #  when 'latex'
          #    #    e.dataTransfer.setData('text/plain', "\\href{#{id}}{}")
          #    e.dataTransfer.setData('text/plain', "<IMG SRC='coauthor:#{id}'>")
      editor.on 'change',
        _.debounce => ti.editBody.set editor.getDoc().getValue()
      , 100
      editorMode editor, ti.data.format
      editorKeyboard editor, messageKeyboard.get(ti.data._id) ? userKeyboard()

  tex2jax: ->
    history = messageHistory.get(@_id) ? @
    if history.format in mathjaxFormats
      'tex2jax'
    else
      ''
  title: historify 'title'
  formatTitle: ->
    history = messageHistory.get(@_id) ? @
    if messageRaw.get @_id
      "<CODE CLASS='raw'>#{_.escape history.title}</CODE>"
    else
      formatTitleOrFilename history, false  ## don't write (untitled)
  formatBody: ->
    #console.log 'rendering', @_id
    history = messageHistory.get(@_id) ? @
    body = history.body
    ## Apply image settings (e.g. rotation) on embedded images and image files
    t = Template.instance()
    Meteor.defer -> messageImageTransform.call t
    return body unless body
    ## Don't show raw view if editing (editor is a raw view)
    if messageRaw.get(@_id) and not Template.instance().editing?.get()
      "<PRE CLASS='raw'>#{_.escape body}</PRE>"
    else
      formatBody history.format, body
  file: historify 'file'
  pdf: ->
    history = messageHistory.get(@_id) ? @
    ## Don't run PDF render if in raw mode
    return if messageRaw.get(@_id) or "pdf" != fileType history.file
    history.file
  image: ->
    history = messageHistory.get(@_id) ? @
    'image' == fileType history.file
  formatFile: ->
    history = messageHistory.get(@_id) ? @
    format = formatFile history
    if messageRaw.get @_id
      "<PRE CLASS='raw'>#{_.escape format}</PRE>"
    else
      format
  formatFileDescription: ->
    formatFileDescription @  ## always editing so not in history

  canEdit: -> canEdit @_id
  canAction: ->
    canEdit @_id
    #canDelete(@_id) or canUndelete(@_id) or canPublish(@_id) or canUnpublish(@_id) or canSuperdelete(@_id) or canPrivate(@_id)
  canDelete: -> canDelete @_id
  canUndelete: -> canUndelete @_id
  canPublish: -> canPublish @_id
  canUnpublish: -> canUnpublish @_id
  canMinimize: -> canMinimize @_id
  canUnminimize: -> canUnminimize @_id
  canSuperdelete: -> canSuperdelete @_id
  canPrivate: -> canPrivate @_id

  history: -> messageHistory.get(@_id)?
  forHistory: ->
    _id: @_id
    history: messageHistory.get @_id

  raw: -> messageRaw.get @_id

  preview: ->
    messageHistory.get(@_id)? or
    (messagePreviewGet() ? on: true).on  ## on if not editing
  sideBySide: -> messagePreviewGet()?.sideBySide
  previewSideBySide: ->
    preview = messagePreviewGet()
    preview?.on and preview?.sideBySide
  sideBySideClass: ->
    if Template.instance().editing
      preview = messagePreviewGet()
      if preview? and preview.on and preview.sideBySide
        'sideBySide'
      else
        ''
    else
      ''  ## no side-by-side if we're not editing

  absentTags: absentTags
  absentTagsCount: ->
    absentTags().count()

Template.messageTags.helpers
  tags: historify 'tags', sortTags

Template.messageLabels.helpers
  deleted: historify 'deleted'
  published: historify 'published'
  minimized: historify 'minimized'
  private: historify 'private'

Template.messageNeighbors.helpers
  prev: ->
    tooltipUpdate()
    messageNeighbors(@)?.prev
  next: ->
    tooltipUpdate()
    messageNeighbors(@)?.next

Template.belowEditor.helpers
  preview: -> messagePreviewGet()?.on
  sideBySide: -> messagePreviewGet()?.sideBySide
  saved: ->
    @title == @editTitle and @body == @editBody
  otherEditors: ->
    others = _.without @editing, Meteor.user()?.username
    if others.length > 0
      " Editing with #{(linkToAuthor @group, other for other in others).join ', '}."
    else
      ''

panelClass =
  deleted: 'panel-danger'
  unpublished: 'panel-warning'
  private: 'panel-info'
  minimized: 'panel-success'
  published: 'panel-primary'
Template.registerHelper 'messagePanelClass', ->
  #console.log 'rendering', @_id, @
  classes = []
  classes.push mclass = messageClass.call @
  classes.push panelClass[mclass]
  if Template.instance().editing?.get()
    classes.push 'editing'
  classes.join ' '

Template.registerHelper 'formatCreator', ->
  linkToAuthor @group, @creator

Template.registerHelper 'creator', ->
  displayUser @creator

Template.registerHelper 'formatAuthors', ->
  a = for own author, date of @authors when author != @creator or date.getTime() != @created.getTime()
        "#{linkToAuthor @group, unescapeUser author} #{formatDate date, 'on '}"
  if a.length > 0
    ', edited by ' + a.join ", "

Template.keyboardSelector.helpers
  keyboard: ->
    if @_id?
      capitalize messageKeyboard.get(@_id) ? userKeyboard()
    else  ## Settings
      capitalize (@keyboard ? defaultKeyboard)
  activeKeyboard: (match) ->
    active =
      if @_id?
        (messageKeyboard.get(@_id) ? userKeyboard()) == match
      else  ## Settings
        (@keyboard ? defaultKeyboard) == match
    if active
      'active'
    else
      ''

Template.submessage.events
  'click .tagRemove': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    tags = t.data.tags
    tag = e.currentTarget.getAttribute 'data-tag'
    if tag of tags
      delete tags[escapeTag tag]
      Meteor.call 'messageUpdate', message,
        tags: tags
      Meteor.call 'tagDelete', t.data.group, tag, true
    else
      console.warn "Attempt to delete nonexistant tag '#{tag}' from message #{message}"

  'click .tagAdd': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    tags = t.data.tags
    tag = e.target.getAttribute 'data-tag'
    if tag of tags
      console.warn "Attempt to add duplicate tag '#{tag}' to message #{message}"
    else
      tags[escapeTag tag] = true
      Meteor.call 'messageUpdate', message,
        tags: tags
    dropdownToggle e

  'click .tagAddNew': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    tags = t.data.tags ? {}
    textTag = $(e.target).parents('form').first().find('.tagAddText')[0]
    tag = textTag.value.trim()
    textTag.value = ''  ## reset custom tag
    if tag
      if tag of tags
        console.warn "Attempt to add duplicate tag '#{tag}' to message #{message}"
      else
        Meteor.call 'tagNew', t.data.group, tag, 'boolean'
        tags[escapeTag tag] = true
        Meteor.call 'messageUpdate', message,
          tags: tags
    dropdownToggle e
    false  ## prevent form from submitting

  'click .foldButton': messageFoldHandler

  'click .rawButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    messageRaw.set @_id, not messageRaw.get @_id

  'click .editButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id  #e.target.getAttribute 'data-message'
    if editing @
      Meteor.call 'messageEditStop', message
    else
      Meteor.call 'messageEditStart', message

  'click .togglePreview': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    messagePreviewSet (preview) -> _.extend {}, preview,
      on: not preview.on

  'click .sideBySidePreview': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    messagePreviewSet (preview) -> _.extend {}, preview,
      sideBySide: not preview.sideBySide

  'click .publishButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    ## Stop editing if we are publishing.
    #if not @published and editing @
    #  Meteor.call 'messageEditStop', message
    Meteor.call 'messageUpdate', message,
      published: not @published
    dropdownToggle e

  'click .deleteButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    messageFolded.set message, not @deleted or @minimized or images[@_id]?.count > 0
    ## Stop editing if we are deleting.
    if not @deleted and editing @
      Meteor.call 'messageEditStop', message
    Meteor.call 'messageUpdate', message,
      deleted: not @deleted
    dropdownToggle e

  'click .privateButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    Meteor.call 'messageUpdate', message,
      private: not @private
    dropdownToggle e

  'click .minimizeButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    messageFolded.set message, @deleted or not @minimized or images[@_id]?.count > 0
    Meteor.call 'messageUpdate', message,
      minimized: not @minimized
    dropdownToggle e

  'click .editorKeyboard': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    messageKeyboard.set @_id, kb = e.target.getAttribute 'data-keyboard'
    editorKeyboard t.editor, kb
    dropdownToggle e

  'click .editorFormat': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    Meteor.call 'messageUpdate', t.data._id,
      format: format = e.target.getAttribute 'data-format'
    editorMode Template.instance().editor, format
    dropdownToggle e

  'input input.title': (e, t) ->
    e.stopPropagation()
    message = t.data._id
    Meteor.clearTimeout t.timer
    t.editTitle.set e.target.value
    t.timer = Meteor.setTimeout ->
      Meteor.call 'messageUpdate', message,
        title: e.target.value
    , idle

  'click .replyButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = @_id
    if canPost @group, @_id
      msg = {}
      privacy = e.target.getAttribute 'data-privacy'
      switch privacy
        when 'public'
          msg.private = false
        when 'private'
          msg.private = true
      Meteor.call 'messageNew', @group, @_id, null, msg, (error, result) ->
        if error
          console.error error
        else if result
          Meteor.call 'messageEditStart', result
          scrollToMessage result
          #Router.go 'message', {group: group, message: result}
        else
          console.error "messageNew did not return problem -- not authorized?"

  'click .historyButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    if messageHistory.get(@_id)?
      messageHistory.set @_id, null
    else
      messageHistory.set @_id, _.clone @

  'click .superdeleteButton': (e) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.show 'superdelete', @

  'click .replaceButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()

Template.superdelete.events
  'click .shallowSuperdeleteButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.hide()
    Meteor.call 'messageSuperdelete', t.data._id
  'click .deepSuperdeleteButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.hide()
    recurse = (message) ->
      msg = Messages.findOne message
      for child in msg.children
        recurse child
      Meteor.call 'messageSuperdelete', message
    recurse t.data._id
  'click .cancelButton': (e) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.hide()

Template.messageHistory.onCreated ->
  @diffsub = @subscribe 'messages.diff', @data._id

Template.messageHistory.onRendered ->
  @autorun =>
    diffs = MessagesDiff.find
        id: @data._id
      ,
        sort: ['updated']
      .fetch()
    return if diffs.length < 2  ## don't show a zero-length slider
    ## Accumulate diffs
    for diff, i in diffs
      if i >= 0
        for own key, value of diffs[i-1]
          unless key of diff
            diff[key] = value
      ## Remove diff IDs
      delete diff._id
    @slider?.destroy()
    `import('bootstrap-slider')`.then (Slider) =>
      Slider = Slider.default
      @slider = new Slider @$('input')[0],
        #min: 0                 ## min and max not needed when using ticks
        #max: diffs.length-1
        #value: diffs.length-1  ## doesn't update, unlike setValue method below
        ticks: [0...diffs.length]
        ticks_snap_bounds: 999999999
        tooltip: 'always'
        tooltip_position: 'bottom'
        formatter: (i) ->
          if i of diffs
            formatDate(diffs[i].updated) + '\n' + diffs[i].updators.join ', '
          else
            i
      @slider.setValue diffs.length-1
      #@slider.off 'change'
      @slider.on 'change', (e) =>
        messageHistory.set @data._id, diffs[e.newValue]
    messageHistory.set @data._id, diffs[diffs.length-1]

uploader = (template, button, input, callback) ->
  Template[template].events {
    "click .#{button}": (e, t) ->
      e.preventDefault()
      e.stopPropagation()
      t.find(".#{input}").click()
    "change .#{input}": (e, t) ->
      callback e.target.files, e, t
      e.target.value = ''
    "dragenter .#{button}": (e) ->
      e.preventDefault()
      e.stopPropagation()
    "dragover .#{button}": (e) ->
      e.preventDefault()
      e.stopPropagation()
    "drop .#{button}": (e, t) ->
      e.preventDefault()
      e.stopPropagation()
      callback e.originalEvent.dataTransfer.files, e, t
  }

attachFiles = (files, e, t) ->
  message = t.data._id
  group = t.data.group
  callbacks = {}
  called = 0
  ## Start all file uploads simultaneously.
  for file, i in files
    do (i) ->
      file.callback = (file2, done) ->
        ## Set up callback for when this file is completed.
        callbacks[i] = ->
          Meteor.call 'messageNew', group, message, null,
            file: file2.uniqueIdentifier
          , done
        ## But call all the callbacks in order by file, so that replies
        ## appear in the correct order.
        while callbacks[called]?
          callbacks[called]()
          called += 1
    file.group = group
    Files.resumable.addFile file, e

uploader 'messageAttach', 'attachButton', 'attachInput', attachFiles

replaceFiles = (files, e, t) ->
  message = t.data._id
  group = t.data.group
  if files.length != 1
    console.error "Attempt to replace #{message} with #{files.length} files -- expected 1"
  else
    file = files[0]
    file.callback = (file2, done) ->
      diff =
        file: file2.uniqueIdentifier
      ## Reset rotation angle on replace
      data = findMessage message
      if data.rotate
        diff.rotate = 0
      Meteor.call 'messageUpdate', message, diff, done
    file.group = group
    Files.resumable.addFile file, e

uploader 'messageReplace', 'replaceButton', 'replaceInput', replaceFiles

Template.messageAuthor.helpers
  creator: ->
    "!" + @creator

privacyOptions = [
  code: 'public'
  list: ['public']
  display: 'Public messages only (usual behavior)'
,
  code: 'both'
  list: ['public', 'private']
  display: 'Public and private messages (for feedback)'
,
  code: 'private'
  list: ['private']
  display: 'Private messages only (for solved problems)'
]
privacyOptionsByCode = {}
for option in privacyOptions
  privacyOptionsByCode[option.code] = option

Template.threadPrivacy.helpers
  privacyOptions: privacyOptions
  active: ->
    if _.isEqual(_.sortBy(privacyOptionsByCode[@code].list),
                 _.sortBy(Template.parentData(2).threadPrivacy ? ['public']))
      'active'
    else
      ''

Template.threadPrivacy.events
  #'click .threadPrivacyToggle': (e, t) ->
  #  e.preventDefault()
  #  e.stopPropagation()  ## prevent propagation to top-level dropdown
  #  console.log e.target
  #  $(e.target).dropdown 'toggle'
  'click .threadPrivacy': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    Meteor.call 'threadPrivacy', Template.parentData()._id,
      privacyOptionsByCode[e.target.getAttribute 'data-code'].list
    dropdownToggle e

Template.emojiButtons.helpers
  canReply: -> canPost @group, @_id
  emoji: -> Emoji.find group: $in: [wildGroup, @group]
  emojiMessages: ->
    tooltipUpdate()
    emojiReplies @
  who: -> (displayUser user for user in @who).join ', '

Template.emojiButtons.events
  'click .emojiAdd': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    symbol = e.currentTarget.getAttribute 'data-symbol'
    #exists = EmojiMessages.findOne
    #  message: message
    #  creator: Meteor.user().username
    #  symbol: symbol
    #  deleted: false
    exists = Meteor.user().username in (t.data.emoji?[symbol] ? [])
    if exists
      console.warn "Attempt to add duplicate emoji '#{symbol}' to message #{message}"
    else
      Meteor.call 'emojiToggle', message, symbol
    dropdownToggle e

  'click .emojiToggle:not(.disabled)': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    tooltipHide t
    message = t.data._id
    symbol = e.currentTarget.getAttribute 'data-symbol'
    Meteor.call 'emojiToggle', message, symbol

Template.replyButtons.helpers
  canReply: -> canPost @group, @_id
  canPublicReply: -> 'public' in (@threadPrivacy ? ['public'])
  canPrivateReply: -> 'private' in (@threadPrivacy ? ['public'])

Template.tableOfContentsMessage.onRendered ->
  @autorun =>
    listener = messageDrag.call @, @find('a'), false, listener

addDragOver = (e) ->
  e.preventDefault()
  e.stopPropagation()
  $(e.target).addClass 'dragover'

removeDragOver = (e) ->
  e.preventDefault()
  e.stopPropagation()
  $(e.target).removeClass 'dragover'

dragOver = (e) ->
  e.preventDefault()
  e.stopPropagation()

dropOn = (e, t) ->
  e.preventDefault()
  e.stopPropagation()
  $(e.target).removeClass 'dragover'
  dragId = e.originalEvent.dataTransfer?.getData 'application/coauthor-id'
  dropId = e.target.getAttribute 'data-id'
  if dragId and dropId
    messageParent dragId, dropId

dropBefore = (e, t) ->
  e.preventDefault()
  e.stopPropagation()
  $(e.target).removeClass 'dragover'
  dragId = e.originalEvent.dataTransfer?.getData 'application/coauthor-id'
  dropId = e.target.getAttribute 'data-parent'
  index = e.target.getAttribute 'data-index'
  if dragId and dropId and index
    index = parseInt index
    messageParent dragId, dropId, index

for template in [Template.tableOfContentsRoot, Template.tableOfContentsMessage]
  template.events
    "dragenter .onMessageDrop": addDragOver
    "dragleave .onMessageDrop": removeDragOver
    "dragover .onMessageDrop": dragOver
    "dragenter .beforeMessageDrop": addDragOver
    "dragleave .beforeMessageDrop": removeDragOver
    "dragover .beforeMessageDrop": dragOver
    "drop .onMessageDrop": dropOn
    "drop .beforeMessageDrop": dropBefore

messageParent = (child, parent, index = null) ->
  #console.log 'messageParent', child, parent, index
  #Meteor.call 'messageParent', child, parent, index
  return if child == parent  ## ignore trivial self-loop
  childMsg = Messages.findOne child
  parentMsg = Messages.findOne parent
  oldParent = findMessageParent child
  oldIndex = oldParent?.children.indexOf child
  if parentMsg?._id == oldParent?._id
    ## Ignore drag to same place
    return if index == oldIndex or
      (not index? and oldIndex == oldParent.children.length - 1)
    ## If dragging within same parent to a later-numbered child,
    ## need to decrease index by 1 to account for loss of self.
    if index? and index > oldIndex
      index -= 1
      return if index == oldIndex
  Modal.show 'messageParentConfirm',
    child: childMsg
    parent: parentMsg
    oldParent: oldParent
    index: index
    oldIndex: oldIndex

Template.messageParentConfirm.events
  "click .messageParentButton": (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.hide()
    Meteor.call 'messageParent', t.data.child._id, t.data.parent._id, t.data.index
  "click .cancelButton": (e) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.hide()
