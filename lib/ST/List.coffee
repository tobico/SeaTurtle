#require ST/Object
#require ST/Enumerable

ST.class 'List', ->
  @include 'Enumerable'

  @initializer ->
    @super()
    @_array = []
    @_retains = true
  
  @initializer 'withArray', (array) ->
    @init()
    @_array = array
  
  @property 'retains'
    
  @method 'each', (fn) ->
    fn = ST.toProc fn
    for item in @_array
      break if fn.call(item, item) == 'break'
    
  @method 'getAt', (index) ->
    if index >= 0 && index < @_array.length
      @_array[Number(index)]
    else
      null
  
  @method 'at', (index, value) ->
    if arguments.length == 2
      @setAt index, value
    else
      @getAt index
    
  @delegate 'indexOf', 'array'
  @delegate 'length', 'array', 'count'
  
  @method 'isEmpty', -> !@_array.length
  
  @method 'count', ->
    return @_array.length
  
  @method 'last', ->
    if @_array.length
      @_array[@_array.length - 1]
    else
      null
  
  @method 'add', (object) ->
    @insertAt @_array.length, object
  
  @method 'insertAt', (index, object) ->
    object.retain() if object && object.retain && @_retains
    @_array.splice index, 0, object
    object.bind 'changed', this, 'itemChanged' if object && object.bind
    @trigger 'itemAdded', object
  
  @method 'addAndRelease', (object) ->
    @add object
    object.release() if object && object.release && @_retains
  
  @method 'removeAt', (index) ->
    return false unless @_array.length > index
    object = @_array.splice(index, 1)[0]
    object.unbind 'changed', this if object && object.unbind
    @trigger 'itemRemoved', object, index
    object.release() if object && object.release && @_retains
    true
    
  @method 'removeLast', ->
    if @_array.length > 0
      @removeAt @_array.length - 1
    else
      false
  
  @method 'remove', (object) ->
    index = @_array.indexOf object
    index >= 0 && @removeAt index
    
  # Add all items in another list to this one
  @method 'append', (list) ->
    self = this
    list.each (item) ->
      self.add item

  @method 'copy', ->
    newList = @_class.create()
    for object in @_array
      newList.add object
    newList
  
  @method 'empty', ->
    while @_array.length
      @removeLast()
      
  @method 'itemChanged', (item, attr, oldValue, newValue) ->
    @trigger 'itemChanged', item, attr, oldValue, newValue