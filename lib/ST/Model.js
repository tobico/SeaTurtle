#= require ST/Model/Searchable
#= require ST/Model/Callbacks
#= require ST/Model/Validates
#= require ST/Model/Base
#= require ST/Model/Scope
#= require ST/Model/Index

ST.module 'Model', ->
  @_byUuid        = {}
  @_notFound      = {}
  @_generateUUID  = Math.uuid || (-> @NextUUID ||= 0; @NextUUID++)
  @_storage       = null
  @_changes       = {}
  @_changesCount  = 0
  @_changeID      = 1
  @_lastChange    = null
  
  @recordChange = (type, uuid, model, data) ->    
    # If the last change made was also an update to this model, and it hasn't
    # been submitted yet, amend the previous update with additional data
    # instead of making a new one
    if type == 'update' && @_lastChange && @_lastChange.type == 'update' && @_lastChange.uuid == uuid && !@_lastChange.submitted
      for attribute of data
        if data.hasOwnProperty attribute
          @_lastChange.data[attribute] = data[attribute]
    else
      change = {
        type:       type
        uuid:       uuid
        model:      model
        submitted:  false
      }
      change.data = data if data
      @_changes[@_changeID++] = change
      @_changesCount++
      @_lastChange = change
      @_onHasChanges @_changesCount if @_onHasChanges
    true
  
  @sync = (url, async, additionalData=null) ->
    if @_changesCount > 0 && !@_submitting
      @_submitting = true
      @_onSyncStart @_changesCount if @_onSyncStart
      for id of @_changes
        if @_changes.hasOwnProperty id
          @_changes[id].submitted = true
      data = {changes: JSON.stringify(@_changes)}
      $.extend data, additionalData if additionalData
      $.ajax {
        url:      url
        type:     'post'
        async:    async
        data:     data
        success:  (data) =>
          @_submitting = false
          if data.fatal
            @_onFatalError data.fatal if @_onFatalError
          else
            @ackSync data
        error: (xhr, status) =>
          @_submitting = false
          @_onConnectionError status if @_onConnectionError
      }
      true
    else
      false
  
  @autoSync = (url, delegate=null, syncBeforeUnload=false) ->
    window.sync = (async) ->
      ST.Model.sync url, async
    
    @onSyncContinue -> sync true
    @onConnectionError (status) ->
      setTimeout(->
        sync true
      , 5000)
      delegate.onConnectionError status if delegate && delegate.onConnectionError
    @onSyncStart (count) -> delegate.onSyncStart(count) if delegate.onSyncStart
    @onSyncComplete -> delegate.onSyncComplete() if delegate.onSyncComplete
    @onFatalError (status) -> delegate.onFatalError(status) if delegate.onFatalError
    @onSyncError -> delegate.onSyncError() if delegate.onSyncError
    
    @onHasChanges ->
      setTimeout (-> sync true), 100
    
    if syncBeforeUnload
      window.onbeforeunload = (e) ->
        ev = e || window.event
        msg = if window.Connection && !Connection.active
          options.unsavedWarning || 'Unable to save your changes to the server. If you leave now, you will lose your changes.'
        else if ST.Model._submitting
          options.savingWarning || 'Currently writing your changes to the server. If you leave now, you will lose your changes.'
        else
          sync(false)
          undefined
        
        ev.returnValue = msg if ev && msg
        msg
      
      window.forceReload = ->
        window.onbeforeunload = -> null
        location.reload true
    
    sync
  
  @ackSync = (data) ->
    errors = []
    if data.ack
      for id, status of data.ack
        if data.ack.hasOwnProperty id
          change = @_changes[id]
          if status == 'ok'
            delete @_changes[id]
            @_changesCount--
          else if status == 'notfound'
            errors.push "#{change.model} with UUID #{change.uuid} not found"
          else if status == 'unauthorized'
            errors.push "Access denied to #{change.model} with UUID #{change.uuid}"
          else if status == 'exists'
            errors.push "#{change.model} with UUID #{change.uuid} already exists"
          else if status == 'invalid'
            base = "#{change.model} with UUID #{change.uuid} failed to validate"
            if data.errors[id]
              for number, message of data.errors[id]
                errors.push "#{base} with message #{message}"
            else
              errors.push base
      for id of @_changes
        if @_changes.hasOwnProperty(id) && @_changes[id].submitted
          @_changes[id].submitted = false
          @_onSyncError errors if @_onSyncError
          return false
      if @_changesCount
        @_onSyncContinue() if @_onSyncContinue
      else
        @_onSyncComplete() if @_onSyncComplete
      true
    else
      @_onSyncError errors if @_onSyncError
      false
  
  # Event handler - called when changes are available to sync
  @onHasChanges = (fn) ->
    @_onHasChanges = fn

  # Event handler - called when a sync request starts
  @onSyncStart = (fn) ->
    @_onSyncStart = fn

  # Event handler - called when sync request finishes, but there are new changes
  @onSyncContinue = (fn) ->
    @_onSyncContinue = fn

  # Event handler - called when sync request finishes and there are no new changes
  @onSyncComplete = (fn) ->
    @_onSyncComplete = fn

  # Event handler - called when individual changes fail to save with an error
  @onSyncError = (fn) ->
    @_onSyncError = fn
  
  # Event handler - called when a connection to the save URL could not be made
  @onConnectionError = (fn) ->
    @_onConnectionError = fn

  # Event handler - called when a save request fails completely
  @onFatalError = (fn) ->
    @_onFatalError = fn

  @changes = ->
    @_changesCount

  @storage = (newStorage) ->
    self = this
    if newStorage?
      @Storage = storage
      
      if newStorage
        # Save any existing models to new storage
        for object in @_byUuid
          object.persist()

        # Load any unloaded saved models from storage
        storage.each (key, value) ->
          if value && value.model && window[value.model] && !self._byUuid[key]
            model = ST.Model.Base.createWithData value
    else
      @Storage