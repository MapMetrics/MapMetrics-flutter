import Flutter
import MapLibre

// Typealias to help Swift parser with complex nested generics
typealias LayerPropertiesArray = [[String: String]]

class MapLibreView: NSObject, FlutterPlatformView, MLNMapViewDelegate,
    MapLibreHostApi, UIGestureRecognizerDelegate
{
    private var _view: UIView = .init()
    private var _mapView: MLNMapView!
    private var _viewId: Int64
    private var _flutterApi: MapLibreFlutterApi
    private var _mapOptions: MapOptions? = nil
    private var _isMapInitialized = false
    private var _pendingOperations: [(MLNMapView) -> Void] = []

    // THREAD SAFETY: Serial queue for all style operations to prevent race conditions
    private let styleOperationQueue = DispatchQueue(label: "com.mapmetrics.styleOperations", qos: .userInitiated)
    private var _isProcessingStyleOperation = false
    private let styleLock = NSLock()

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
        super.init()  // self can be used after calling super.init()
        MapLibreHostApiSetup.setUp(
            binaryMessenger: binaryMessenger, api: self,
            messageChannelSuffix: channelSuffix
        )
        // get and apply the MapOptions from Flutter
        _flutterApi.getOptions { result in
            switch result {
            case let .success(mapOptions):
                self._mapOptions = mapOptions

                // Hand the API key to the SDK BEFORE the first MLNMapView exists.
                //
                // This is what turns on v2 billing. MMMapSession opens a session
                // only once it holds both halves of its config: the gateway origin
                // (pinned from Info.plist's MLNTileServerBaseURL) and this key,
                // which it watches by KVO on MLNSettings.apiKey. Without this line
                // the key crosses the Pigeon bridge and is read by nobody, no
                // session is ever created, and every request falls through to the
                // v1 path -- which bills once per request on a cold load instead
                // of once per session.
                //
                // Set before MLNMapView(frame:) so the create is already under
                // way when the first request is built. The KVO fires
                // synchronously, so this costs nothing.
                //
                // Correctness no longer RESTS on that ordering. Up to
                // MapMetrics-SDK 2.0.0 it did: the create is an async POST, so
                // the opening style-and-tile wave left before the credential
                // landed, went out on the style's `?token=` alone, and billed
                // once per tile -- 8 charges for one map load, measured. 2.0.1
                // makes an outgoing gateway request wait for an in-flight
                // create, so the SDK closes that window for every consumer
                // rather than each caller having to sequence it. Keeping the
                // assignment early is still the right shape; it just is not
                // load-bearing any more.
                //
                // Guarded on non-empty because MLNSettings.apiKey is a GLOBAL, and
                // every MapLibreView created in this app writes it. A second map
                // built without a key must not blank out the key a first map set.
                if let apiKey = mapOptions.apiKey, !apiKey.isEmpty {
                    MLNSettings.apiKey = apiKey
                }

                // init map view
                self._mapView = MLNMapView(frame: self._view.bounds)
                
                // CRITICAL: Ensure user location is disabled initially to prevent layer conflicts
                self._mapView.showsUserLocation = false
                
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

                // Disable double-tap zoom gesture while keeping pinch-to-zoom
                for gestureRecognizer in self._mapView.gestureRecognizers ?? [] {
                    if let tapGR = gestureRecognizer as? UITapGestureRecognizer,
                       tapGR.numberOfTapsRequired == 2 {
                        tapGR.isEnabled = false
                    }
                }

                self._flutterApi.onMapReady { _ in }
                
                // Mark map as initialized and execute pending operations
                self._isMapInitialized = true
                self.executePendingOperations()
                
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
        
        // CRITICAL: Disable user location before disposing to prevent layer conflicts
        if let mapView = _mapView {
            print("iOS: Disabling user location before disposal to prevent layer conflicts")
            mapView.showsUserLocation = false
            mapView.setUserTrackingMode(.none, animated: false, completionHandler: nil)
            mapView.removeFromSuperview()
            mapView.delegate = nil
        }
        
        _mapView = nil
        _view.removeFromSuperview()
    }

    @objc func onTap(sender: UITapGestureRecognizer) {
        var screenPosition = sender.location(in: _mapView)
        var point = _mapView.convert(screenPosition, toCoordinateFrom: _mapView)  // Remove asterisks
        _flutterApi.onClick(
            point: LngLat(lng: point.longitude, lat: point.latitude)
        ) { _ in }
    }

    @objc func onLongPress(sender: UILongPressGestureRecognizer) {
        // Only trigger on the began state to avoid multiple calls
        guard sender.state == .began else {
            return
        }
        var screenPosition = sender.location(in: _mapView)
        var point = _mapView.convert(screenPosition, toCoordinateFrom: _mapView)  // Remove asterisks
        print("iOS: Long press detected at lng: \(point.longitude), lat: \(point.latitude)")
        _flutterApi.onLongClick(
            point: LngLat(lng: point.longitude, lat: point.latitude)
        ) { _ in }
    }

    func view() -> UIView {
        _view
    }
    
    private func executePendingOperations() {
        guard _isMapInitialized && _mapView != nil else { return }
        
        print("iOS: Executing \(_pendingOperations.count) pending operations")
        for operation in _pendingOperations {
            operation(_mapView)
        }
        _pendingOperations.removeAll()
    }
    
    private func executeOrQueue<T>(_ operation: @escaping (MLNMapView) -> T, completion: @escaping (Result<T, Error>) -> Void) {
        if _isMapInitialized && _mapView != nil {
            let result = operation(_mapView)
            completion(.success(result))
        } else {
            _pendingOperations.append { mapView in
                let result = operation(mapView)
                completion(.success(result))
            }
        }
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
        MapLibreIosPlugin.setCurrentStyle(style)
        print("iOS: MapViewDelegate - Current style set successfully")

        var camera = _mapView.camera
        camera.pitch = _mapOptions!.pitch
        _mapView.setCamera(camera, animated: false)
        _mapView = mapView
        print("mapView didFinishLoading, call onStyleLoaded")
        _flutterApi.onStyleLoaded { _ in }  // Remove asterisk
    }

    func mapView(_: MLNMapView, regionDidChangeAnimated _: Bool) {
        onCameraMoved()
    }

    func mapViewRegionIsChanging(_: MLNMapView) {
        onCameraMoved()
    }

    // MARK: - User Location Delegate Methods

    /// Called when the user's location is updated
    /// This helps us track if the user location is being set incorrectly during camera moves
    func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
        if let location = userLocation?.location {
            let cameraCenter = mapView.camera.centerCoordinate
            let userLat = location.coordinate.latitude
            let userLng = location.coordinate.longitude
            let cameraLat = cameraCenter.latitude
            let cameraLng = cameraCenter.longitude

            // Calculate distance between user location and camera center
            let latDiff = abs(userLat - cameraLat)
            let lngDiff = abs(userLng - cameraLng)

            // Only log if there's a significant difference (debugging)
            if latDiff > 0.0001 || lngDiff > 0.0001 {
                print("📍 iOS didUpdateUserLocation: user=(\(userLat),\(userLng)) camera=(\(cameraLat),\(cameraLng))")
            }
        }
    }

    /// Called when user tracking mode changes
    func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
        print("🔵 iOS didChangeTrackingMode: mode=\(mode.rawValue), animated=\(animated)")
    }

    func onCameraMoved() {
        var mlnCamera = _mapView.camera
        var center = LngLat(
            lng: mlnCamera.centerCoordinate.longitude,
            lat: mlnCamera.centerCoordinate.latitude
        )
        // NOT mlnCamera.altitude. MLNMapCamera has no zoom property; altitude is
        // metres above the ground, so every camera update shipped a number in the
        // millions to Dart as "zoom" (measured: 8871981.1 at a European overview).
        // getCamera().zoom was therefore garbage for every caller, which is what
        // the zoom buttons were working around by keeping their own counter.
        // getMetersPerPixelAtLatitude/zoomLevel elsewhere in this file already
        // read _mapView.zoomLevel, which is the real zoom.
        var pigeonCamera = MapCamera(
            center: center, zoom: _mapView.zoomLevel, pitch: mlnCamera.pitch,
            bearing: mlnCamera.heading
        )
        _flutterApi.onMoveCamera(camera: pigeonCamera) { _ in }  // Remove asterisks
    }

    // MARK: - MapLibreHostApi Implementation

    func addFillLayer(
        id: String,
        sourceId: String,
        layout: [String: Any],
        paint: [String: Any],
        belowLayerId: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Guard against nil _mapView before accessing it
        guard _mapView != nil else {
            print("iOS: Error - MapView not initialized for addFillLayer")
            completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
            return
        }

        guard let style = _mapView.style else {
            completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
            return
        }

        guard let source = style.source(withIdentifier: sourceId) else {
            completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Source not found: \(sourceId)"])))
            return
        }

        let layer = MLNFillStyleLayer(identifier: id, source: source)
        applyFillProperties(to: layer, paint: paint, layout: layout)

        if let belowLayerId = belowLayerId {
            if let belowLayer = style.layer(withIdentifier: belowLayerId) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
        } else {
            style.addLayer(layer)
        }

        completion(.success(()))
    }

    private func applyFillProperties(to layer: MLNFillStyleLayer, paint: [String: Any], layout: [String: Any]) {
        // Apply paint properties — wrap in ObjC exception catcher for safety
        paint.forEach { key, value in
            let success = MLNExpressionCatcher.performSafely {
                switch key {
                case "fill-color": layer.fillColor = self.parseColor(value)
                case "fill-opacity": layer.fillOpacity = self.parseValue(value)
                case "fill-outline-color": layer.fillOutlineColor = self.parseColor(value)
                case "fill-pattern": layer.fillPattern = NSExpression(forConstantValue: value)
                default: break
                }
            }
            if !success {
                print("iOS: ⚠️ Skipped fill paint property '\(key)' (ObjC exception caught safely)")
            }
        }

        // Apply layout properties — wrap in ObjC exception catcher for safety
        layout.forEach { key, value in
            let success = MLNExpressionCatcher.performSafely {
                switch key {
                case "visibility": layer.isVisible = (value as? String == "visible")
                case "fill-sort-key": layer.fillSortKey = self.parseValue(value)
                default: break
                }
            }
            if !success {
                print("iOS: ⚠️ Skipped fill layout property '\(key)' (ObjC exception caught safely)")
            }
        }
    }

    func addCircleLayer(
        id: String,
        sourceId: String,
        layout: [String: Any],
        paint: [String: Any],
        belowLayerId: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Guard against nil _mapView before accessing it
        guard _mapView != nil else {
            print("iOS: Error - MapView not initialized for addCircleLayer")
            completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
            return
        }

        guard let style = _mapView.style else {
            completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
            return
        }

        guard let source = style.source(withIdentifier: sourceId) else {
            completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Source not found: \(sourceId)"])))
            return
        }

        // NOTE: this used to bail out here when the source already had the
        // auto-created cluster layers ("<id>-clusters" / "<id>-unclustered"),
        // reporting .success while adding nothing. That silently discarded
        // every circle layer an app added to a clustered source, so cluster
        // styling supplied from Dart was impossible on iOS -- the app got the
        // plugin's hardcoded defaults and no error. Android has never had this
        // guard: it auto-creates the same layers AND honours the app's, which
        // then draw on top. Match Android.
        print("iOS: Adding circle layer for source: \(sourceId)")
        let layer = MLNCircleStyleLayer(identifier: id, source: source)

        // Handle source-layer property for vector tile sources
        // DEBUG: Log the entire layout to see what we're receiving
        NSLog("🔴 iOS NATIVE: addCircleLayer received layout: %@", layout as NSDictionary)
        NSLog("🔴 iOS NATIVE: layout keys: %@", layout.keys.joined(separator: ", "))

        // DEBUG: Check if source is a vector tile source and FORCE sourceLayerIdentifier
        if source is MLNVectorTileSource {
            print("iOS: Source \(sourceId) IS a vector tile source!")
            NSLog("🔴 iOS NATIVE: Source is MLNVectorTileSource - will set sourceLayerIdentifier")

            // FORCE set to "pois" for poi-source (the actual POI layer in tiles), otherwise use layout value
            if sourceId == "poi-source" || id.contains("poi-debug") {
                layer.sourceLayerIdentifier = "pois"
                print("iOS: FORCED sourceLayerIdentifier to 'pois' for layer: \(id)")
                NSLog("🔴 iOS NATIVE: FORCED sourceLayerIdentifier to 'pois'")
            } else if let sourceLayer = layout["source-layer"] as? String {
                layer.sourceLayerIdentifier = sourceLayer
                print("iOS: Set source-layer from layout to: \(sourceLayer)")
            }
        } else {
            print("iOS: Source \(sourceId) is NOT a vector tile source (type: \(type(of: source)))")
        }

        if let sourceLayer = layout["source-layer"] as? String {
            layer.sourceLayerIdentifier = sourceLayer
            NSLog("🔴 iOS NATIVE: Set sourceLayerIdentifier to: %@", sourceLayer)
            print("iOS: Set source-layer to: \(sourceLayer)")
        } else {
            NSLog("🔴 iOS NATIVE: WARNING - source-layer not found or not a String!")
            NSLog("🔴 iOS NATIVE: source-layer value type: %@", String(describing: type(of: layout["source-layer"])))
        }

        // Handle __filter__ property for filtering features
        if let filterArray = layout["__filter__"] as? [Any] {
            print("iOS: Found filter in layout for circle layer: \(filterArray)")
            if let predicate = predicateFromFilter(filterArray) {
                layer.predicate = predicate
                print("iOS: Applied filter predicate to circle layer")
            } else {
                print("iOS: Warning - Could not convert filter to predicate for circle layer")
            }
        }

        // Handle __minZoom__ and __maxZoom__ for zoom level restrictions
        if let minZoom = layout["__minZoom__"] as? Double {
            layer.minimumZoomLevel = Float(minZoom)
            print("iOS: Set circle layer minZoom to: \(minZoom)")
        }
        if let maxZoom = layout["__maxZoom__"] as? Double {
            layer.maximumZoomLevel = Float(maxZoom)
            print("iOS: Set circle layer maxZoom to: \(maxZoom)")
        }

        applyCircleProperties(to: layer, paint: paint, layout: layout)

        if let belowLayerId = belowLayerId {
            if let belowLayer = style.layer(withIdentifier: belowLayerId) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
        } else {
            style.addLayer(layer)
        }

        // DEBUG: Verify the layer was added and has correct properties
        if let addedLayer = style.layer(withIdentifier: id) as? MLNCircleStyleLayer {
            print("✅ iOS: Verified circle layer '\(id)' exists in style")
            print("✅ iOS: Layer sourceLayerIdentifier: \(addedLayer.sourceLayerIdentifier ?? "nil")")
            print("✅ iOS: Layer circleRadius: \(addedLayer.circleRadius)")
            print("✅ iOS: Layer circleColor: \(addedLayer.circleColor)")
            NSLog("🔴 iOS NATIVE: Layer verified - sourceLayerIdentifier: %@", addedLayer.sourceLayerIdentifier ?? "nil")
        } else {
            print("❌ iOS: Could not verify layer '\(id)' in style!")
            NSLog("🔴 iOS NATIVE: FAILED to verify layer in style!")
        }

        completion(.success(()))
    }

    private func applyCircleProperties(to layer: MLNCircleStyleLayer, paint: [String: Any], layout: [String: Any]) {

        // Apply paint properties — wrap in ObjC exception catcher for safety
        paint.forEach { key, value in
            let success = MLNExpressionCatcher.performSafely {
                switch key {
                case "circle-radius":
                    layer.circleRadius = self.createExpression(from: value)
                case "circle-color":
                    layer.circleColor = self.createExpression(from: value)
                case "circle-opacity":
                    layer.circleOpacity = self.createExpression(from: value)
                case "circle-stroke-width":
                    layer.circleStrokeWidth = self.createExpression(from: value)
                case "circle-stroke-color":
                    layer.circleStrokeColor = self.createExpression(from: value)
                case "circle-stroke-opacity":
                    layer.circleStrokeOpacity = self.createExpression(from: value)
                case "circle-blur":
                    layer.circleBlur = self.createExpression(from: value)
                default:
                    print("iOS: Unknown circle paint property: \(key)")
                }
            }
            if !success {
                print("iOS: ⚠️ Skipped circle paint property '\(key)' (ObjC exception caught safely)")
            }
        }

        // Apply layout properties — wrap in ObjC exception catcher for safety
        layout.forEach { key, value in
            let success = MLNExpressionCatcher.performSafely {
                switch key {
                case "visibility":
                    layer.isVisible = (value as? String == "visible")
                case "circle-sort-key":
                    layer.circleSortKey = self.createExpression(from: value)
                default:
                    print("iOS: Unknown circle layout property: \(key)")
                }
            }
            if !success {
                print("iOS: ⚠️ Skipped circle layout property '\(key)' (ObjC exception caught safely)")
            }
        }
    }
    // The key method - this creates NSExpression from any value type
    private func createExpression(from value: Any) -> NSExpression {
        print("iOS: Creating expression from: \(value) (type: \(type(of: value)))")

        // Handle different value types
        switch value {
        case let arrayValue as [Any]:
            // This is likely a MapMetrics expression array
            if !arrayValue.isEmpty && arrayValue.first is String {
                print("iOS: Found expression array, building native NSExpression...")

                // FIRST: Try to build native NSExpression directly
                // This handles complex case/match/has expressions that mglJSONObject can't handle
                if let nativeExpr = buildNativeExpression(arrayValue) {
                    print("iOS: ✅ Successfully built native NSExpression")
                    return nativeExpr
                }

                // SECOND: Try MapLibre's mglJSONObject converter via ObjC exception catcher
                print("iOS: Native builder didn't handle this, trying mglJSONObject via safe catcher...")
                if let safeExpr = MLNExpressionCatcher.tryMglJSONObject(arrayValue) {
                    print("iOS: ✅ mglJSONObject succeeded via safe catcher")
                    return safeExpr
                } else {
                    print("iOS: ⚠️ mglJSONObject failed (ObjC exception caught safely)")
                    print("iOS: Expression that failed: \(arrayValue)")

                    // Return nil constant instead of crashing - graceful degradation
                    print("iOS: ⚠️ Expression not supported, returning nil constant: \(arrayValue)")
                    return NSExpression(forConstantValue: nil)
                }
            } else {
                // Regular array
                return NSExpression(forConstantValue: arrayValue)
            }

        case let stringValue as String:
            // Handle color strings and regular strings
            if isColorString(stringValue) {
                if let color = getColorFromNameOrHex(stringValue) {
                    return NSExpression(forConstantValue: color)
                }
            }
            return NSExpression(forConstantValue: stringValue)

        default:
            // Numbers, etc.
            return NSExpression(forConstantValue: value)
        }
    }

    // Convert MapLibre filter expression to NSPredicate (handles 'all', 'any' compound operators)
    private func predicateFromFilter(_ filter: [Any]) -> NSPredicate? {
        guard !filter.isEmpty, let op = filter.first as? String else {
            return nil
        }

        switch op {
        case "all":
            // ['all', predicate1, predicate2, ...] -> AND compound predicate
            var subpredicates: [NSPredicate] = []
            for i in 1..<filter.count {
                if let subFilter = filter[i] as? [Any], let subPredicate = predicateFromFilter(subFilter) {
                    subpredicates.append(subPredicate)
                }
            }
            if subpredicates.isEmpty {
                return nil
            }
            return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        case "any":
            // ['any', predicate1, predicate2, ...] -> OR compound predicate
            var subpredicates: [NSPredicate] = []
            for i in 1..<filter.count {
                if let subFilter = filter[i] as? [Any], let subPredicate = predicateFromFilter(subFilter) {
                    subpredicates.append(subPredicate)
                }
            }
            if subpredicates.isEmpty {
                return nil
            }
            return NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)

        case "!":
            // ['!', predicate] -> NOT compound predicate
            // Example: ['!', ['has', 'highway']] -> NOT (highway != nil)
            if filter.count >= 2, let subFilter = filter[1] as? [Any],
               let subPredicate = predicateFromFilter(subFilter) {
                print("iOS: Creating NOT predicate for: \(subFilter)")
                return NSCompoundPredicate(notPredicateWithSubpredicate: subPredicate)
            }
            return nil

        default:
            // For simple predicates, use buildPredicate
            return buildPredicate(from: filter)
        }
    }

    // Build NSPredicate from expression array (for use in conditionals)
    private func buildPredicate(from expression: [Any]) -> NSPredicate? {
        guard !expression.isEmpty, let op = expression.first as? String else {
            return nil
        }

        switch op {
        case "all":
            // ['all', pred1, pred2, ...] -> AND compound predicate
            var subpredicates: [NSPredicate] = []
            for i in 1..<expression.count {
                if let subFilter = expression[i] as? [Any], let subPredicate = buildPredicate(from: subFilter) {
                    subpredicates.append(subPredicate)
                }
            }
            return subpredicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        case "any":
            // ['any', pred1, pred2, ...] -> OR compound predicate
            var subpredicates: [NSPredicate] = []
            for i in 1..<expression.count {
                if let subFilter = expression[i] as? [Any], let subPredicate = buildPredicate(from: subFilter) {
                    subpredicates.append(subPredicate)
                }
            }
            return subpredicates.isEmpty ? nil : NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)

        case "has":
            // ['has', 'key'] -> keyPath != nil
            if expression.count >= 2, let key = expression[1] as? String {
                let keyPathExpr = NSExpression(forKeyPath: key)
                let nilExpr = NSExpression(forConstantValue: nil)
                return NSComparisonPredicate(
                    leftExpression: keyPathExpr,
                    rightExpression: nilExpr,
                    modifier: .direct,
                    type: .notEqualTo
                )
            }

        case "==", "!=", "<", ">", "<=", ">=":
            if expression.count >= 3 {
                let leftExpr: NSExpression
                if let leftArray = expression[1] as? [Any], let built = buildNativeExpression(leftArray) {
                    leftExpr = built
                } else {
                    leftExpr = NSExpression(forConstantValue: expression[1])
                }

                let rightExpr: NSExpression
                if let rightArray = expression[2] as? [Any], let built = buildNativeExpression(rightArray) {
                    rightExpr = built
                } else {
                    rightExpr = NSExpression(forConstantValue: expression[2])
                }

                let predicateType: NSComparisonPredicate.Operator
                switch op {
                case "==": predicateType = .equalTo
                case "!=": predicateType = .notEqualTo
                case "<": predicateType = .lessThan
                case ">": predicateType = .greaterThan
                case "<=": predicateType = .lessThanOrEqualTo
                case ">=": predicateType = .greaterThanOrEqualTo
                default: return nil
                }

                return NSComparisonPredicate(
                    leftExpression: leftExpr,
                    rightExpression: rightExpr,
                    modifier: .direct,
                    type: predicateType
                )
            }

        case "!":
            // ['!', subExpression] -> NOT predicate
            // Example: ['!', ['has', 'highway']] -> NOT (highway != nil)
            if expression.count >= 2, let subExpr = expression[1] as? [Any] {
                if let subPredicate = buildPredicate(from: subExpr) {
                    print("iOS: buildPredicate creating NOT for: \(subExpr)")
                    return NSCompoundPredicate(notPredicateWithSubpredicate: subPredicate)
                }
            }

        default:
            break
        }

        return nil
    }

    // Build native NSExpression directly from MapLibre expression array
    // This bypasses the mglJSONObject converter which has limitations
    private func buildNativeExpression(_ expression: [Any]) -> NSExpression? {
        guard !expression.isEmpty, let op = expression.first as? String else {
            return nil
        }

        print("iOS: Building native NSExpression for operator: \(op)")

        switch op {
        case "accumulated":
            // ['accumulated'] -> The accumulated cluster property value
            // Used in clusterProperties reduce expressions
            // CRITICAL: Must use "$accumulated" (with $ prefix) so that MapLibre's
            // mgl_jsonExpressionObject serializes it back to ["accumulated"], not ["var", "accumulated"]
            return NSExpression(forVariable: "$accumulated")

        case "get":
            // ['get', 'property_name'] -> NSExpression for key path
            if expression.count >= 2, let key = expression[1] as? String {
                return NSExpression(forKeyPath: key)
            }

        case "has", "==", "!=", "<", ">", "<=", ">=":
            // Comparison operators should not be used as value expressions
            // They should only appear as conditions in case expressions
            // If we encounter them here, return nil to signal they should be handled differently
            print("iOS: Comparison operator '\(op)' found in value context - should be in predicate context")
            return nil

        case "case":
            // ['case', condition1, output1, condition2, output2, ..., fallback]
            // Build NSExpression conditional: TERNARY(condition, trueValue, falseValue)
            if expression.count >= 4 {
                // Start from the end with the fallback value
                var resultExpr: NSExpression
                if let fallbackArray = expression.last as? [Any], let built = buildNativeExpression(fallbackArray) {
                    resultExpr = built
                } else if let colorStr = expression.last as? String, isColorString(colorStr),
                          let color = getColorFromNameOrHex(colorStr) {
                    resultExpr = NSExpression(forConstantValue: color)
                } else {
                    resultExpr = NSExpression(forConstantValue: expression.last!)
                }

                // Work backwards through condition/value pairs
                var i = expression.count - 2  // Start before fallback
                while i >= 2 {  // Pairs are at indices 1-2, 3-4, etc.
                    let outputValue = expression[i]
                    let conditionValue = expression[i - 1]

                    // Build output expression (convert color strings to UIColor)
                    let outputExpr: NSExpression
                    if let outputArray = outputValue as? [Any], let built = buildNativeExpression(outputArray) {
                        outputExpr = built
                    } else if let colorStr = outputValue as? String, isColorString(colorStr),
                              let color = getColorFromNameOrHex(colorStr) {
                        outputExpr = NSExpression(forConstantValue: color)
                    } else {
                        outputExpr = NSExpression(forConstantValue: outputValue)
                    }

                    // Build condition predicate
                    // conditionValue should be an array like ["==", ["get", "key"], "value"]
                    let conditionPredicate: NSPredicate
                    if let condArray = conditionValue as? [Any], let op = condArray.first as? String {
                        // Build predicate from comparison expression
                        conditionPredicate = buildPredicate(from: condArray) ?? NSPredicate(value: false)
                    } else if let boolValue = conditionValue as? Bool {
                        conditionPredicate = NSPredicate(value: boolValue)
                    } else {
                        conditionPredicate = NSPredicate(value: false)
                    }

                    // Build TERNARY: TERNARY(predicate, trueValue, falseValue)
                    resultExpr = NSExpression(
                        forConditional: conditionPredicate,
                        trueExpression: outputExpr,
                        falseExpression: resultExpr
                    )

                    i -= 2
                }

                return resultExpr
            }

        case "match":
            // ['match', input, label1, output1, label2, output2, ..., fallback]
            // Convert to case expression
            if expression.count >= 4 {
                let input = expression[1]
                var caseExpr: [Any] = ["case"]

                var i = 2
                while i < expression.count - 1 {
                    let matchValue = expression[i]
                    let outputValue = expression[i + 1]

                    // Create condition: input == matchValue
                    caseExpr.append(["==", input, matchValue])
                    caseExpr.append(outputValue)

                    i += 2
                }

                // Add fallback
                caseExpr.append(expression.last!)

                // Recursively build the case expression
                return buildNativeExpression(caseExpr)
            }

        case "concat":
            // ['concat', str1, str2, ...] -> String concatenation
            if expression.count >= 2 {
                var arguments: [NSExpression] = []
                for i in 1..<expression.count {
                    if let argArray = expression[i] as? [Any], let built = buildNativeExpression(argArray) {
                        arguments.append(built)
                    } else {
                        arguments.append(NSExpression(forConstantValue: expression[i]))
                    }
                }

                return NSExpression(forFunction: "stringByAppendingString:", arguments: arguments)
            }

        case "coalesce":
            // ['coalesce', val1, val2, ...] -> Return first non-null value
            // CRITICAL: Must use mgl_coalesce: function so that MapLibre's
            // mgl_jsonExpressionObject serializes it back to ["coalesce", ...],
            // NOT ["case", ...] which happens with NSExpression(forConditional:).
            if expression.count >= 2 {
                var arguments: [NSExpression] = []
                for i in 1..<expression.count {
                    let value = expression[i]
                    if let valueArray = value as? [Any], let built = buildNativeExpression(valueArray) {
                        arguments.append(built)
                    } else {
                        arguments.append(NSExpression(forConstantValue: value))
                    }
                }
                // mgl_coalesce: takes a single aggregate argument containing all values
                return NSExpression(
                    forFunction: "mgl_coalesce:",
                    arguments: [NSExpression(forAggregate: arguments)]
                )
            }

        case "interpolate":
            // ['interpolate', ['linear'], ['zoom'], stop1, output1, stop2, output2, ...]
            // Use MapLibre's mglJSONObject via ObjC exception catcher for safety
            print("iOS: Processing interpolate expression")
            if let result = MLNExpressionCatcher.tryMglJSONObject(expression) {
                print("iOS: ✅ Successfully built interpolate NSExpression via safe catcher")
                return result
            } else {
                print("iOS: ⚠️ Failed to build interpolate expression (ObjC exception caught)")
                return nil
            }

        case "step":
            // ['step', input, defaultValue, stop1, output1, stop2, output2, ...]
            // Use MapLibre's mglJSONObject via ObjC exception catcher for safety
            print("iOS: Processing step expression")
            if let result = MLNExpressionCatcher.tryMglJSONObject(expression) {
                print("iOS: ✅ Successfully built step NSExpression via safe catcher")
                return result
            } else {
                print("iOS: ⚠️ Failed to build step expression (ObjC exception caught)")
                return nil
            }

        default:
            print("iOS: Unsupported native expression operator: \(op)")
            return nil
        }

        return nil
    }

    /// Build NSExpression safely from a JSON expression array.
    /// Uses buildNativeExpression first, falls back to mglJSONObject with error handling.
    /// Returns nil if the expression cannot be parsed (instead of crashing).
    private func buildSafeExpression(from jsonExpr: [Any]) -> NSExpression? {
        // Try the native builder first — handles accumulated, get, coalesce, etc.
        if let expr = buildNativeExpression(jsonExpr) {
            return expr
        }
        // Fallback: try mglJSONObject via ObjC exception catcher (catches NSException safely)
        if let result = MLNExpressionCatcher.tryMglJSONObject(jsonExpr) {
            return result
        }
        print("iOS: ⚠️ buildSafeExpression failed for \(jsonExpr)")
        return nil
    }

    /// Build the "reduce" expression for a cluster property.
    /// Input JSON example: ["coalesce", ["accumulated"], ["get", "clusterIconId"]]
    /// Uses MapLibre's official NSExpression API with $featureAccumulated variable.
    private func buildClusterReduceExpression(key: String, reduceJson: [Any]) -> NSExpression? {
        guard !reduceJson.isEmpty, let op = reduceJson.first as? String else {
            print("iOS: ⚠️ Empty or invalid reduce expression")
            return nil
        }

        print("iOS: Building cluster reduce expression, op='\(op)' for key='\(key)'")

        // Map the operator to the NSExpression format string function name
        // MapLibre iOS expects: NSExpression(format: "FUNCTION:({$featureAccumulated, key})")
        // Where FUNCTION is sum:, max:, min:, etc.
        // For coalesce: use mgl_coalesce: function
        let functionName: String
        switch op {
        case "coalesce":
            functionName = "mgl_coalesce:"
        case "+", "sum":
            functionName = "sum:"
        case "max":
            functionName = "max:"
        case "min":
            functionName = "min:"
        case "concat":
            functionName = "mgl_join:"
        case "any":
            functionName = "mgl_any:"
        case "all":
            functionName = "mgl_all:"
        default:
            print("iOS: ⚠️ Unsupported cluster reduce operator: \(op)")
            return nil
        }

        // Build using NSExpression(format:) which MapLibre can properly round-trip
        // The format uses $featureAccumulated which MapLibre knows how to serialize
        let formatString = "\(functionName)({$featureAccumulated, \(key)})"
        print("iOS: Using format string: \(formatString)")

        do {
            let expr = NSExpression(format: formatString)
            print("iOS: ✅ Successfully built reduce expression via format string")
            return expr
        } catch {
            print("iOS: ⚠️ NSExpression(format:) failed: \(error)")
            return nil
        }
    }

    /// Build the "map" expression for a cluster property.
    /// Input JSON example: ["get", "iconId"]
    /// Returns an NSExpression that extracts the property value from each feature.
    private func buildClusterMapExpression(mapJson: [Any]) -> NSExpression? {
        guard !mapJson.isEmpty, let op = mapJson.first as? String else {
            print("iOS: ⚠️ Empty or invalid map expression")
            return nil
        }

        if op == "get", mapJson.count >= 2, let key = mapJson[1] as? String {
            return NSExpression(forKeyPath: key)
        }

        // Fallback: try buildSafeExpression for other map expression types
        return buildSafeExpression(from: mapJson)
    }

    // Convert unsupported MapLibre expressions to iOS-compatible ones
    private func convertUnsupportedExpressions(_ expression: [Any]) -> [Any] {
        // This function is kept for backward compatibility but simplified
        // Most work is now done in buildNativeExpression
        guard !expression.isEmpty, let op = expression.first as? String else {
            return expression
        }

        print("iOS: Checking expression operator: \(op)")

        // Recursively process nested arrays
        switch op {
        case "get", "has", "==", "!=", "<", ">", "<=", ">=",
             "case", "match", "coalesce", "concat", "to-string",
             "step", "interpolate":
            // These are now handled by buildNativeExpression
            return expression

        default:
            // For unknown operators, recursively convert nested expressions
            var convertedExpr: [Any] = [op]
            for i in 1..<expression.count {
                let item = expression[i]
                if let itemArray = item as? [Any] {
                    convertedExpr.append(convertUnsupportedExpressions(itemArray))
                } else {
                    convertedExpr.append(item)
                }
            }
            return convertedExpr
        }
    }

    private func isColorString(_ string: String) -> Bool {
        return string.hasPrefix("#") ||
            string.hasPrefix("rgb") ||
            string.hasPrefix("rgba") ||
            ["white", "black", "red", "blue", "green", "yellow", "orange", "purple", "gray", "grey", "brown", "pink", "cyan", "magenta"].contains(string.lowercased())
    }

    private func getColorFromNameOrHex(_ colorString: String) -> UIColor? {
        // First try hex parsing
        if let hexColor = UIColor(hexString: colorString) {
            return hexColor
        }

        // Then try color names
        switch colorString.lowercased() {
        case "white": return UIColor.white
        case "black": return UIColor.black
        case "red": return UIColor.red
        case "blue": return UIColor.blue
        case "green": return UIColor.green
        case "yellow": return UIColor.yellow
        case "orange": return UIColor.orange
        case "purple": return UIColor.purple
        case "gray", "grey": return UIColor.gray
        case "brown": return UIColor.brown
        case "pink": return UIColor.systemPink
        case "cyan": return UIColor.cyan
        case "magenta": return UIColor.magenta
        default: return nil
        }
    }

    func addBackgroundLayer(
        id: String,
        layout: [String: Any],
        paint: [String: Any],
        belowLayerId: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Guard against nil _mapView before accessing it
        guard _mapView != nil else {
            print("iOS: Error - MapView not initialized for addBackgroundLayer")
            completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
            return
        }

        guard let style = _mapView.style else {
            completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
            return
        }

        let layer = MLNBackgroundStyleLayer(identifier: id)
        applyBackgroundProperties(to: layer, paint: paint, layout: layout)

        if let belowLayerId = belowLayerId {
            if let belowLayer = style.layer(withIdentifier: belowLayerId) {
                style.insertLayer(layer, below: belowLayer)
            } else {
                style.addLayer(layer)
            }
        } else {
            style.addLayer(layer)
        }

        completion(.success(()))
    }

    private func applyBackgroundProperties(to layer: MLNBackgroundStyleLayer, paint: [String: Any], layout: [String: Any]) {
        // Apply paint properties — wrap in ObjC exception catcher for safety
        paint.forEach { key, value in
            let success = MLNExpressionCatcher.performSafely {
                switch key {
                case "background-color": layer.backgroundColor = self.parseColor(value)
                case "background-opacity": layer.backgroundOpacity = self.parseValue(value)
                case "background-pattern": layer.backgroundPattern = NSExpression(forConstantValue: value)
                default: break
                }
            }
            if !success {
                print("iOS: ⚠️ Skipped background paint property '\(key)' (ObjC exception caught safely)")
            }
        }

        // Apply layout properties — wrap in ObjC exception catcher for safety
        layout.forEach { key, value in
            let success = MLNExpressionCatcher.performSafely {
                switch key {
                case "visibility": layer.isVisible = (value as? String == "visible")
                default: break
                }
            }
            if !success {
                print("iOS: ⚠️ Skipped background layout property '\(key)' (ObjC exception caught safely)")
            }
        }
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
      id: String,
      sourceId: String,
      layout: [String: Any],
      paint: [String: Any],
      belowLayerId: String?,
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      print("iOS: addLineLayer called with id: \(id), sourceId: \(sourceId)")
      print("iOS: Paint properties: \(paint)")
      print("iOS: Layout properties: \(layout)")

      // Guard against nil _mapView before accessing it
      guard _mapView != nil else {
        print("iOS: Error - MapView not initialized for addLineLayer")
        completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
        return
      }

      guard let style = _mapView.style else {
        print("iOS: Error - Style not available for addLineLayer")
        completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
        return
      }

      // Check if layer already exists and remove it first
      if let existingLayer = style.layer(withIdentifier: id) {
        print("iOS: Removing existing line layer with id: \(id)")
        style.removeLayer(existingLayer)
      }

      guard let source = style.source(withIdentifier: sourceId) else {
        print("iOS: Error - Source not found with ID: \(sourceId)")
        completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Source not found: \(sourceId)"])))
        return
      }

      print("iOS: Creating line layer with source: \(sourceId)")
      let lineLayer = MLNLineStyleLayer(identifier: id, source: source)

      // Handle source-layer property for vector tile sources.
      // Without this, an MLNLineStyleLayer backed by an MLNVectorTileSource
      // never names a layer inside the MVT, so MapLibre renders nothing.
      // (Mirror of the Circle/Symbol layer handling in this file.)
      if let sourceLayer = layout["source-layer"] as? String {
        lineLayer.sourceLayerIdentifier = sourceLayer
        print("iOS: Set line-layer source-layer to: \(sourceLayer)")
      }

      // Apply paint properties
      for (key, value) in paint {
        print("iOS: Processing paint property \(key) = \(value) (type: \(type(of: value)))")

        switch key {
        case "line-width":
          if let width = value as? NSNumber {
            lineLayer.lineWidth = NSExpression(forConstantValue: width)
            print("iOS: Set line-width to \(width)")
          } else if let width = value as? Double {
            lineLayer.lineWidth = NSExpression(forConstantValue: NSNumber(value: width))
            print("iOS: Set line-width to \(width)")
          } else if let width = value as? Int {
            lineLayer.lineWidth = NSExpression(forConstantValue: NSNumber(value: width))
            print("iOS: Set line-width to \(width)")
          }

        case "line-color":
          var color: UIColor? = nil
          if let expressionArray = value as? [Any],
             let operatorName = expressionArray.first as? String {
            lineLayer.lineColor = createExpression(from: expressionArray)
            print("iOS: Set line-color from expression: \(operatorName)")
            continue
          } else if let colorArray = value as? [Any], colorArray.count >= 3 {
            // Handle RGBA array format [r, g, b, a]. Expression arrays are
            // handled above; treating ['get', 'color'] as RGBA makes iOS
            // fall back to black for data-driven MVT line colors.
            if let r = colorArray[0] as? Double,
               let g = colorArray[1] as? Double,
               let b = colorArray[2] as? Double {
              let a = colorArray.count > 3 ? (colorArray[3] as? Double ?? 1.0) : 1.0
              color = UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
              print("iOS: Set line-color from RGBA array: [\(r), \(g), \(b), \(a)]")
            }
          } else if let colorString = value as? String {
            color = UIColor(hexString: colorString) ?? UIColor.black
            print("iOS: Set line-color from hex string: \(colorString)")
          }

          if let color = color {
            lineLayer.lineColor = NSExpression(forConstantValue: color)
          } else {
            print("iOS: Warning - Could not convert line-color value: \(value)")
            lineLayer.lineColor = NSExpression(forConstantValue: UIColor.black)
          }

        case "line-opacity":
          if let opacity = value as? NSNumber {
            lineLayer.lineOpacity = NSExpression(forConstantValue: opacity)
            print("iOS: Set line-opacity to \(opacity)")
          } else if let opacity = value as? Double {
            lineLayer.lineOpacity = NSExpression(forConstantValue: NSNumber(value: opacity))
            print("iOS: Set line-opacity to \(opacity)")
          }

        case "line-gap-width":
          if let gapWidth = value as? NSNumber {
            lineLayer.lineGapWidth = NSExpression(forConstantValue: gapWidth)
            print("iOS: Set line-gap-width to \(gapWidth)")
          } else if let gapWidth = value as? Double {
            lineLayer.lineGapWidth = NSExpression(forConstantValue: NSNumber(value: gapWidth))
            print("iOS: Set line-gap-width to \(gapWidth)")
          } else if let gapWidth = value as? Int {
            lineLayer.lineGapWidth = NSExpression(forConstantValue: NSNumber(value: gapWidth))
            print("iOS: Set line-gap-width to \(gapWidth)")
          }

        case "line-blur":
          if let blur = value as? NSNumber {
            lineLayer.lineBlur = NSExpression(forConstantValue: blur)
            print("iOS: Set line-blur to \(blur)")
          } else if let blur = value as? Double {
            lineLayer.lineBlur = NSExpression(forConstantValue: NSNumber(value: blur))
            print("iOS: Set line-blur to \(blur)")
          } else if let blur = value as? Int {
            lineLayer.lineBlur = NSExpression(forConstantValue: NSNumber(value: blur))
            print("iOS: Set line-blur to \(blur)")
          }

        case "line-dasharray":
          if let dashArray = value as? [Any] {
            let numberArray = dashArray.compactMap { item -> NSNumber? in
              if let number = item as? NSNumber {
                return number
              } else if let double = item as? Double {
                return NSNumber(value: double)
              } else if let int = item as? Int {
                return NSNumber(value: int)
              }
              return nil
            }
            if !numberArray.isEmpty {
              lineLayer.lineDashPattern = NSExpression(forConstantValue: numberArray)
              print("iOS: Set line-dasharray to \(numberArray)")
            }
          } else if let dashArray = value as? [NSNumber] {
            lineLayer.lineDashPattern = NSExpression(forConstantValue: dashArray)
            print("iOS: Set line-dasharray to \(dashArray)")
          }

        default:
          print("iOS: Unknown paint property: \(key)")
        }
      }

      // Apply layout properties
      for (key, value) in layout {
        print("iOS: Processing layout property \(key) = \(value)")
        switch key {
        case "visibility":
          if let visibility = value as? String {
            lineLayer.isVisible = (visibility == "visible")
            print("iOS: Set visibility to \(visibility)")
          }
        case "line-cap":
          if let lineCap = value as? String {
            switch lineCap {
            case "butt":
              lineLayer.lineCap = NSExpression(forConstantValue: "butt")
            case "round":
              lineLayer.lineCap = NSExpression(forConstantValue: "round")
            case "square":
              lineLayer.lineCap = NSExpression(forConstantValue: "square")
            default:
              print("iOS: Unknown line-cap value: \(lineCap)")
            }
            print("iOS: Set line-cap to \(lineCap)")
          }
        case "line-join":
          if let lineJoin = value as? String {
            switch lineJoin {
            case "bevel":
              lineLayer.lineJoin = NSExpression(forConstantValue: "bevel")
            case "round":
              lineLayer.lineJoin = NSExpression(forConstantValue: "round")
            case "miter":
              lineLayer.lineJoin = NSExpression(forConstantValue: "miter")
            default:
              print("iOS: Unknown line-join value: \(lineJoin)")
            }
            print("iOS: Set line-join to \(lineJoin)")
          }
        default:
          print("iOS: Unknown layout property: \(key)")
        }
      }

      // Add the layer to the style
      if let belowLayerId = belowLayerId {
        if let belowLayer = style.layer(withIdentifier: belowLayerId) {
          style.insertLayer(lineLayer, below: belowLayer)
          print("iOS: Line layer '\(id)' added below layer '\(belowLayerId)'")
        } else {
          print("iOS: Warning - Below layer '\(belowLayerId)' not found, adding to top")
          style.addLayer(lineLayer)
        }
      } else {
        style.addLayer(lineLayer)
        print("iOS: Line layer '\(id)' added to top of style")
      }

      print("iOS: Successfully added line layer '\(id)'")
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
    id: String,
    sourceId: String,
    layout: [String: Any],
    paint: [String: Any],
    belowLayerId: String?,
    completion: @escaping (Result<Void, Error>) -> Void
) {
    print("iOS: addSymbolLayer called - id: \(id), sourceId: \(sourceId)")
    print("iOS: Layout properties: \(layout)")
    print("iOS: Paint properties: \(paint)")

    guard _mapView != nil else {
        print("iOS: Error - MapView not yet initialized")
        completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not yet initialized"])))
        return
    }

    guard let style = _mapView.style else {
        print("iOS: Error - Style not available")
        completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
        return
    }

    guard let source = style.source(withIdentifier: sourceId) else {
        print("iOS: Error - Source not found: \(sourceId)")
        completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Source not found: \(sourceId)"])))
        return
    }

    let layer = MLNSymbolStyleLayer(identifier: id, source: source)

    // Handle source-layer property for vector tile sources
    if let sourceLayer = layout["source-layer"] as? String {
        layer.sourceLayerIdentifier = sourceLayer
        print("iOS: Set source-layer to: \(sourceLayer)")
    }

    // Handle __filter__ property for filtering features
    if let filterArray = layout["__filter__"] as? [Any] {
        print("iOS: Found filter in layout: \(filterArray)")
        if let predicate = predicateFromFilter(filterArray) {
            layer.predicate = predicate
            print("iOS: Applied filter predicate to symbol layer")
        } else {
            print("iOS: Warning - Could not convert filter to predicate")
        }
    }

    // Handle __minZoom__ and __maxZoom__ for zoom level restrictions
    if let minZoom = layout["__minZoom__"] as? Double {
        layer.minimumZoomLevel = Float(minZoom)
        print("iOS: Set symbol layer minZoom to: \(minZoom)")
    }
    if let maxZoom = layout["__maxZoom__"] as? Double {
        layer.maximumZoomLevel = Float(maxZoom)
        print("iOS: Set symbol layer maxZoom to: \(maxZoom)")
    }

    applySymbolProperties(to: layer, paint: paint, layout: layout)

    if let belowLayerId = belowLayerId {
        if let belowLayer = style.layer(withIdentifier: belowLayerId) {
            style.insertLayer(layer, below: belowLayer)
            print("iOS: SymbolLayer '\(id)' added below '\(belowLayerId)'")
        } else {
            style.addLayer(layer)
            print("iOS: belowLayer '\(belowLayerId)' not found, added '\(id)' to top")
        }
    } else {
        style.addLayer(layer)
        print("iOS: SymbolLayer '\(id)' added to top of layers")
    }

    completion(.success(()))
}

    private func applySymbolProperties(to layer: MLNSymbolStyleLayer, paint: [String: Any], layout: [String: Any]) {
        print("iOS: Applying symbol properties using proper MapLibre setters")

        // Apply paint properties — wrap in ObjC exception catcher for safety
        paint.forEach { key, value in
            let success = MLNExpressionCatcher.performSafely {
                switch key {
                case "icon-opacity":
                    layer.iconOpacity = self.createExpression(from: value)
                case "icon-color":
                    layer.iconColor = self.createExpression(from: value)
                case "icon-halo-color":
                    layer.iconHaloColor = self.createExpression(from: value)
                case "icon-halo-width":
                    layer.iconHaloWidth = self.createExpression(from: value)
                case "text-opacity":
                    layer.textOpacity = self.createExpression(from: value)
                case "text-color":
                    layer.textColor = self.createExpression(from: value)
                case "text-halo-color":
                    layer.textHaloColor = self.createExpression(from: value)
                case "text-halo-width":
                    layer.textHaloWidth = self.createExpression(from: value)
                default:
                    print("iOS: Unknown symbol paint property: \(key)")
                }
            }
            if !success {
                print("iOS: ⚠️ Skipped symbol paint property '\(key)' (ObjC exception caught safely)")
            }
        }

        // Apply layout properties — wrap in ObjC exception catcher for safety
        layout.forEach { key, value in
            if key == "source-layer" { return }

            let success = MLNExpressionCatcher.performSafely {
                switch key {
                case "visibility":
                    layer.isVisible = (value as? String == "visible")
                case "icon-image":
                    layer.iconImageName = self.createExpression(from: value)
                case "icon-size":
                    layer.iconScale = self.createExpression(from: value)
                case "icon-allow-overlap":
                    if let boolValue = value as? Bool {
                        layer.iconAllowsOverlap = NSExpression(forConstantValue: boolValue)
                    }
                case "icon-ignore-placement":
                    if let boolValue = value as? Bool {
                        layer.iconIgnoresPlacement = NSExpression(forConstantValue: boolValue)
                    }
                case "icon-padding":
                    layer.iconPadding = self.createExpression(from: value)
                case "icon-anchor":
                    layer.iconAnchor = self.createExpression(from: value)
                case "icon-offset":
                    layer.iconOffset = self.createExpression(from: value)
                case "icon-rotate", "icon-rotation":
                    layer.iconRotation = self.createExpression(from: value)
                case "text-field":
                    layer.text = self.createExpression(from: value)
                case "text-size":
                    layer.textFontSize = self.createExpression(from: value)
                case "text-font":
                    layer.textFontNames = self.createExpression(from: value)
                case "text-anchor":
                    layer.textAnchor = self.createExpression(from: value)
                case "text-offset":
                    layer.textOffset = self.createExpression(from: value)
                default:
                    print("iOS: Unknown symbol layout property: \(key)")
                }
            }
            if !success {
                print("iOS: ⚠️ Skipped symbol layout property '\(key)' (ObjC exception caught safely)")
            }
        }
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
        print("iOS: addImage called with id: \(id), data length: \(bytes.data.count)")

        // THREAD SAFETY: Decode image off main thread, then add to style on main thread with lock
        styleOperationQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView deallocated"])))
                return
            }

            let imageData = bytes.data

            // Decode image on background queue
            guard let image = UIImage(data: imageData, scale: 1.0) else {
                print("iOS: ERROR - Failed to decode UIImage from data")
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode image"])))
                }
                return
            }

            print("iOS: Image decoded successfully - size: \(image.size.width) x \(image.size.height), scale: \(image.scale)")

            // THREAD SAFETY: Acquire lock and execute on main thread
            self.styleLock.lock()
            DispatchQueue.main.async { [weak self] in
                defer { self?.styleLock.unlock() }

                guard let self = self else {
                    completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView deallocated"])))
                    return
                }

                guard self._isMapInitialized else {
                    print("iOS: Map not initialized, queueing addImage for '\(id)'")
                    self._pendingOperations.append { mapView in
                        guard let style = mapView.style else { return }
                        let ok = MLNExpressionCatcher.performSafely {
                            if style.image(forName: id) != nil {
                                style.removeImage(forName: id)
                            }
                            style.setImage(image, forName: id)
                        }
                        if ok {
                            print("iOS: ✅ Queued image '\(id)' added to style")
                        } else {
                            print("iOS: ⚠️ Queued image '\(id)' skipped due to ObjC exception")
                        }
                    }
                    completion(.success(()))
                    return
                }

                guard let mapView = self._mapView else {
                    completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not available"])))
                    return
                }

                guard let style = mapView.style else {
                    print("iOS: Style not available yet for addImage '\(id)'")
                    completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
                    return
                }

                // SAFETY: setImage can throw uncaught ObjC exceptions on iOS.
                // Use ObjC catcher to avoid process crash.
                let setOk = MLNExpressionCatcher.performSafely {
                    if style.image(forName: id) != nil {
                        style.removeImage(forName: id)
                    }
                    style.setImage(image, forName: id)
                }
                if !setOk {
                    completion(.failure(NSError(domain: "MapLibre", code: 3, userInfo: [NSLocalizedDescriptionKey: "ObjC exception while adding image"])))
                    return
                }

                // Verify the image was added
                if let verifyImage = style.image(forName: id) {
                    print("iOS: ✅ Image '\(id)' added to style successfully - verified size: \(verifyImage.size.width) x \(verifyImage.size.height)")
                } else {
                    print("iOS: ⚠️ WARNING - Image '\(id)' was set but cannot be retrieved from style")
                }

                completion(.success(()))
            }
        }
    }

    func addImages(
        ids: [String], images: [FlutterStandardTypedData],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("iOS: addImages called with \(ids.count) images")

        guard ids.count == images.count else {
            print("iOS: ERROR - ids and images count mismatch")
            completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "ids and images count mismatch"])))
            return
        }

        // THREAD SAFETY: Decode all images off main thread
        styleOperationQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView deallocated"])))
                return
            }

            // Decode all images on background queue
            var decodedImages: [(String, UIImage)] = []
            for (index, id) in ids.enumerated() {
                let imageData = images[index].data
                if let image = UIImage(data: imageData, scale: 1.0) {
                    decodedImages.append((id, image))
                } else {
                    print("iOS: Failed to decode image for id: \(id)")
                }
            }

            // THREAD SAFETY: Acquire lock and add to style on main thread
            self.styleLock.lock()
            DispatchQueue.main.async { [weak self] in
                defer { self?.styleLock.unlock() }

                guard let self = self else {
                    completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView deallocated"])))
                    return
                }

                guard self._isMapInitialized else {
                    print("iOS: Map not initialized, queueing addImages for \(decodedImages.count) images")
                    self._pendingOperations.append { mapView in
                        guard let style = mapView.style else { return }
                        for (id, image) in decodedImages {
                            _ = MLNExpressionCatcher.performSafely {
                                if style.image(forName: id) != nil {
                                    style.removeImage(forName: id)
                                }
                                style.setImage(image, forName: id)
                            }
                        }
                        print("iOS: ✅ Queued \(decodedImages.count) images added to style")
                    }
                    completion(.success(()))
                    return
                }

                guard let mapView = self._mapView else {
                    completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not available"])))
                    return
                }

                guard let style = mapView.style else {
                    print("iOS: ERROR - Style not available for addImages")
                    completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
                    return
                }

                // SAFE: Add all images to style
                var successCount = 0
                for (id, image) in decodedImages {
                    let ok = MLNExpressionCatcher.performSafely {
                        if style.image(forName: id) != nil {
                            style.removeImage(forName: id)
                        }
                        style.setImage(image, forName: id)
                    }
                    if ok {
                        successCount += 1
                    } else {
                        print("iOS: ⚠️ Skipped image '\(id)' due to ObjC exception in setImage")
                    }
                }

                print("iOS: addImages complete - success: \(successCount), total: \(ids.count)")
                completion(.success(()))
            }
        }
    }

    func addSprite(
        spriteJson: String, spriteImage: FlutterStandardTypedData,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("iOS: addSprite called - native sprite extraction")

        guard _mapView != nil else {
            print("iOS: Error - MapView not initialized for addSprite")
            completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
            return
        }

        guard let style = _mapView.style else {
            print("iOS: ERROR - Style not available")
            completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
            return
        }

        // Decode the sprite sheet image
        guard let spriteBitmap = UIImage(data: spriteImage.data) else {
            print("iOS: ERROR - Failed to decode sprite sheet image")
            completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode sprite sheet image"])))
            return
        }

        // Parse the sprite JSON
        guard let jsonData = spriteJson.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: [String: Any]] else {
            print("iOS: ERROR - Failed to parse sprite JSON")
            completion(.failure(NSError(domain: "MapLibre", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse sprite JSON"])))
            return
        }

        let startTime = Date()
        var iconCount = 0

        // Get the CGImage from UIImage for cropping
        guard let cgImage = spriteBitmap.cgImage else {
            print("iOS: ERROR - Failed to get CGImage from sprite sheet")
            completion(.failure(NSError(domain: "MapLibre", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to get CGImage"])))
            return
        }

        // Extract each icon from the sprite sheet
        for (name, iconData) in jsonObject {
            guard let x = iconData["x"] as? Int,
                  let y = iconData["y"] as? Int,
                  let width = iconData["width"] as? Int,
                  let height = iconData["height"] as? Int else {
                print("iOS: Skipping icon '\(name)' - missing coordinates")
                continue
            }

            // Create a crop rect
            let cropRect = CGRect(x: x, y: y, width: width, height: height)

            // Crop the icon from the sprite sheet
            if let croppedCGImage = cgImage.cropping(to: cropRect) {
                let iconImage = UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: .up)
                style.setImage(iconImage, forName: name)
                iconCount += 1
            }
        }

        let elapsed = Date().timeIntervalSince(startTime) * 1000
        print("iOS: ✅ Native sprite loading complete - \(iconCount) icons in \(Int(elapsed))ms")
        completion(.success(()))
    }

    func addClusteredGeoJsonSource(
        id: String,
        data: String,
        clustered: Bool,
        clusterRadius: Double,
        clusterMaxZoom: Double,
        clusterPropertiesJson: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("iOS: addClusteredGeoJsonSource called with id: \(id), clustered: \(clustered)")

        // THREAD SAFETY: Execute on main thread with proper error handling
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView deallocated"])))
                return
            }

            do {
                // Guard against nil _mapView before accessing it
                guard self._mapView != nil else {
                    print("iOS: Error - MapView not yet initialized")
                    completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
                    return
                }

                guard let style = self._mapView.style else {
                    print("iOS: Error - Style not available")
                    completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
                    return
                }

                // SAFETY: Check if source already exists and remove it first
                // CRASH FIX: Must remove all dependent layers BEFORE removing source,
                // otherwise MapLibre throws an uncaught ObjC NSInvalidArgumentException
                // that Swift's do/catch cannot handle → SIGABRT.
                if let existingSource = style.source(withIdentifier: id) {
                    print("iOS: Source '\(id)' already exists, removing layers then source")
                    // Collect all dependent layers first (avoid mutation during enumeration)
                    var layersToRemove: [MLNStyleLayer] = []
                    for layer in style.layers {
                        if let vectorLayer = layer as? MLNVectorStyleLayer,
                           vectorLayer.sourceIdentifier == id {
                            layersToRemove.append(layer)
                        }
                    }
                    // Also check known auto-generated cluster layer suffixes
                    for layerSuffix in ["-unclustered", "-clusters", "-cluster-count"] {
                        let layerId = "\(id)\(layerSuffix)"
                        if let layer = style.layer(withIdentifier: layerId),
                           !layersToRemove.contains(where: { $0.identifier == layerId }) {
                            layersToRemove.append(layer)
                        }
                    }
                    // Now remove all collected layers
                    for layer in layersToRemove {
                        style.removeLayer(layer)
                        print("iOS: Removed dependent layer '\(layer.identifier)'")
                    }
                    style.removeSource(existingSource)
                    print("iOS: Removed existing source '\(id)'")
                }

                var options: [MLNShapeSourceOption: Any] = [:]
                if clustered {
                    options[.clustered] = true
                    options[.clusterRadius] = NSNumber(value: clusterRadius)
                    options[.maximumZoomLevelForClustering] = NSNumber(value: clusterMaxZoom)
                    print("iOS: Clustering enabled with radius: \(clusterRadius), maxZoom: \(clusterMaxZoom)")

                    // Apply cluster properties if provided
                    // Uses MapLibre's official NSExpression API:
                    //   - NSExpression.featureAccumulatedVariableExpression for ["accumulated"]
                    //   - NSExpression(format:) with function syntax for reduce expressions
                    // Previous approaches (buildNativeExpression, mglJSONObject) crashed because
                    // MLNGeoJSONOptionsFromDictionary couldn't round-trip the NSExpressions.
                    if let cpJson = clusterPropertiesJson,
                       let cpData = cpJson.data(using: .utf8),
                       let cpDict = try? JSONSerialization.jsonObject(with: cpData) as? [String: [[Any]]] {
                        var clusterProps: [String: [NSExpression]] = [:]
                        for (key, exprs) in cpDict {
                            if exprs.count == 2 {
                                // Build the reduce and map expressions using MapLibre's API
                                if let reduceExpr = self.buildClusterReduceExpression(key: key, reduceJson: exprs[0]),
                                   let mapExpr = self.buildClusterMapExpression(mapJson: exprs[1]) {
                                    clusterProps[key] = [reduceExpr, mapExpr]
                                    print("iOS: ✅ Built cluster property '\(key)' successfully")
                                } else {
                                    print("iOS: ⚠️ Failed to build cluster property '\(key)' — skipping")
                                }
                            }
                        }
                        if !clusterProps.isEmpty {
                            options[.clusterProperties] = clusterProps
                            print("iOS: Applied \(clusterProps.count) cluster properties")
                        }
                    }
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
                          let shape = try? MLNShape(data: dataBytes, encoding: String.Encoding.utf8.rawValue) else {
                        throw NSError(domain: "MapLibre", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON data"])
                    }
                    source = MLNShapeSource(identifier: id, shape: shape, options: options)
                }

                style.addSource(source)
                print("iOS: Successfully added clustered source with ID: \(id)")

                // Add clustering visualization if enabled
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
                    // NOT UIColor.systemOrange. That is a dynamic, trait-dependent
                    // catalog colour; as an NSExpression constant it does not
                    // resolve to an RGBA the renderer can use, so this layer drew
                    // nothing at all while the unclustered layer beside it -- built
                    // from a static hex -- drew fine. #f1f075 is the colour Android
                    // uses for the same auto-created layer.
                    clustersLayer.circleColor = NSExpression(forConstantValue: UIColor(hexString: "#f1f075") ?? UIColor.blue)
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
                    // Without an explicit fontstack the layer inherits a default the
                    // glyph endpoint does not serve (every Open Sans weight 404s),
                    // and a missing fontstack renders no text and raises no error --
                    // so clusters drew as circles with no count inside them.
                    // Noto Sans Medium is verified 200 and is used by the demo
                    // style's own layers, so it cannot be pruned server-side.
                    clusterCountLayer.textFontNames = NSExpression(forConstantValue: ["Noto Sans Medium"])
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
    }

    func addVectorSource(
        id: String,
        tiles: [String],
        minZoom: Double,
        maxZoom: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("✅ iOS: Set VectorSource called with id: \(id), tiles: \(tiles), minZoom: \(minZoom), maxZoom: \(maxZoom)")

        executeOrQueue({ mapView in
            do {
                guard let style = mapView.style else {
                    print("iOS: Error - Style not available")
                    completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
                    return
                }

                // Configure tile source options with min/max zoom
                var options: [MLNTileSourceOption: Any] = [:]
                options[.minimumZoomLevel] = NSNumber(value: minZoom)
                options[.maximumZoomLevel] = NSNumber(value: maxZoom)

                print("iOS: Configuring vector source with options: minZoom=\(minZoom), maxZoom=\(maxZoom)")

                // Create MLNVectorTileSource with tiles array and options
                let source = MLNVectorTileSource(identifier: id, tileURLTemplates: tiles, options: options)

                style.addSource(source)
                print("✅ iOS: Successfully added vector source with ID: \(id) and zoom range \(minZoom)-\(maxZoom)")

                // DEBUG: Verify the source was actually added
                if let addedSource = style.source(withIdentifier: id) {
                    print("✅ iOS: Verified source '\(id)' exists in style (type: \(type(of: addedSource)))")
                    NSLog("🔴 iOS NATIVE: Source verified - type: %@", String(describing: type(of: addedSource)))

                    // Check if it's a vector tile source
                    if let vectorSource = addedSource as? MLNVectorTileSource {
                        print("✅ iOS: Source is MLNVectorTileSource")
                        print("✅ iOS: configurationURL: \(vectorSource.configurationURL?.absoluteString ?? "nil")")
                        NSLog("🔴 iOS NATIVE: Vector source configurationURL: %@", vectorSource.configurationURL?.absoluteString ?? "nil")
                    }
                } else {
                    print("❌ iOS: FAILED to verify source '\(id)' in style!")
                    NSLog("🔴 iOS NATIVE: FAILED to verify source in style!")
                }

                completion(.success(()))
            } catch {
                print("iOS: Error adding vector source: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }, completion: { _ in })
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
        print("🎬 iOS animateCamera CALLED: lat=\(latitude), lng=\(longitude), zoom=\(zoom), bearing=\(bearing), pitch=\(pitch), duration=\(duration)ms")
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                // Map view not yet initialized, skip camera animation
                print("🎬 iOS animateCamera: mapView is nil, skipping")
                completion(.success(()))
                return
            }
            var camera = self._mapView.camera

            // Use sentinel values (-1.0 or NaN) to indicate "no change"
            if !latitude.isNaN && latitude != -1.0 {
                camera.centerCoordinate = CLLocationCoordinate2D(
                    latitude: latitude, longitude: longitude)
            }
            if !bearing.isNaN && bearing != -1.0 {
                camera.heading = bearing
            }
            if !pitch.isNaN && pitch != -1.0 {
                camera.pitch = pitch
            }

            // Use CATransaction to prevent implicit animations that could affect user location display
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if duration == 0 {
                CATransaction.setAnimationDuration(0)
            }

            let animationDuration = Double(duration) / 1000.0
            print("🎬 iOS animateCamera: animationDuration=\(animationDuration)s")
            self._mapView.setCamera(
                camera, withDuration: animationDuration, animationTimingFunction: nil)

            if !zoom.isNaN && zoom != -1.0 {
                self._mapView.setZoomLevel(zoom, animated: duration > 0)
            }

            CATransaction.commit()

            completion(.success(()))
        }
    }

    // Get the current camera state
    func getCamera() throws -> MapCamera {
        guard _mapView != nil else {
            // Map view not yet initialized, return default camera
            return MapCamera(
                center: LngLat(lng: 0.0, lat: 0.0),
                zoom: 0.0,
                pitch: 0.0,
                bearing: 0.0
            )
        }
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
    func getZoomLevel() throws -> Double {
        guard _mapView != nil else {
            // Map view not yet initialized, return default zoom
            return 0.0
        }
        return _mapView.zoomLevel
    }

    // Get the user's current location
    func getUserLocation() throws -> LngLat {
        guard _mapView != nil else {
            // Map view not yet initialized, return default location
            return LngLat(lng: 0.0, lat: 0.0)
        }
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
        print("📍 iOS moveCamera CALLED: lat=\(lat), lng=\(lng), zoom=\(zoom), bearing=\(bearing), pitch=\(pitch) (NO ANIMATION)")
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                // Map view not yet initialized, skip camera move
                print("📍 iOS moveCamera: mapView is nil, skipping")
                completion(.success(()))
                return
            }
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

            // Set camera without animation - use CATransaction to disable ALL implicit animations
            print("📍 iOS moveCamera: setCamera animated=false (with CATransaction disabled)")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)

            self._mapView.setCamera(camera, animated: false)

            // Handle zoom separately if needed
            if !zoom.isNaN && zoom != -1.0 {
                print("📍 iOS moveCamera: setZoomLevel animated=false")
                self._mapView.setZoomLevel(zoom, animated: false)
            }

            CATransaction.commit()
            print("📍 iOS moveCamera: CATransaction committed")

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
            guard self._mapView != nil else {
                // Map view not yet initialized, skip map options update
                completion(.success(()))
                return
            }
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
            guard self._mapView != nil else {
                // Map view not yet initialized, skip enable location
                completion(.success(()))
                return
            }

            // Only enable if not already enabled to prevent duplicate layer errors
            guard !self._mapView.showsUserLocation else {
                print("📍 iOS enableLocation: User location already enabled, skipping")
                completion(.success(()))
                return
            }

            // Wrap in CATransaction to disable implicit animations when showing user location
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)

            self._mapView.showsUserLocation = true
            // Note: iOS MapLibre doesn't have all the detailed location settings like Android
            // The parameters here would need custom implementation if needed

            CATransaction.commit()
            print("📍 iOS enableLocation: showsUserLocation=true with CATransaction")

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
        print("🗺️ iOS fitBounds CALLED: bounds=(\(south),\(west))->(\(north),\(east)), duration=\(duration)ms")
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                // Map view not yet initialized, skip fit bounds
                print("🗺️ iOS fitBounds: mapView is nil, skipping")
                completion(.success(()))
                return
            }
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

            // Use CATransaction to prevent any implicit animations that could affect user location display
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)

            let animated = duration > 0
            print("🗺️ iOS fitBounds: setVisibleCoordinateBounds animated=\(animated)")
            self._mapView.setVisibleCoordinateBounds(
                bounds, edgePadding: edgeInsets, animated: animated)

            CATransaction.commit()

            completion(.success(()))
        }
    }

    // Set persistent viewport content inset. After this call, the camera
    // `center` lat/lng projects to the geometric center of the rectangle
    // defined by (top, left, screenH - bottom, screenW - right) — bearing
    // pivots there too. Used to keep the user puck low on screen during nav
    // while ensuring rotation pivots through the puck.
    func setContentInset(
        left: Double,
        top: Double,
        right: Double,
        bottom: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                completion(.success(()))
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            self._mapView.contentInset = UIEdgeInsets(
                top: CGFloat(top),
                left: CGFloat(left),
                bottom: CGFloat(bottom),
                right: CGFloat(right)
            )
            CATransaction.commit()
            completion(.success(()))
        }
    }

    // Get the meters per pixel at the specified latitude
    func getMetersPerPixelAtLatitude(
        latitude: Double,
        completion: @escaping (Result<Double, Error>) -> Void
    ) {
        guard _mapView != nil else {
            // Map view not yet initialized, return a default value instead of crashing
            completion(.success(1.0))
            return
        }
        let metersPerPixel = _mapView.metersPerPoint(atLatitude: latitude)
        completion(.success(metersPerPixel))
    }

    // Get the visible region bounds
    func getVisibleRegion(
        completion: @escaping (Result<[Double], Error>) -> Void
    ) {
        guard _mapView != nil else {
            // Map view not yet initialized, return empty bounds
            completion(.success([0.0, 0.0, 0.0, 0.0]))
            return
        }
        let bounds = _mapView.visibleCoordinateBounds
        let result = [
            bounds.sw.longitude, bounds.sw.latitude, bounds.ne.longitude, bounds.ne.latitude,
        ]
        completion(.success(result))
    }

    // Convert screen coordinates to longitude/latitude
    func toLngLat(
        x: Double,
        y: Double,
        completion: @escaping (Result<[Double], Error>) -> Void
    ) {
        guard _mapView != nil else {
            // Map view not yet initialized, return default coordinates
            completion(.success([0.0, 0.0]))
            return
        }
        let screenPoint = CGPoint(x: x, y: y)
        let coordinate = _mapView.convert(screenPoint, toCoordinateFrom: _mapView)  // Remove asterisks
        let result = [coordinate.longitude, coordinate.latitude]
        completion(.success(result))
    }

    // Convert longitude/latitude to screen coordinates
    func toScreenLocation(
        lng: Double,
        lat: Double,
        completion: @escaping (Result<[Double], Error>) -> Void
    ) {
        guard _mapView != nil else {
            // Map view not yet initialized, return default screen location
            completion(.success([0.0, 0.0]))
            return
        }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let screenPoint = _mapView.convert(coordinate, toPointTo: _mapView)  // Remove asterisks
        let result = [Double(screenPoint.x), Double(screenPoint.y)]
        completion(.success(result))
    }

    // Query rendered layers at the specified screen location
    func queryLayers(
        x: Double,
        y: Double,
        completion: @escaping (Result<[[String: String]], Error>) -> Void
    ) {
        guard _mapView != nil else {
            // Map view not yet initialized, return empty results
            completion(.success([]))
            return
        }

        let screenPoint = CGPoint(x: x, y: y)
        print("iOS: queryLayers called at screen point: (\(x), \(y))")

        guard let style = _mapView.style else {
            print("iOS: ERROR - Style not available for queryLayers")
            completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
            return
        }

        var result: [[String: String]] = []

        // Get all layers from the style
        let styleLayers = style.layers
        print("iOS: Total layers in style: \(styleLayers.count)")

        // Query each layer individually to get layer metadata
        for layer in styleLayers {
            // Only query layers that might have feature data
            // Include circle, symbol, fill, and line layers
            guard layer is MLNVectorStyleLayer ||
                  layer is MLNSymbolStyleLayer ||
                  layer is MLNCircleStyleLayer ||
                  layer is MLNFillStyleLayer ||
                  layer is MLNLineStyleLayer else {
                continue
            }

            // Query features for this specific layer
            let layerFeatures = _mapView.visibleFeatures(
                at: screenPoint,
                styleLayerIdentifiers: [layer.identifier]
            )

            if !layerFeatures.isEmpty {
                print("iOS: Layer '\(layer.identifier)' has \(layerFeatures.count) features at tap point")
            }

            for feature in layerFeatures {
                var properties: [String: String] = [:]

                // Add layer metadata (matching Android implementation)
                properties["layerId"] = layer.identifier

                // Get source-layer identifier from different layer types
                if let vectorLayer = layer as? MLNVectorStyleLayer {
                    properties["sourceLayer"] = vectorLayer.sourceLayerIdentifier ?? ""
                } else if let symbolLayer = layer as? MLNSymbolStyleLayer {
                    properties["sourceLayer"] = symbolLayer.sourceLayerIdentifier ?? ""
                } else if let circleLayer = layer as? MLNCircleStyleLayer {
                    properties["sourceLayer"] = circleLayer.sourceLayerIdentifier ?? ""
                } else if let fillLayer = layer as? MLNFillStyleLayer {
                    properties["sourceLayer"] = fillLayer.sourceLayerIdentifier ?? ""
                } else if let lineLayer = layer as? MLNLineStyleLayer {
                    properties["sourceLayer"] = lineLayer.sourceLayerIdentifier ?? ""
                } else {
                    properties["sourceLayer"] = ""
                }

                // Note: iOS MapLibre doesn't expose source ID directly from layers
                // Set to empty string to match Android structure
                properties["sourceId"] = ""

                // Extract feature properties from the attributes dictionary
                var attributes: [String: Any]? = nil
                var coordinate: CLLocationCoordinate2D? = nil

                if let pointFeature = feature as? MLNPointFeature {
                    attributes = pointFeature.attributes
                    coordinate = pointFeature.coordinate
                    print("iOS: Found MLNPointFeature with \(pointFeature.attributes.count) attributes at (\(pointFeature.coordinate.latitude), \(pointFeature.coordinate.longitude))")
                } else if let polylineFeature = feature as? MLNPolylineFeature {
                    attributes = polylineFeature.attributes
                    print("iOS: Found MLNPolylineFeature")
                } else if let polygonFeature = feature as? MLNPolygonFeature {
                    attributes = polygonFeature.attributes
                    print("iOS: Found MLNPolygonFeature")
                } else if let shapeCollectionFeature = feature as? MLNShapeCollectionFeature {
                    attributes = shapeCollectionFeature.attributes
                    print("iOS: Found MLNShapeCollectionFeature")
                }

                // Add latitude and longitude if available
                if let coordinate = coordinate {
                    properties["latitude"] = String(coordinate.latitude)
                    properties["longitude"] = String(coordinate.longitude)
                }

                // Add all feature properties
                if let attributes = attributes {
                    print("iOS: Feature attributes: \(attributes)")
                    for (key, value) in attributes {
                        properties[key] = String(describing: value)
                    }
                } else {
                    print("iOS: WARNING - No attributes found for feature")
                }

                result.append(properties)
            }
        }

        print("iOS: queryLayers found \(result.count) total features at (\(x), \(y))")

        // Print all feature properties for debugging
        for (index, feature) in result.enumerated() {
            print("iOS: Feature #\(index): layerId=\(feature["layerId"] ?? "unknown"), sourceLayer=\(feature["sourceLayer"] ?? "unknown"), properties=\(feature)")
        }

        completion(.success(result))
    }

    // Query rendered layers within a bounding box (more efficient for hit detection)
    func queryLayersInRect(
        left: Double,
        top: Double,
        right: Double,
        bottom: Double,
        completion: @escaping (Result<[[AnyHashable?: Any?]], Error>) -> Void
    ) {
        guard _mapView != nil else {
            completion(.success([]))
            return
        }

        let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        print("iOS: queryLayersInRect called with rect: \(rect)")

        guard let style = _mapView.style else {
            print("iOS: ERROR - Style not available for queryLayersInRect")
            completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
            return
        }

        var result: [[AnyHashable?: Any?]] = []

        // Get all layers from the style
        let styleLayers = style.layers

        // Query each layer individually using the bounding box
        for layer in styleLayers {
            guard layer is MLNVectorStyleLayer ||
                  layer is MLNSymbolStyleLayer ||
                  layer is MLNCircleStyleLayer ||
                  layer is MLNFillStyleLayer ||
                  layer is MLNLineStyleLayer else {
                continue
            }

            // Query features within the rect for this specific layer
            let layerFeatures = _mapView.visibleFeatures(
                in: rect,
                styleLayerIdentifiers: [layer.identifier]
            )

            for feature in layerFeatures {
                var properties: [AnyHashable?: Any?] = [:]

                // Add layer metadata
                properties["layerId"] = layer.identifier

                // Get source-layer identifier
                if let vectorLayer = layer as? MLNVectorStyleLayer {
                    properties["sourceLayer"] = vectorLayer.sourceLayerIdentifier ?? ""
                } else if let symbolLayer = layer as? MLNSymbolStyleLayer {
                    properties["sourceLayer"] = symbolLayer.sourceLayerIdentifier ?? ""
                } else if let circleLayer = layer as? MLNCircleStyleLayer {
                    properties["sourceLayer"] = circleLayer.sourceLayerIdentifier ?? ""
                } else if let fillLayer = layer as? MLNFillStyleLayer {
                    properties["sourceLayer"] = fillLayer.sourceLayerIdentifier ?? ""
                } else if let lineLayer = layer as? MLNLineStyleLayer {
                    properties["sourceLayer"] = lineLayer.sourceLayerIdentifier ?? ""
                } else {
                    properties["sourceLayer"] = ""
                }

                properties["sourceId"] = ""

                // Extract feature properties
                var attributes: [String: Any]? = nil
                var coordinate: CLLocationCoordinate2D? = nil

                if let pointFeature = feature as? MLNPointFeature {
                    attributes = pointFeature.attributes
                    coordinate = pointFeature.coordinate
                } else if let polylineFeature = feature as? MLNPolylineFeature {
                    attributes = polylineFeature.attributes
                } else if let polygonFeature = feature as? MLNPolygonFeature {
                    attributes = polygonFeature.attributes
                } else if let shapeCollectionFeature = feature as? MLNShapeCollectionFeature {
                    attributes = shapeCollectionFeature.attributes
                }

                if let coordinate = coordinate {
                    properties["latitude"] = String(coordinate.latitude)
                    properties["longitude"] = String(coordinate.longitude)
                }

                if let attributes = attributes {
                    print("iOS: queryLayersInRect - Feature in layer '\(layer.identifier)' has \(attributes.count) attributes")
                    for (key, value) in attributes {
                        properties[key] = String(describing: value)
                        if key == "name" || key == "name:en" {
                            print("iOS: queryLayersInRect - Found POI name: \(key)=\(value)")
                        }
                    }
                } else {
                    print("iOS: queryLayersInRect - WARNING: No attributes for feature in layer '\(layer.identifier)'")
                }

                result.append(properties)
            }
        }

        print("iOS: queryLayersInRect found \(result.count) total features in rect")
        // Print first few features for debugging
        for (index, feature) in result.prefix(3).enumerated() {
            print("iOS: queryLayersInRect - Feature #\(index): layerId=\(feature["layerId"] ?? "unknown"), name=\(feature["name"] ?? "NO_NAME")")
        }
        completion(.success(result))
    }

    // Enable/disable location tracking with bearing mode
    // NOTE: We avoid setUserTrackingMode entirely because MapLibre's internal
    // C++ engine always does a fly-to arc animation when switching modes,
    // even with animated:false and CATransaction. Instead we just toggle
    // showsUserLocation and let the Dart side handle camera positioning.
    func trackLocation(
        track: Bool,
        bearingMode: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("🔵 iOS trackLocation CALLED: track=\(track), bearingMode=\(bearingMode)")
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                print("🔵 iOS trackLocation: mapView is nil, skipping")
                completion(.success(()))
                return
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)

            if track {
                // Just ensure the location dot is visible — no tracking mode change
                if !self._mapView.showsUserLocation {
                    self._mapView.showsUserLocation = true
                }
                // Always set to .none to prevent MapLibre's internal fly-to
                self._mapView.setUserTrackingMode(.none, animated: false, completionHandler: nil)
                print("🔵 iOS trackLocation: showsUserLocation=true, trackingMode=.none (no fly-to)")
            } else {
                self._mapView.setUserTrackingMode(.none, animated: false, completionHandler: nil)
                print("🔵 iOS trackLocation: trackingMode=.none")
            }

            CATransaction.commit()
            print("🔵 iOS trackLocation: CATransaction committed")

            completion(.success(()))
        }
    }

    // Show/hide the user location puck (blue dot)
    func showUserLocationPuck(
        show: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                // Map view not yet initialized, skip show user location puck
                completion(.success(()))
                return
            }

            // Only change if the state is different to prevent duplicate layer errors
            guard self._mapView.showsUserLocation != show else {
                print("📍 iOS showUserLocationPuck: Already set to \(show), skipping")
                completion(.success(()))
                return
            }

            // Wrap in CATransaction to disable implicit animations when showing/hiding user location
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)

            self._mapView.showsUserLocation = show

            CATransaction.commit()
            print("📍 iOS showUserLocationPuck: set to \(show) with CATransaction")

            completion(.success(()))
        }
    }

    // Add these methods to your MapLibreView class that implements MapLibreHostApi

    func removeLayer(
      id: String,
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      print("iOS: removeLayer called for id: \(id)")

      // Guard against nil _mapView before accessing it
      guard _mapView != nil else {
        print("iOS: Warning - MapView not yet initialized for removeLayer, returning success (layer doesn't exist)")
        completion(.success(()))
        return
      }

      guard let style = _mapView.style else {
        print("iOS: Error - Style not available for removeLayer")
        completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
        return
      }

      if let layer = style.layer(withIdentifier: id) {
        style.removeLayer(layer)
        print("iOS: Successfully removed layer: \(id)")
        completion(.success(()))
      } else {
        print("iOS: Warning - Layer not found: \(id)")
        // Don't fail if layer doesn't exist, just complete successfully
        completion(.success(()))
      }
    }

    func removeSource(
      id: String,
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      print("iOS: removeSource called for id: \(id)")

      // Guard against nil _mapView before accessing it
      guard _mapView != nil else {
        print("iOS: Warning - MapView not yet initialized for removeSource, returning success (source doesn't exist)")
        completion(.success(()))
        return
      }

      guard let style = _mapView.style else {
        print("iOS: Error - Style not available for removeSource")
        completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
        return
      }

      if let source = style.source(withIdentifier: id) {
        // CRASH FIX: Remove all dependent layers BEFORE removing source,
        // otherwise MapLibre throws an uncaught ObjC NSInvalidArgumentException.
        // Collect first to avoid mutation during enumeration.
        var layersToRemove: [MLNStyleLayer] = []
        for layer in style.layers {
            if let vectorLayer = layer as? MLNVectorStyleLayer,
               vectorLayer.sourceIdentifier == id {
                layersToRemove.append(layer)
            }
        }
        for suffix in ["-unclustered", "-clusters", "-cluster-count"] {
            let layerId = "\(id)\(suffix)"
            if let layer = style.layer(withIdentifier: layerId),
               !layersToRemove.contains(where: { $0.identifier == layerId }) {
                layersToRemove.append(layer)
            }
        }
        for layer in layersToRemove {
            style.removeLayer(layer)
            print("iOS: Removed dependent layer '\(layer.identifier)' before source removal")
        }
        style.removeSource(source)
        print("iOS: Successfully removed source: \(id)")
        completion(.success(()))
      } else {
        print("iOS: Warning - Source not found: \(id)")
        // Don't fail if source doesn't exist, just complete successfully
        completion(.success(()))
      }
    }

    func updateGeoJsonSource(
      id: String,
      data: String,
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else {
          completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView deallocated"])))
          return
        }

        guard self._mapView != nil else {
          completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
          return
        }

        guard let style = self._mapView.style else {
          completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
          return
        }

        guard let source = style.source(withIdentifier: id) as? MLNShapeSource else {
          completion(.failure(NSError(domain: "MapLibre", code: 4, userInfo: [NSLocalizedDescriptionKey: "Source not found: \(id)"])))
          return
        }

        if data.hasPrefix("http://") || data.hasPrefix("https://") {
          guard let url = URL(string: data) else {
            completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(data)"])))
            return
          }
          source.url = url
          completion(.success(()))
        } else {
          guard let dataBytes = data.data(using: .utf8),
                let shape = try? MLNShape(data: dataBytes, encoding: String.Encoding.utf8.rawValue) else {
            completion(.failure(NSError(domain: "MapLibre", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON data"])))
            return
          }

          // Simple shape assignment — MapLibre redraws the source automatically.
          source.shape = shape
          completion(.success(()))
        }
      }
    }

    func setStyleUri(
      styleUri: String,
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else {
          completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView deallocated"])))
          return
        }
        guard let url = URL(string: styleUri) else {
          completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid style URI"])))
          return
        }
        self._mapView.styleURL = url
        // didFinishLoading delegate will fire onStyleLoaded
        completion(.success(()))
      }
    }

    // MARK: - Helper Methods for Property Parsing

    private func parseValue(_ value: Any) -> NSExpression {
        if let num = value as? NSNumber {
            return NSExpression(forConstantValue: num)
        }
        if let double = value as? Double {
            return NSExpression(forConstantValue: NSNumber(value: double))
        }
        if let int = value as? Int {
            return NSExpression(forConstantValue: NSNumber(value: int))
        }
        return NSExpression(forConstantValue: NSNumber(value: 0))
    }

    private func parseColor(_ value: Any) -> NSExpression {
        if let colorArray = value as? [Double], colorArray.count >= 3 {
            let a = colorArray.count > 3 ? colorArray[3] : 1.0
            return NSExpression(forConstantValue: UIColor(red: colorArray[0], green: colorArray[1], blue: colorArray[2], alpha: a))
        }
        if let colorString = value as? String {
            return NSExpression(forConstantValue: UIColor(hexString: colorString) ?? UIColor.red)
        }
        return NSExpression(forConstantValue: UIColor.red)
    }
}
