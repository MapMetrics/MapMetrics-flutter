import Flutter
import MapLibre

class MapLibreView: NSObject, FlutterPlatformView, MLNMapViewDelegate,
  MapLibreHostApi, UIGestureRecognizerDelegate
{
  private var _view: UIView = .init()
  private var _mapView: MLNMapView!
  private var _viewId: Int64
  private var _flutterApi: MapLibreFlutterApi
  private var _mapOptions: MapOptions? = nil

  init(
    frame _: CGRect,
    viewId: Int64,
    binaryMessenger: FlutterBinaryMessenger
  ) {
    print("### init new MapViewDelegate ### \(viewId) ###")
    var channelSuffix = String(viewId)
    _viewId = viewId
    _flutterApi = MapLibreFlutterApi(
      binaryMessenger: binaryMessenger,
      messageChannelSuffix: channelSuffix
    )
    super.init() // self can be used after calling super.init()
    MapLibreHostApiSetup.setUp(
      binaryMessenger: binaryMessenger, api: self,
      messageChannelSuffix: channelSuffix
    )
    // get and apply the MapOptions from Flutter
    _flutterApi.getOptions { result in
      switch result {
      case let .success(mapOptions):
        self._mapOptions = mapOptions
        // init map view
        self._mapView = MLNMapView(frame: self._view.bounds)
        MapLibreRegistry.addMap(viewId: viewId, map: self._mapView)
        self._mapView.autoresizingMask = [
          .flexibleWidth, .flexibleHeight,
        ]
        self._view.addSubview(self._mapView)
        self._mapView.delegate = self
        // disable the default UI because they are rebuilt in Flutter
        self._mapView.compassView.isHidden = true
        self._mapView.attributionButton.isHidden = true
        self._mapView.logoView.isHidden = true
        // set options
        DispatchQueue.main.async {
          var currentCenter = self._mapView.camera.centerCoordinate
          var center = CLLocationCoordinate2D(
            latitude: mapOptions.center?.lat
              ?? currentCenter.latitude,
            longitude: mapOptions.center?.lng
              ?? currentCenter.longitude
          )
          self._mapView.setCenter(
            center, zoomLevel: mapOptions.zoom,
            direction: mapOptions.bearing, animated: false
          )
        }

        self._mapView.showAttribution(false)

        self._mapView.minimumZoomLevel = mapOptions.minZoom
        self._mapView.maximumZoomLevel = mapOptions.maxZoom
        self._mapView.minimumPitch = mapOptions.minPitch
        self._mapView.maximumPitch = mapOptions.maxPitch

        self._mapView.styleURL = URL(string: mapOptions.style)

        self._mapView.allowsRotating = mapOptions.gestures.rotate
        self._mapView.allowsScrolling = mapOptions.gestures.pan
        self._mapView.allowsTilting = mapOptions.gestures.tilt
        self._mapView.allowsZooming = mapOptions.gestures.zoom

        self._flutterApi.onMapReady { _ in }
        // tap gestures
        self._mapView.addGestureRecognizer(
          UITapGestureRecognizer(
            target: self, action: #selector(self.onTap(sender:))
          ))
        self._mapView.addGestureRecognizer(
          UILongPressGestureRecognizer(
            target: self,
            action: #selector(self.onLongPress(sender:))
          ))
      case let .failure(error):
        print(error)
      }
    }
  }

  func dispose() throws {
    print("### dispose MapLibre view ### \(_viewId) ###")
    MapLibreRegistry.removeMap(viewId: _viewId)
    _mapView.removeFromSuperview()
    _mapView.delegate = nil
    _mapView = nil
    _view.removeFromSuperview()
  }

  @objc func onTap(sender: UITapGestureRecognizer) {
    var screenPosition = sender.location(in: _mapView)
    var point = _mapView.convert(screenPosition, toCoordinateFrom: _mapView)
    _flutterApi.onClick(
      point: LngLat(lng: point.longitude, lat: point.latitude)
    ) { _ in }
  }

  @objc func onLongPress(sender: UILongPressGestureRecognizer) {
    var screenPosition = sender.location(in: _mapView)
    var point = _mapView.convert(screenPosition, toCoordinateFrom: _mapView)
    _flutterApi.onLongClick(
      point: LngLat(lng: point.longitude, lat: point.latitude)
    ) { _ in }
  }

  func view() -> UIView {
    _view
  }

  func gestureRecognizer(
    _: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
  ) -> Bool {
    // Do not override the default behavior
    true
  }

  // MLNMapViewDelegate method called when map has finished loading
  func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
    print("iOS: MapViewDelegate - didFinishLoading called, setting current style")
    // Set the current style for clustering support
    MapLibreIosPlugin.setCurrentStyle(style)
    print("iOS: MapViewDelegate - Current style set successfully")
    
    // setCamera() can only be used after the map did finish loading
    var camera = _mapView.camera
    camera.pitch = _mapOptions!.pitch
    _mapView.setCamera(camera, animated: false)

    _mapView = mapView
    print("mapView didFinishLoading, call onStyleLoaded")
    _flutterApi.onStyleLoaded { _ in }
  }

  func mapView(_: MLNMapView, regionDidChangeAnimated _: Bool) {
    onCameraMoved()
  }

  func mapViewRegionIsChanging(_: MLNMapView) {
    onCameraMoved()
  }

  func onCameraMoved() {
    var mlnCamera = _mapView.camera
    var center = LngLat(
      lng: mlnCamera.centerCoordinate.longitude,
      lat: mlnCamera.centerCoordinate.latitude
    )
    var pigeonCamera = MapCamera(
      center: center, zoom: mlnCamera.altitude, pitch: mlnCamera.pitch,
      bearing: mlnCamera.heading
    )
    _flutterApi.onMoveCamera(camera: pigeonCamera) { _ in }
  }

  // MARK: - MapLibreHostApi Implementation

  func addFillLayer(
    id _: String, sourceId _: String, layout _: [String: Any],
    paint _: [String: Any], belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func addCircleLayer(
    id _: String, sourceId _: String, layout _: [String: Any],
    paint _: [String: Any], belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func addBackgroundLayer(
    id _: String, layout _: [String: Any], paint _: [String: Any],
    belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func addFillExtrusionLayer(
    id _: String, sourceId _: String, layout _: [String: Any],
    paint _: [String: Any], belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func addHeatmapLayer(
    id _: String, sourceId _: String, layout _: [String: Any],
    paint _: [String: Any], belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func addHillshadeLayer(
    id _: String, sourceId _: String, layout _: [String: Any],
    paint _: [String: Any], belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func addLineLayer(
    id _: String, sourceId _: String, layout _: [String: Any],
    paint _: [String: Any], belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func addRasterLayer(
    id _: String, sourceId _: String, layout _: [String: Any],
    paint _: [String: Any], belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func addSymbolLayer(
    id _: String, sourceId _: String, layout _: [String: Any],
    paint _: [String: Any], belowLayerId _: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    completion(.success(()))
  }

  func loadImage(
    url _: String,
    completion _: @escaping (Result<FlutterStandardTypedData, Error>) ->
      Void
  ) {
    // completion(.success((bytes)))
  }

  func addImage(
    id: String, bytes: FlutterStandardTypedData,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("addImage before")
    var style = _mapView.style!
    var imageData = bytes.data
    var image = UIImage(data: imageData, scale: UIScreen.main.scale)!
    style.setImage(image, forName: id)
    print("addImage afters")
    print("added image: \(style.image(forName: id))")
    completion(.success(()))
  }

  func addClusteredGeoJsonSource(
    id: String, data: String, clustered: Bool, clusterRadius: Double, clusterMaxZoom: Double,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("Swift: addClusteredGeoJsonSource called with id: \(id), clustered: \(clustered)")

    guard let style = _mapView.style else {
      print("Swift: Error - Style not available")
      completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
      return
    }

    print("Swift: Style is available, creating clustering options")

    // Create clustering options
    var options: [MLNShapeSourceOption: Any] = [:]
    if clustered {
      options[.clustered] = true
      options[.clusterRadius] = clusterRadius
      options[.maximumZoomLevelForClustering] = clusterMaxZoom
      print("Swift: Clustering enabled with radius: \(clusterRadius), maxZoom: \(clusterMaxZoom)")
    }

    // Create the shape source
    let source: MLNShapeSource
    if data.hasPrefix("http://") || data.hasPrefix("https://") {
      // Handle URL source
      print("Swift: Creating URL source")
      guard let url = URL(string: data) else {
        print("Swift: Error - Invalid URL: \(data)")
        completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(data)"])))
        return
      }
      source = MLNShapeSource(identifier: id, url: url, options: options)
    } else {
      // Handle GeoJSON data
      print("Swift: Creating GeoJSON data source with \(data.count) characters")
      guard let dataBytes = data.data(using: .utf8),
            let shape = try? MLNShape(data: dataBytes, encoding: String.Encoding.utf8.rawValue) else {
        print("Swift: Error - Invalid GeoJSON data")
        completion(.failure(NSError(domain: "MapLibre", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON data"])))
        return
      }
      source = MLNShapeSource(identifier: id, shape: shape, options: options)
    }

    // Add the source to the style
    print("Swift: Adding source to style")
    style.addSource(source)
    print("Swift: Successfully added clustered source with ID: \(id)")

    // Add visualization layers for the clusters
    if clustered {
      print("Swift: Adding visualization layers for clusters")

      // Add layer for unclustered points (individual points)
      let unclusteredLayer = MLNCircleStyleLayer(identifier: "\(id)-unclustered", source: source)
      unclusteredLayer.circleRadius = NSExpression(forConstantValue: 8)
      unclusteredLayer.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
      unclusteredLayer.circleOpacity = NSExpression(forConstantValue: 0.8)
      unclusteredLayer.circleStrokeWidth = NSExpression(forConstantValue: 2)
      unclusteredLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)

      // Filter to show only unclustered points
      unclusteredLayer.predicate = NSPredicate(format: "point_count == nil")

      style.addLayer(unclusteredLayer)
      print("Swift: Added unclustered points layer")

      // Add layer for clusters (colored circles)
      let clustersLayer = MLNCircleStyleLayer(identifier: "\(id)-clusters", source: source)
      clustersLayer.circleRadius = NSExpression(forConstantValue: 20)
      clustersLayer.circleColor = NSExpression(forConstantValue: UIColor.systemOrange)
      clustersLayer.circleOpacity = NSExpression(forConstantValue: 0.8)
      clustersLayer.circleStrokeWidth = NSExpression(forConstantValue: 2)
      clustersLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)

      // Filter to show only clusters
      clustersLayer.predicate = NSPredicate(format: "point_count != nil")

      style.addLayer(clustersLayer)
      print("Swift: Added clusters layer")

      // Add layer for cluster count labels
      let clusterCountLayer = MLNSymbolStyleLayer(identifier: "\(id)-cluster-count", source: source)
      clusterCountLayer.text = NSExpression(forKeyPath: "point_count_abbreviated")
      clusterCountLayer.textFontSize = NSExpression(forConstantValue: 12)
      clusterCountLayer.textColor = NSExpression(forConstantValue: UIColor.white)

      // Filter to show only clusters
      clusterCountLayer.predicate = NSPredicate(format: "point_count != nil")

      style.addLayer(clusterCountLayer)
      print("Swift: Added cluster count labels layer")
    }

    completion(.success(()))
  }

  // Test method for debugging Pigeon generation
  func testMethod(
    value: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("Swift: testMethod called with value: \(value)")
    completion(.success(()))
  }

  // Animate the camera to a new position (Pigeon API)
  func animateCamera(
    latitude: Double,
    longitude: Double,
    zoom: Double,
    bearing: Double,
    pitch: Double,
    duration: Int64,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DispatchQueue.main.async {
      var camera = self._mapView.camera

      // Use sentinel values (-1.0 or NaN) to indicate "no change"
      if !latitude.isNaN && latitude != -1.0 {
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      }
      if !bearing.isNaN && bearing != -1.0 {
        camera.heading = bearing
      }
      if !pitch.isNaN && pitch != -1.0 {
        camera.pitch = pitch
      }

      // Set camera with animation
      let animationDuration = duration > 0 ? Double(duration) / 1000.0 : 0.2
      self._mapView.setCamera(camera, withDuration: animationDuration, animationTimingFunction: nil)

      // Handle zoom separately if needed
      if !zoom.isNaN && zoom != -1.0 {
        self._mapView.setZoomLevel(zoom, animated: true)
      }

      completion(.success(()))
    }
  }

  // Get the current camera state
  func getCamera() -> MapCamera {
    let camera = _mapView.camera
    let center = LngLat(
      lng: camera.centerCoordinate.longitude,
      lat: camera.centerCoordinate.latitude
    )
    return MapCamera(
      center: center,
      zoom: _mapView.zoomLevel,
      pitch: camera.pitch,
      bearing: camera.heading
    )
  }

  // Get the current zoom level
  func getZoomLevel() -> Double {
    return _mapView.zoomLevel
  }

  // Get the user's current location
  func getUserLocation() -> LngLat {
    if let userLocation = _mapView.userLocation?.location {
      return LngLat(
        lng: userLocation.coordinate.longitude,
        lat: userLocation.coordinate.latitude
      )
    } else {
      // Return a default location if user location is not available
      return LngLat(lng: 0.0, lat: 0.0)
    }
  }

  // MARK: - New Required Methods

  // Move the camera to a new position without animation
  func moveCamera(
    lat: Double,
    lng: Double,
    zoom: Double,
    bearing: Double,
    pitch: Double,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DispatchQueue.main.async {
      var camera = self._mapView.camera

      // Use sentinel values (-1.0 or NaN) to indicate "no change"
      if !lat.isNaN && lat != -1.0 {
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
      }
      if !bearing.isNaN && bearing != -1.0 {
        camera.heading = bearing
      }
      if !pitch.isNaN && pitch != -1.0 {
        camera.pitch = pitch
      }

      // Set camera without animation
      self._mapView.setCamera(camera, animated: false)

      // Handle zoom separately if needed
      if !zoom.isNaN && zoom != -1.0 {
        self._mapView.setZoomLevel(zoom, animated: false)
      }

      completion(.success(()))
    }
  }

  // Update map options including bounds and gesture settings
  func updateMapOptions(
    minZoom: Double,
    maxZoom: Double,
    minPitch: Double,
    maxPitch: Double,
    boundsWest: Double,
    boundsSouth: Double,
    boundsEast: Double,
    boundsNorth: Double,
    rotateEnabled: Bool,
    panEnabled: Bool,
    zoomEnabled: Bool,
    pitchEnabled: Bool,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DispatchQueue.main.async {
      // Update zoom and pitch limits
      if !minZoom.isNaN && minZoom != -1.0 {
        self._mapView.minimumZoomLevel = minZoom
      }
      if !maxZoom.isNaN && maxZoom != -1.0 {
        self._mapView.maximumZoomLevel = maxZoom
      }
      if !minPitch.isNaN && minPitch != -1.0 {
        self._mapView.minimumPitch = minPitch
      }
      if !maxPitch.isNaN && maxPitch != -1.0 {
        self._mapView.maximumPitch = maxPitch
      }

      // Update bounds if provided
      if !boundsWest.isNaN && !boundsSouth.isNaN && !boundsEast.isNaN && !boundsNorth.isNaN {
        let bounds = MLNCoordinateBounds(
          sw: CLLocationCoordinate2D(latitude: boundsSouth, longitude: boundsWest),
          ne: CLLocationCoordinate2D(latitude: boundsNorth, longitude: boundsEast)
        )
        // Note: MLNMapView doesn't have a direct way to set coordinate bounds
        // This would need to be implemented differently if needed
      }

      // Update gesture settings
      self._mapView.allowsRotating = rotateEnabled
      self._mapView.allowsScrolling = panEnabled
      self._mapView.allowsZooming = zoomEnabled
      self._mapView.allowsTilting = pitchEnabled

      completion(.success(()))
    }
  }

  // Enable location services and show user location on map
  func enableLocation(
    fastestInterval: Int64,
    maxWaitTime: Int64,
    pulseFade: Bool,
    accuracyAnimation: Bool,
    compassAnimation: Bool,
    pulse: Bool,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DispatchQueue.main.async {
      self._mapView.showsUserLocation = true
      // Note: iOS MapLibre doesn't have all the detailed location settings like Android
      // The parameters here would need custom implementation if needed
      completion(.success(()))
    }
  }

  // Fit the map camera to show the specified bounds
  func fitBounds(
    west: Double,
    south: Double,
    east: Double,
    north: Double,
    bearing: Double,
    pitch: Double,
    duration: Int64,
    paddingLeft: Double,
    paddingTop: Double,
    paddingRight: Double,
    paddingBottom: Double,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DispatchQueue.main.async {
      let bounds = MLNCoordinateBounds(
        sw: CLLocationCoordinate2D(latitude: south, longitude: west),
        ne: CLLocationCoordinate2D(latitude: north, longitude: east)
      )

      let edgeInsets = UIEdgeInsets(
        top: CGFloat(paddingTop),
        left: CGFloat(paddingLeft),
        bottom: CGFloat(paddingBottom),
        right: CGFloat(paddingRight)
      )

      let animated = duration > 0
      self._mapView.setVisibleCoordinateBounds(bounds, edgePadding: edgeInsets, animated: animated)

      completion(.success(()))
    }
  }

  // Get the meters per pixel at the specified latitude
  func getMetersPerPixelAtLatitude(
    latitude: Double,
    completion: @escaping (Result<Double, Error>) -> Void
  ) {
    let metersPerPixel = _mapView.metersPerPoint(atLatitude: latitude)
    completion(.success(metersPerPixel))
  }

  // Get the visible region bounds
  func getVisibleRegion(
    completion: @escaping (Result<[Double], Error>) -> Void
  ) {
    let bounds = _mapView.visibleCoordinateBounds
    let result = [bounds.sw.longitude, bounds.sw.latitude, bounds.ne.longitude, bounds.ne.latitude]
    completion(.success(result))
  }

  // Convert screen coordinates to longitude/latitude
  func toLngLat(
    x: Double,
    y: Double,
    completion: @escaping (Result<[Double], Error>) -> Void
  ) {
    let screenPoint = CGPoint(x: x, y: y)
    let coordinate = _mapView.convert(screenPoint, toCoordinateFrom: _mapView)
    let result = [coordinate.longitude, coordinate.latitude]
    completion(.success(result))
  }

  // Convert longitude/latitude to screen coordinates
  func toScreenLocation(
    lng: Double,
    lat: Double,
    completion: @escaping (Result<[Double], Error>) -> Void
  ) {
    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
    let screenPoint = _mapView.convert(coordinate, toPointTo: _mapView)
    let result = [Double(screenPoint.x), Double(screenPoint.y)]
    completion(.success(result))
  }

  // Query rendered layers at the specified screen location
  func queryLayers(
    x: Double,
    y: Double,
    completion: @escaping (Result<[[String: String?]], Error>) -> Void
  ) {
    let screenPoint = CGPoint(x: x, y: y)

    // Query visible features at the point
    let features = _mapView.visibleFeatures(at: screenPoint)

    var result: [[String: String?]] = []
    for feature in features {
      if let layer = feature.attribute(forKey: "layer") as? String,
         let source = feature.attribute(forKey: "source") as? String {
        let layerInfo: [String: String?] = [
          "layerId": layer,
          "sourceId": source,
          "sourceLayer": feature.attribute(forKey: "sourceLayer") as? String
        ]
        result.append(layerInfo)
      }
    }

    completion(.success(result))
  }

  // Enable/disable location tracking with bearing mode
  func trackLocation(
    track: Bool,
    bearingMode: Int64,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    DispatchQueue.main.async {
      if track {
        // Convert bearingMode to appropriate iOS tracking mode
        switch bearingMode {
        case 0: // none
          self._mapView.userTrackingMode = .follow
        case 1: // compass
          self._mapView.userTrackingMode = .followWithHeading
        case 2: // gps
          self._mapView.userTrackingMode = .followWithCourse
        default:
          self._mapView.userTrackingMode = .follow
        }
      } else {
        self._mapView.userTrackingMode = .none
      }

      completion(.success(()))
    }
  }
}