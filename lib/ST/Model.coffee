ST.class 'Model', ->
  @include 'Enumerable'
  
  @Index        = {}
  @NotFound     = {}
  @GenerateUUID = Math.uuid || (-> null)
  @Storage      = null
  @Debug        = false
  
  @classMethod 'fetch', (uuid, callback) ->
    self = this
            
    if STModel.Index[uuid]
      callback STModel.Index[uuid]
    else if @FindUrl
      $.ajax {
        url:      @FindUrl.replace('?', uuid)
        type:     'get'
        data:     @FindData || {}
        success:  (data) ->
          model = ST.Model.createWithData data
          callback model
      }
    else
      ST.error "No find URL for model: #{@_name}"
  
  @classMethod 'find', (mode, options={}) ->
    self = this
    
    if mode == 'first' || mode == 'all'
      console.log "Finding #{mode} in #{@_name} , with options: #{JSON.stringify options}" if ST.Model.Debug

      found = []
      unless @Index
        return if mode == 'first'
          null
        else
          found
      
      index = false
      nonIndexConditions = 0
      for key of options.conditions
        indexName = "Index #{ST.ucFirst key}"
        if !index && @[indexName]
          value = options.conditions[key]
          if @[indexName][value]
            index = @[indexName][value].array
          else
            console.log "Found empty index for condition: #{key}=#{value}" if ST.Model.Debug
            return if mode == 'first' then null; else []
        else
          nonIndexConditions++
      
      if index
        if nonIndexConditions == 0
          console.log "Indexed result - #{index.length}" if ST.Model.Debug
          if mode == 'first'
            return if index.length then index[0]; else null
          return index
        else
          if ST.Model.Debug
            console.log "Partially-Indexed result"
            console.log options.conditions
          filter = (o) -> o.matches options.conditions
          if mode == 'first'
            index.find filter
          else
            index.collect filter
      else
        console.log 'Unindexed result' if ST.Model.Debug
        for uuid of @Index
          if !@Index[uuid].destroyed && (!options.conditions || @Index[uuid].matches(options.conditions))
            return if mode == 'first'
              @Index[uuid]
            else
              found.push @Index[uuid]
        return if mode == 'first'
          null
        else
          found
    else if mode == 'by' || mode == 'all_by'
      conditions = {}
      conditions[arguments[1]] = arguments[2]
      @find(
          (if mode == 'by' then 'first'; else 'all'),
          {conditions: conditions}
      )
    else if STModel.Index[mode]
      STModel.Index[mode]
    else
      ST.error 'Model not found'
  
  @classMethod 'load', (data) ->
    self = this
    if data instanceof Array
      for row in data
        @load row
    else
      return unless data && data.uuid
      return if STModel.Index[data.uuid]
      @createWithObject data
  
  @classMethod 'buildIndex', (attribute) ->
    indexName = "Index#{ST.ucFirst attribute}"
    return if @[indexName]
    
    index = {}
    for uuid of @Index
      object = @Index[uuid]
      value = object.attributes[attribute]
      index[value] ||= STList.create()
      index[value].add object
    @[indexName] = index
  
  @classMethod 'getValueIndex', (attribute, value) ->
    indexName = "Index#{ST.ucFirst attribute}"
    @buildIndex attribute unless @[indexName]
    
    index = @[indexName];
    index[value] ||= STList.create()
    index[value]
  
  @classMethod 'getUpdatedModelData', ->
    data = {
      created: []
      updated: []
      deleted: []
    }
    for uuid of @Index
      model = @Index[uuid]
      continue if model.$.ReadOnly
      if model.created && model.approved
        data.created.push model.objectify()
      else if model.updated && model.approved
        data.updated.push model.objectify()
      else if model.deleted
        data.deleted.push {
          '_model':   model.$._name
          uuid:       model.getUuid()
        }
    data.created.sort ST.makeSortFn('uuid')
    data
  
  @classMethid 'saveToServer', (url, async, extraData) ->
    return if ST.Model.Saving
    
    updatedData = @getUpdatedModelData()
    
    return null if updatedData.created.length == 0 && updatedData.updated.length == 0 && updatedData.deleted.length == 0
    
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
  
  # Initializes a new model, and loads the supplied attribute data, if any
  @initializer 'withData', (data, options) ->
    self = this
    
    ST.Object.prototype.init.call this
    @approved = true
    @created = !data['uuid']
    @deleted = false
    @setUuid data['uuid'] || ST.Model.GenerateUUID()
    @attributes = {}
    for attribute of @$.Attributes
      if data[attribute]?
        @set attribute, data[attribute]
      else
        defaultValue = @$.Attributes[attribute]
        if typeof defaultValue == 'function'
          @set attribute, new defaultValue()
        else
          @set attribute, defaultValue
    if @$.ManyMany
      @$.ManyMany.each (key) ->
        fullKey = "#{key}Uuids"
        self.attributes[fullKey] = []
        self.attributes[fullKey].append data[fullKey] if data[fullKey]
    if @$.ManyBinds
      @$.ManyBinds.each (binding) ->
        self.get(binding.assoc).bind(binding.from, self, binding.to);

    @updated = false
    @setUuid = null
    @persists = !(options && options.temporary)
    @persist()
  
  # Creates a new object from model data. If the data includes a _model
  # property, as with data genereated by #objectify, the specified model
  # will be used instead of the model createWithData was called on.
  @classMethod 'createWithData', (data, options) ->
    # If data is being sent to the wrong model, transfer to correct model
    if data._model && data._model != @_name
      if (window[data._model])
        window[data._model].createWithData data, options
      else
        null
    # If object with uuid already exists, update object and return it
    else if data.uuid && ST.Model.Index[data.uuid]
      object = STModel.Index[data.uuid]
      object.persists = true unless options && options.temporary
      for attribute of object.attributes
        object.set attribute, data[attribute] if data[attribute]?
      object
    # Otherwise, create a new object
    else
      (new this).initWithData data, options
  
  @property 'uuid'
  
  # These properties specify what changes have been made locally and need
  # to be synchronized to the server.
  #
  # Newly created objects will only be saved if they are marked as
  # approved.
  @property 'created'
  @property 'updated'
  @property 'deleted'
  @property 'approved'
  
  # Makes a new uuid for object.
  @method 'resetId', ->
    this.id = null;
    this.uuid = STModel.GenerateUUID();
  
  @method 'setUuid', (newUuid) ->
    return if newUuid == @uuid
    
    # Insert object in global index
    delete ST.Model.Index[@uuid]
    ST.Model.Index[newUuid] = this
    
    # Insert object in model-specific index
    @$.Index ||= {}
    index = @$.Index
    delete index[@uuid] if index[@uuid]
    index[newUuid] = this
    
    @uuid = newUuid
  
  @method 'matches', (conditions) ->
    if @attributes
      for key of conditions
        if conditions[key] instanceof Function
          return false unless conditions[key](@attributes[key])
        else
          return false unless @attributes[key] == conditions[key]
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
        @setUpdated true
        @persist()
  
      # Create new method to update UUIDs on removed events
      this[s + 'Removed'] = (list, item) ->
        this[s + 'Uuids'].remove item
        @setUpdated true
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
        object = ST.Model.Index[uuid]
        list.array.push object if object
      
      this[member + 'NeedsRebuild'] = false
    
    this[member]
  
  @method 'markChanged', ->
    @changed = true
  
  @method '_changed', (member, oldValue, newValue) ->
    @_super member, oldValue, newValue
    @markChanged()
  
  # Returns saveable object containing model data.
  @method 'objectify', ->
    output = {
      _model: @$._name
      uuid:   @getUuid()
    }
    for attribute of @attributes
      value = @attributes[attribute]
      value = String(value) if value instanceof Date
      output[attribute] = value
    output
  
  # Saves model data and saved status in Storage for persistance.
  @method 'persist', ->
    if ST.Model.Storage && @persists
      output = @objectify()
      output._created = @created
      output._updated = @updated
      output._deleted = @deleted
      output._approved = @approved
      ST.Model.Storage.set @uuid, output
  
  # Removes model from all indexes.
  @method 'deindex', ->
    for attribute of @attributes
      indexName = "Index#{ST.ucFirst attribute}"
      value = @attributes[attribute]
      if @$[indexName]
        index = @$[indexName]
        index[value].remove this if index[value]
  
  # Marks model as destroyed, destroy to be propagated to server when 
  # possible.
  @method 'destroy', ->
    @deleted = @destroyed = true
    @deindex()
    @updated = @created = false
    @persist()
  
  # Removes all local data for model.
  @method 'forget', ->
    @deindex()
    delete ST.Model.Index[@uuid]
    STModel.Storage.remove @uuid if ST.Model.Storage
    STObject.prototype.destroy.apply this

  @classMethod 'attribute', (name, defaultValue) ->
    ucName = ST.ucFirst name
    
    @Attributes ||= {}
    @Attributes[name] = defaultValue
    
    @method "set#{ucName}", (newValue) ->
      oldValue = @attributes[name]
  
      # Set new value
      @attributes[name] = newValue
  
      # Update index
      if @$["Index#{ucName}"]
        index = @$["Index#{ucName}"];
        index[oldValue].remove this if index[oldValue]
        index[newValue] ||= ST.List.create()
        index[newValue].add this
  
      # Trigger changed event
      @_changed name, oldValue, newValue if @_changed
      @trigger 'changed', name, oldValue, newValue
      
      @setUpdated true
      @persist()
    
    @method "get#{ucName}", -> @attributes[name]
  
  @classMethod 'belongsTo', (name, assocModel, options={}) ->
    @attribute "#{name}Uuid"
    
    ucName = ST.ucFirst name
    
    @method "get#{ucName}", ->
      uuid = @get "#{name}Uuid"
      uuid && ST.Model.Index[uuid]
    
    @method "set#{ucName}", (value) ->
      ST.error 'Invalid object specified for association' if value && value.$._name != assocModel
      @set "#{name}Uuid", value && value.uuid
  
    if options.bind
      setUuidName = "set#{ucName}Uuid"
      oldSet = @prototype[setUuidName]
      @method setUuidName, (value) ->
        oldValue = @attributes[name]
        unless oldValue == value
          if oldValue.unbind
            for key of options.bind
              oldValue.unbind key, this
          oldSet.call this, value
          if newValue.bind
            for key of options.bind
              oldValue.bind key, this, options.bind[key]

  @classMethod 'hasMany', (name, assocModel, foreign=null, options={}) ->
    if foreign
      # One-to-many assocation through a Model and foreign key
      @method "get#{ST.ucFirst name}", ->
        unless this[name]
          conditions = {}
          conditions["#{foreign}Uuid"] = @uuid
          this[name] = ST.Scope.create(window[assocModel], { conditions: conditions }) 
        this[name]
      
      if options && options.bind
        for key of options.bind
          @ManyBinds ||= []
          @ManyBinds.push {
            assoc:  member
            from:   key
            to:     options.bind[key]
          }
    else
      # One-to-many association using a Uuids attribute
      attr = "#{ST.singularize name}Uuids"
      ucAttr = ST.ucFirst attr
  
      @Attributes ||= {}
      @Attributes[attr] = Array
  
      #setCustomerUuids
      @method "set#{ucAttr}", (value) ->
        @attributes[attr] = value
        this["#{name}NeedsRebuild"] = true
        @setUpdated true
        @persist()
  
      #getCustomerUuids
      @method "get#{ucAttr}", -> @attributes[attr]
  
      ucName = ST.ucFirst name
      ucsName = ST.ucFirst ST.singularize(name)
  
      #getCustomers
      @method "get#{ucName}", -> @getManyList name
  
      #addCustomer
      @method "add#{ucsName}", (record) ->
        @getManyList(name).add record
        this
      
  @classMethod 'hasAndBelongsToMany', (name, assocModel) ->
    @ManyMany ||= []
    @ManyMany.push name
    @method "get#{ST.ucFirst name}", ->
      this[name] ||= STManyAssociation.create this, name
      this[name]
    
  @setStorage = (storage) ->
    ST.Model.Storage = storage;
    
    if storage
      # Save any existing models to new storage
      for object in ST.Model.Index
        object.persist()
  
      # Load any unloaded saved models from storage
      storage.each (key, value) ->
        if value && value._model && window[value._model] && !STModel.Index[key]
          model = ST.Model.createWithData value
          model.created = value._created if value._created?
          model.updated = value._updated if value._updated?
          model.deleted = value._deleted if value._deleted?
          model.approved = value._approved if value._approved?