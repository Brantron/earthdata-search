#= require models/data/granules
#= require models/data/service_options

ns = @edsc.models.data

ns.Dataset = do (ko
                 DetailsModel = @edsc.models.DetailsModel
                 scalerUrl = @edsc.config.browseScalerUrl
                 Granules=ns.Granules
                 GranuleQuery = ns.query.GranuleQuery
                 ServiceOptionsModel = ns.ServiceOptions
                 toParam=jQuery.param
                 extend=jQuery.extend
                 ajax = @edsc.util.xhr.ajax
                 dateUtil = @edsc.util.date
                 ) ->

  datasets = ko.observableArray()

  randomKey = Math.random()

  register = (dataset) ->
    dataset.reference()
    datasets.push(dataset)
    dataset

  class Dataset extends DetailsModel
    @findOrCreate: (jsonData, query) ->
      id = jsonData.id
      featured = jsonData.featured
      for dataset in datasets()
        if dataset.id == id
          if (jsonData.short_name? && !dataset.hasAtomData()) || dataset.featured != featured || jsonData.granule_count != dataset.granule_count
            dataset.fromJson(jsonData)
          return dataset.reference()
      register(new Dataset(jsonData, query, randomKey))

    @visible: ko.computed
      read: -> dataset for dataset in datasets() when dataset.visible()

    constructor: (jsonData, @query, inKey) ->
      throw "Datasets should not be constructed directly" unless inKey == randomKey
      @granuleCount = ko.observable(0)

      @hasAtomData = ko.observable(false)

      @granuleQueryLoaded = ko.observable(false)
      Object.defineProperty this, 'granuleQuery',
        get: ->
          @granuleQueryLoaded(true)
          @_granuleQuery ?= @disposable(new GranuleQuery(@id, @query, @searchable_attributes))

      Object.defineProperty this, 'granulesModel',
        get: -> @_granulesModel ?= @disposable(new Granules(@granuleQuery, @query))

      @details = @asyncComputed({}, 100, @_computeDatasetDetails, this)
      @detailsLoaded = ko.observable(false)

      @timeRange = @computed(@_computeTimeRange, this, deferEvaluation: true)
      @spatial = @computed(@_computeSpatial, this, deferEvaluation: true)
      @granuleDescription = @computed(@_computeGranuleDescription, this, deferEvaluation: true)

      @visible = ko.observable(false)

      @fromJson(jsonData)

      @spatial_constraint = @computed =>
        if @points?
          'point:' + @points[0].split(/\s+/).reverse().join(',')
        else
          null

      @echoGranulesUrl = @computed
        read: =>
          paramStr = toParam(@granuleQuery.params())
          "#{@details().granule_url}?#{paramStr}"
        deferEvaluation: true

    _computeTimeRange: ->
      if @hasAtomData()
        result = dateUtil.timeSpanToIsoDate(@time_start, @time_end)
      (result || "Unknown")

    _computeSpatial: ->
      if @boxes?
        "Bounding Rectangles: (" + @boxes[0] + (if @boxes.length > 1 then ") ..." else ")")
      else if @points?
        "Points: (" + @points[0] + (if @points.length > 1 then ") ..." else ")")
      else if @polygons?
        "Polygons: (" + @polygons[0] + (if @polygons.length > 1 then ") ..." else ")")
      else if @lines?
        "Lines: (" + @lines[0] + (if @lines.length > 1 then ") ..." else ")")

    _computeGranuleDescription: ->
      result = null
      return result unless @hasAtomData()
      if @has_granules
        if @granulesModel.isLoaded()
          hits = @granulesModel.hits()
        else
          hits = @granuleCount()
        if hits?
          result = "#{hits} Granule"
          result += 's' if hits != 1
      else
        result = 'Dataset only'
      result

    thumbnail: ->
      granule = @browseable_granule
      collection_id = @id for link in @links when link['rel'].indexOf('browse#') > -1
      if collection_id?
        "#{scalerUrl}/datasets/#{collection_id}?h=85&w=85"
      else if granule?
        "#{scalerUrl}/granules/#{granule}?h=85&w=85"
      else
        null

    granuleFiltersApplied: ->
      # granuleQuery.params() will have echo_collection_id and page_size by default
      params = @granuleQuery.serialize()
      return true for own key, value of params
      return false

    hasGranuleConfig: ->
      @granuleQueryLoaded() && Object.keys(@granuleQuery.serialize()).length > 0

    shouldDispose: ->
      result = !@hasGranuleConfig()
      datasets.remove(this) if result
      result

    makeRecent: ->
      id = @id
      if id? && !@featured
        ajax
          dataType: 'json'
          url: "/datasets/#{id}/use.json"
          method: 'post'
          success: (data) ->
            @featured = data

    fromJson: (jsonObj) ->
      @json = jsonObj

      console.log jsonObj
      attributes = jsonObj.searchable_attributes
      if attributes && @granuleQueryLoaded()
        @granuleQuery.attributes.definitions(attributes)

      @hasAtomData(jsonObj.short_name?)
      @_setObservable('gibs', jsonObj)
      @_setObservable('opendap', jsonObj)
      @_setObservable('modaps', jsonObj)
      @nrt = jsonObj.collection_data_type == "NEAR_REAL_TIME"
      @granuleCount(jsonObj.granule_count)

      for own key, value of jsonObj
        this[key] = value unless ko.isObservable(this[key])

    _setObservable: (prop, jsonObj) =>
      this[prop] ?= ko.observable(undefined)
      this[prop](jsonObj[prop] ? this[prop]())

  exports = Dataset
