#= require ST/Model

Spec.describe "Model/Scope", ->
  beforeEach ->
    @scope = ST.Model.Base.scoped()
    
  describe "#initWithModel", ->
    beforeEach ->
      @scope = new ST.Model.Scope()
      @scope.initWithModel ST.Model

    it "should set @_model", ->
      @scope._model.should be(ST.Model)
      
    it "should set defaults", ->
      @scope._conditions.should equal([])
      expect(@scope._orders).to be(null)
  
  describe "#initWithScope", ->
    beforeEach ->
      @condition = {attribute: 'foo', test: (-> true) }
      @scope._conditions = [@condition]
      @scope._orders = ['foo']
      @copy = ST.Model.Scope.createWithScope @scope
  
    it "should copy scope model", ->
      @copy._model.should be(@scope._model)
    
    it "should copy scope conditions", ->
      @copy._conditions.length.should equal(1)
      expect(@copy._conditions[0]).to be(@condition)
      
    it "should copy scope order", ->
      @copy._orders.should equal(['foo'])
  
  describe "#model", ->
    it "should return model", ->
      @scope.model().should be(ST.Model.Base)
  
  describe "#fork", ->
    it "should copy scope", ->
      copy = @scope.fork()
      copy._model.should be(ST.Model.Base)
    
    it "should run block on new scope", ->
      exp = expectation('run block')
      copy = @scope.fork -> exp.meet()
  
  describe "#where", ->
    it "should add conditions to fork of scope with no conditions", ->
      condition = {attribute: 'foo', test: (-> true) }
      copy = @scope.where(condition)
      copy._conditions.should equal([condition])
    
    it "should combine conditions on fork of scope with conditions", ->
      condition1 = {attribute: 'foo', test: (-> true) }
      condition2 = {attribute: 'bar', test: (-> false) }
      @scope._conditions = [condition1]
      copy = @scope.where(condition2)
      copy._conditions.should equal([condition1, condition2])
  
  describe "#order", ->
    it "should set order on fork of scope", ->
      copy = @scope.order('foo')
      copy._orders.should equal(['foo'])
  
  context "with a test model", ->
    beforeEach ->
      uuid = 1
      ST.Model._generateUUID = -> uuid++
    
      ST.class 'TestModel', ST.Model.Base, ->
        @string 'foo', 'bacon'
        @integer 'cost', 1
  
    describe "#enableBindings", ->
      it "should bind scope to a relevant attribute index"
    
    describe "#each", ->
      it "should iterate over items matched by scope", ->
        model = ST.TestModel.createWithData {foo: 'bacon'}
        found = expectation('find matching model')
        ST.TestModel.where(ST.TestModel.foo.equals('bacon')).each (item) ->
          found.meet()
          item.should be(model)
    
      it "should iterate over items in order", ->
        model1 = ST.TestModel.createWithData {foo: 'bacon', cost: 3}
        model2 = ST.TestModel.createWithData {foo: 'waffles', cost: 2}
        model3 = ST.TestModel.createWithData {foo: 'waffles', cost: 7}
        found = expectation('find model').exactly(3).times
        index = 0
        ST.TestModel.order('cost').each (item) ->
          index++
          item.should be(model2) if index == 1
          item.should be(model1) if index == 2
          item.should be(model3) if index == 3
          found.meet()
  
    describe "#count", ->
      it "should count number of items matched by scope", ->
        model = ST.TestModel.createWithData {foo: 'bacon'}
        ST.TestModel.scoped().count().should equal(1)
  
    describe "#destroyAll", ->
      it "should destroy all items matched by scope", ->
        model = ST.TestModel.createWithData {foo: 'bacon'}
        ST.TestModel.scoped().destroyAll()
        ST.TestModel.scoped().count().should equal(0)
  
    describe "#build", ->
      it "should create a new object using scope conditions as base data", ->
        model = ST.TestModel.where(ST.TestModel.foo.equals('banana')).build()
        model.foo().should equal('banana')
  
    describe "#indexItemAdded", ->
      it "should trigger event if item matches scope"
      it "should do nothing if item doesn't match scope"
  
    describe "#indexItemRemoved", ->
      it "should trigger event if item matches scope"
      it "should do nothing if item doesn't match scope"
  
    describe "#indexItemChanged", ->
      it "should trigger event if item matches scope"
      it "should do nothing if item doesn't match scope"