import Flutter
import MapLibre

class MapLibreView: NSObject, FlutterPlatformView, MLNMapViewDelegate,
                    MapLibreHostApi, UIGestureRecognizerDelegate {
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

                self._flutterApi.onMapReady { _ in
                }
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
        ) { _ in
        }
    }

    @objc func onLongPress(sender: UILongPressGestureRecognizer) {
        var screenPosition = sender.location(in: _mapView)
        var point = _mapView.convert(screenPosition, toCoordinateFrom: _mapView)
        _flutterApi.onLongClick(
            point: LngLat(lng: point.longitude, lat: point.latitude)
        ) { _ in
        }
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
    func mapView(_ mapView: MLNMapView, didFinishLoading _: MLNStyle) {
        // setCamera() can only be used after the map did finish loading
        var camera = _mapView.camera
        camera.pitch = _mapOptions!.pitch
        _mapView.setCamera(camera, animated: false)

        _mapView = mapView
        print("mapView didFinishLoading, call onStyleLoaded")
        _flutterApi.onStyleLoaded { _ in
        }
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
        _flutterApi.onMoveCamera(camera: pigeonCamera) { _ in
        }
    }

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

    func addClusteredGeoJsonSource(
        id: String,
        data: String,
        clustered: Bool,
        clusterRadius: Double,
        clusterMaxZoom: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            print("iOS: addClusteredGeoJsonSource called with id: \(id), clustered: \(clustered)")

            guard let style = _mapView.style else {
                print("iOS: Error - Style not available")
                completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
                return
            }

            var options: [MLNShapeSourceOption: Any] = [:]
            if clustered {
                options[.clustered] = true
                options[.clusterRadius] = NSNumber(value: clusterRadius)
                options[.maximumZoomLevelForClustering] = NSNumber(value: clusterMaxZoom)
                print("iOS: Clustering enabled with radius: \(clusterRadius), maxZoom: \(clusterMaxZoom)")
            }

            let source: MLNShapeSource
            if data.hasPrefix("http://") || data.hasPrefix("https://") {
                print("iOS: Creating URL source")
                guard let url = URL(string: data) else {
                    throw NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(data)"])
                }
                source = MLNShapeSource(identifier: id, url: url, options: options)
            } else {
                print("iOS: Creating GeoJSON data source with \(data.count) characters")
                guard let dataBytes = data.data(using: .utf8),
                      let shape = try? MLNShape(data: dataBytes, encoding: String.Encoding.utf8.rawValue)
                else {
                    throw NSError(domain: "MapLibre", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON data"])
                }
                source = MLNShapeSource(identifier: id, shape: shape, options: options)
            }

            style.addSource(source)
            print("iOS: Successfully added clustered source with ID: \(id)")

            // Replace the clustering visualization section in your addClusteredGeoJsonSource method:

            if clustered {
                print("iOS: Adding visualization layers for clusters")

                // Add layer for unclustered points (individual points only)
                let unclusteredLayer = MLNCircleStyleLayer(identifier: "\(id)-unclustered", source: source)
                unclusteredLayer.circleRadius = NSExpression(forConstantValue: 8)
                unclusteredLayer.circleColor = NSExpression(forConstantValue: UIColor(hexString: "#11b4da") ?? UIColor.blue)
                unclusteredLayer.circleOpacity = NSExpression(forConstantValue: 0.8)
                unclusteredLayer.circleStrokeWidth = NSExpression(forConstantValue: 2)
                unclusteredLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor(hexString: "#ffffff") ?? UIColor.white)

                // Show only individual points that are NOT part of clusters
                unclusteredLayer.predicate = NSPredicate(format: "point_count == nil")
                style.addLayer(unclusteredLayer)
                print("iOS: Added unclustered points layer with predicate: point_count == nil")

                // Add layer for clusters only
                let clustersLayer = MLNCircleStyleLayer(identifier: "\(id)-clusters", source: source)
                clustersLayer.circleRadius = NSExpression(forConstantValue: 20)
                clustersLayer.circleColor = NSExpression(forConstantValue: UIColor.systemOrange)
                clustersLayer.circleOpacity = NSExpression(forConstantValue: 0.8)
                clustersLayer.circleStrokeWidth = NSExpression(forConstantValue: 2)
                clustersLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor(hexString: "#ffffff") ?? UIColor.white)

                // Show only cluster points (multiple points grouped together)
                clustersLayer.predicate = NSPredicate(format: "point_count != nil")
                style.addLayer(clustersLayer)
                print("iOS: Added clusters layer with predicate: point_count != nil")

                // Add layer for cluster count labels
                let clusterCountLayer = MLNSymbolStyleLayer(identifier: "\(id)-cluster-count", source: source)
                clusterCountLayer.text = NSExpression(forKeyPath: "point_count_abbreviated")
                clusterCountLayer.textFontSize = NSExpression(forConstantValue: 12)
                clusterCountLayer.textColor = NSExpression(forConstantValue: UIColor(hexString: "#ffffff") ?? UIColor.white)

                // Same predicate as clusters
                clusterCountLayer.predicate = NSPredicate(format: "point_count != nil")
                style.addLayer(clusterCountLayer)
                print("iOS: Added cluster count labels layer with predicate: point_count != nil")
            } else {
                print("iOS: No visualization layers added - clustering disabled")
            }

            completion(.success(()))
        } catch {
            print("iOS: Error adding clustered source: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }

    func addImage(
        id: String, bytes: FlutterStandardTypedData,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Main Thread Checker: UI API called on a background thread: -[UIView frame]
        // DispatchQueue.main.async {
        print("addImage before")
        var style = _mapView.style!
        var imageData = bytes.data
        var image = UIImage(data: imageData, scale: UIScreen.main.scale)!
        style.setImage(image, forName: id)
        print("addImage afters")
        print("added image: \(style.image(forName: id))")
        // }
        completion(.success(()))
    }
}
