#require ST/Object
#require ST/Enumerable
#require ST/Inflector
#request ST/Model/Scope
#request ST/Model/Index

ST.class 'Model', ->  
  @_byUuid       = {}
  @NotFound     = {}
  @GenerateUUID = Math.uuid || (-> null)
  @Storage      = null
  @Debug        = false
  
  @classMethod 'fetch', (uuid, yield) ->
    self = this
            
    if STModel._byUuid[uuid]
      yield STModel._byUuid[uuid]
    else if @FindUrl
      $.ajax {
        url:      @FindUrl.replace('?', uuid)
        type:     'get'
        data:     @FindData || {}
        success:  (data) ->
          model = ST.Model.createWithData data
          yield model
      }
    else
      ST.error "No find URL for model: #{@_name}"
      
  @classDelegate 'where', 'scoped'
  @classDelegate 'order', 'scoped'
  @classDelegate 'each',  'scoped'
  
  @classMethod 'scoped', ->
    ST.Model.Scope.createWithModel this
  
  @classMethod 'find', (uuid) ->
    ST.Model._byUuid[uuid]
  
  @classMethod 'load', (data) ->
    self = this
    if data instanceof Array
      for row in data
        @load row
    else
      return unless data && data.uuid
      return if ST.Model._byUuid[data.uuid]
      @createWithData data
  
  @classMethod 'getIndex', (attribute) ->
    @_indexes ||= {}
    @_indexes[attribute] ||= ST.Model.Index.createWithModelAttribute(this, attribute)
    
  @classMethod 'changes', ->
    ST.Model._changes || []
  
  @classMethod 'saveToServer', (url, async, extraData) ->
    return if ST.Model.Saving
    return unless ST.Model._changes && ST.Model._changes.length
    
    ST.Model.Saving = true
    
    data = { data: JSON.stringify updatedData }
    $.extend data, extraData if extraData
    
    STModel.SaveStarted() if STModel.SaveStarted
    
    $.ajax {
      url:      url
      type:     'post'
      async:    if async? then async; else true
      data:     data,
      success:  (data) ->
        STModel.SaveFinished() if STModel.SaveFinished
        
        if data.status && data.status == 'Access Denied'
          STModel.AccessDeniedHandler() if STModel.AccessDeniedHandler
        
        for type in ['created', 'updated', 'deleted']
          if data[type] && data[type] instanceof Array
            for uuid in data[type]
              object = ST.Model.find uuid
              object.set(type, false).persist() if object
             
      complete: ->
        ST.Model.Saving = false
    }
  
  @initializer (options) ->
    @initWithData {}, options
    this
  
  # Initializes a new model, and loads the supplied attribute data, if any
  @initializer 'withData', (data, options) ->
    self = this
    
    ST.Object.prototype.init.call this
    
    @uuid data.uuid || ST.Model.GenerateUUID()
    @_attributes = {}
    for attribute of @_class.Attributes
      if @_class.Attributes.hasOwnProperty attribute
        @_attributes[attribute] = if data[attribute]?
          data[attribute]
        else
          defaultValue = @_class.Attributes[attribute]
          if typeof defaultValue == 'function'
            new defaultValue()
          else
            defaultValue
    if @_class.ManyBinds
      @_class.ManyBinds.each (binding) ->
        self.get(binding.assoc).bind(binding.from, self, binding.to);
    this
  
  # Creates a new object from model data. If the data includes a 
  # property, as with data genereated by #objectify, the specified model
  # will be used instead of the model createWithData was called on.
  @classMethod 'createWithData', (data, options) ->
    # If data is being sent to the wrong model, transfer to correct model
    if data.model && data.model != @_name
      if (@_namespace[data.model])
        @_namespace[data.model].createWithData data, options
      else
        null
    # If object with uuid already exists, update object and return it
    else if data.uuid && ST.Model._byUuid[data.uuid]
      object = ST.Model._byUuid[data.uuid]
      for attribute of object._attributes
        if object._attributes.hasOwnProperty attribute
          object.set attribute, data[attribute] if data[attribute]?
      object
    # Otherwise, create a new object
    else
      (new this).initWithData data, options
  
  @property 'uuid'
  
  @method 'setUuid', (newUuid) ->
    unless @_uuid    
      # Insert object in global index
      ST.Model._byUuid[newUuid] = this
    
      # Insert object in model-specific index
      @_class._byUuid ||= {}
      @_class._byUuid[newUuid] = this
    
      @_uuid = newUuid
  
  @method 'matches', (conditions) ->
    if @_attributes
      for condition in conditions
        return false unless condition.test @_attributes[condition.attribute]
      true
    else
      false

  # Returns (and creates if needed) a STList to contain objects from
  # a corresponsing one-to-many relationship using a plain array of UUIDs.
  # 
  # When list is created, triggers are bounds so that items added or
  # removed from the list are reflected in the UUIDs array.
  @method 'getManyList', (member) ->
    # Create list if it doesn't already exist
    unless this[member]
      s = ST.singularize member
  
      # Create a new list, with bindings for itemAdded and itemRemoved
      this[member] = ST.List.create()
      this[member].bind 'itemAdded', this, s + 'Added'
      this[member].bind 'itemRemoved', this, s + 'Removed'
  
      # Create new method to update UUIDs on added events
      this[s + 'Added'] = (list, item) ->
        this[s + 'Uuids'].push item
        @persist()
  
      # Create new method to update UUIDs on removed events
      this[s + 'Removed'] = (list, item) ->
        this[s + 'Uuids'].remove item
        @persist()
      
      this[member].find = (mode, options) ->
        if mode == 'first' || mode == 'all'
          all = mode == 'all';
          if options && options.conditions
            filter = (o) -> o.matches options.conditions
            return if all @array.collect filter
            else @array.find filter
          else
            return if all then this; else @objectAtIndex(0)
        else if mode == 'by' || mode == 'all_by'
          conditions = {}
          conditions[arguments[1]] = arguments[2]
          return @find(
            (if mode == 'by' then 'first'; else 'all'),
            {conditions: conditions}
          )
        else
          return this.array.find.apply(this.array, arguments);
      
      this[member + 'NeedsRebuild'] = true
    
    # Rebuild items in list if marked for rebuild
    if this[member + 'NeedsRebuild']
      uuids = this.attributes[ST.singularize(member) + 'Uuids']
      list = this[member]
      
      # Rebuild by accessing array directly, so that we don't fire off
      # our own triggers
      list.array.empty()
      for uuid in uuids
        object = ST.Model._byUuid[uuid]
        list.array.push object if object
      
      this[member + 'NeedsRebuild'] = false
    
    this[member]
  
  @method '_changed', (member, oldValue, newValue) ->
    @super member, oldValue, newValue
    ST.Model._changes ||= []
    ST.Model._changes.push {
      uuid:       ST.Model.GenerateUUID()
      model:      @_class._name
      type:       'update'
      objectUuid: @_uuid
      attribute:  member
      oldValue:   oldValue
      newValue:   newValue
    }
  
  # Returns saveable object containing model data.
  @method 'serialize', ->
    output = {
      model: @_class._name
      uuid:   @getUuid()
    }
    for attribute of @_attributes
      if @_attributes.hasOwnProperty attribute
        value = @_attributes[attribute]
        value = String(value) if value instanceof Date
        output[attribute] = value
    JSON.stringify output
  
  # Saves model data and saved status in Storage for persistance.
  @method 'persist', ->
    if ST.Model.Storage
      ST.Model.Storage.set @uuid(), @serialize()
  
  # Removes all local data for model.
  @method 'forget', ->
    # Remove from global index
    delete ST.Model._byUuid[@_uuid]
    
    # Remove from model index
    delete @_class._byUuid[@_uuid]
    
    # Remove from attribute indexes
    ST.Model.Index.removeObject this

    # Remove from persistant storage
    ST.Model.Storage.remove @_uuid if ST.Model.Storage

  # Marks model as destroyed, destroy to be propagated to server when 
  # possible.
  @method 'destroy', ->
    ST.Model._changes ||= []
    ST.Model._changes.push {
      uuid:       ST.Model.GenerateUUID()
      model:      @_class._name
      type:       'destroy'
      objectUuid: @_uuid
    }
    @forget()

  @classMethod 'attribute', (name, type, defaultValue) ->
    ucName = ST.ucFirst name
    
    @Attributes ||= {}
    @Attributes[name] = defaultValue
    
    @method "set#{ucName}", (newValue) ->
      oldValue = @_attributes[name]
  
      # Set new value
      @_attributes[name] = newValue
  
      # Update index
      if @_class["Index#{ucName}"]
        index = @_class["Index#{ucName}"];
        index[oldValue].remove this if index[oldValue]
        index[newValue] ||= ST.List.create()
        index[newValue].add this
  
      # Trigger changed event
      @_changed name, oldValue, newValue if @_changed
      @trigger 'changed', name, oldValue, newValue
      
      @persist()
    
    @method "get#{ucName}", -> @_attributes[name]
    
    @accessor name
    
    @[name] = {
      equals: (value) ->
        {
          attribute: name
          value: value
          test: (test) -> test == value
        }
    }
    
  for dataType in 'string integer float boolean date datetime'.split(' ')
    @classMethod dataType, (name, defaultValue) ->
      @attribute name, dataType, defaultValue
  
  @classMethod 'belongsTo', (name, assocModel, options={}) ->
    @attribute "#{name}Uuid"
    
    ucName = ST.ucFirst name
    
    @method "get#{ucName}", ->
      uuid = @["#{name}Uuid"]()
      ST.Model._byUuid[uuid] || null
    
    @method "set#{ucName}", (value) ->
      ST.error 'Invalid object specified for association' if value && value._class._name != assocModel
      @set "#{name}Uuid", value && value.uuid()
    
    @accessor name
  
    if options.bind
      setUuidName = "set#{ucName}Uuid"
      oldSet = @prototype[setUuidName]
      @method setUuidName, (value) ->
        oldValue = @_attributes[name]
        unless oldValue == value
          if oldValue.unbind
            for key of options.bind
              oldValue.unbind key, this
          oldSet.call this, value
          if newValue.bind
            for key of options.bind
              oldValue.bind key, this, options.bind[key]

  @classMethod 'hasMany', (name, assocModel, foreign=null, binds={}) ->
    if foreign
      # One-to-many assocation through a Model and foreign key
      @method name, ->
        unless this["_#{name}"]
          model = @_class._namespace.getClass(assocModel)
          this["_#{name}"] = model.where(model["#{foreign}Uuid"].equals(@uuid()))
        this["_#{name}"]
      
      for key of binds
        if binds.hasOwnProperty key
          @ManyBinds ||= []
          @ManyBinds.push {
            assoc:  name
            from:   key
            to:     binds[key]
          }
    else
      # One-to-many association using a Uuids attribute
      attr = "#{ST.singularize name}Uuids"
      ucAttr = ST.ucFirst attr
  
      @Attributes ||= {}
      @Attributes[attr] = Array
  
      #setCustomerUuids
      @method "set#{ucAttr}", (value) ->
        @_attributes[attr] = value
        this["#{name}NeedsRebuild"] = true
        @persist()
  
      #getCustomerUuids
      @method "get#{ucAttr}", -> @_attributes[attr]
      
      @accessor attr

      ucsName = ST.ucFirst ST.singularize(name)
  
      #customers
      @method name, -> @getManyList name
  
      #addCustomer
      @method "add#{ucsName}", (record) ->
        @getManyList(name).add record
        this
    
  @classMethod 'setStorage', (storage) ->
    ST.Model.Storage = storage;
    
    if storage
      # Save any existing models to new storage
      for object in ST.Model._byUuid
        object.persist()
  
      # Load any unloaded saved models from storage
      storage.each (key, value) ->
        if value && value.model && window[value.model] && !STModel.byUuid[key]
          model = ST.Model.createWithData value
          model.created = value._created if value._created?
          model.updated = value._updated if value._updated?
          model.deleted = value._deleted if value._deleted?
          model.approved = value._approved if value._approved?