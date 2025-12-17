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
        _mapView.removeFromSuperview()
        _mapView.delegate = nil
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
        // Apply paint properties
        paint.forEach { key, value in
            switch key {
            case "fill-color": layer.fillColor = parseColor(value)
            case "fill-opacity": layer.fillOpacity = parseValue(value)
            case "fill-outline-color": layer.fillOutlineColor = parseColor(value)
            case "fill-pattern": layer.fillPattern = NSExpression(forConstantValue: value)
            default: break
            }
        }

        // Apply layout properties
        layout.forEach { key, value in
            switch key {
            case "visibility": layer.isVisible = (value as? String == "visible")
            case "fill-sort-key": layer.fillSortKey = parseValue(value)
            default: break
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

        // Check if this is a clustered source by looking for existing cluster layers
        let hasClusterLayers = style.layer(withIdentifier: "\(sourceId)-clusters") != nil ||
                              style.layer(withIdentifier: "\(sourceId)-unclustered") != nil

        if hasClusterLayers {
            print("iOS: Skipping addCircleLayer for clustered source: \(sourceId) - cluster visualization already exists")
            completion(.success(()))
            return
        }

        print("iOS: Adding circle layer for non-clustered source: \(sourceId)")
        let layer = MLNCircleStyleLayer(identifier: id, source: source)

        // Handle source-layer property for vector tile sources
        if let sourceLayer = layout["source-layer"] as? String {
            layer.sourceLayerIdentifier = sourceLayer
            print("iOS: Set source-layer to: \(sourceLayer)")
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

        completion(.success(()))
    }

    private func applyCircleProperties(to layer: MLNCircleStyleLayer, paint: [String: Any], layout: [String: Any]) {

        // Apply paint properties with proper mapping
        paint.forEach { key, value in
            print("iOS: Setting paint property \(key) = \(value)")

            switch key {
            case "circle-radius":
                layer.circleRadius = createExpression(from: value)
            case "circle-color":
                layer.circleColor = createExpression(from: value)
            case "circle-opacity":
                layer.circleOpacity = createExpression(from: value)
            case "circle-stroke-width":
                layer.circleStrokeWidth = createExpression(from: value)
            case "circle-stroke-color":
                layer.circleStrokeColor = createExpression(from: value)
            case "circle-stroke-opacity":
                layer.circleStrokeOpacity = createExpression(from: value)
            case "circle-blur":
                layer.circleBlur = createExpression(from: value)
            default:
                print("iOS: Unknown circle paint property: \(key)")
            }
        }

        // Apply layout properties
        layout.forEach { key, value in
            print("iOS: Setting layout property \(key) = \(value)")

            switch key {
            case "visibility":
                layer.isVisible = (value as? String == "visible")
            case "circle-sort-key":
                layer.circleSortKey = createExpression(from: value)
            default:
                print("iOS: Unknown circle layout property: \(key)")
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

                // SECOND: Try MapMetrics's mglJSONObject converter for simpler expressions
                print("iOS: Native builder didn't handle this, trying mglJSONObject...")
                do {
                    return try NSExpression(mglJSONObject: arrayValue)
                } catch let error {
                    print("iOS: ⚠️ mglJSONObject also failed: \(error)")
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

    // Build NSPredicate from expression array (for use in conditionals)
    private func buildPredicate(from expression: [Any]) -> NSPredicate? {
        guard !expression.isEmpty, let op = expression.first as? String else {
            return nil
        }

        switch op {
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
                } else {
                    resultExpr = NSExpression(forConstantValue: expression.last!)
                }

                // Work backwards through condition/value pairs
                var i = expression.count - 2  // Start before fallback
                while i >= 2 {  // Pairs are at indices 1-2, 3-4, etc.
                    let outputValue = expression[i]
                    let conditionValue = expression[i - 1]

                    // Build output expression
                    let outputExpr: NSExpression
                    if let outputArray = outputValue as? [Any], let built = buildNativeExpression(outputArray) {
                        outputExpr = built
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
            // In iOS, we can simulate this with nested conditionals
            if expression.count >= 2 {
                var resultExpr: NSExpression
                if let lastArray = expression.last as? [Any], let built = buildNativeExpression(lastArray) {
                    resultExpr = built
                } else {
                    resultExpr = NSExpression(forConstantValue: expression.last!)
                }

                for i in stride(from: expression.count - 2, through: 1, by: -1) {
                    let value = expression[i]
                    let valueExpr: NSExpression
                    if let valueArray = value as? [Any], let built = buildNativeExpression(valueArray) {
                        valueExpr = built
                    } else {
                        valueExpr = NSExpression(forConstantValue: value)
                    }

                    // Check if value is not nil
                    let notNilCheck = NSComparisonPredicate(
                        leftExpression: valueExpr,
                        rightExpression: NSExpression(forConstantValue: nil),
                        modifier: .direct,
                        type: .notEqualTo
                    )

                    resultExpr = NSExpression(
                        forConditional: notNilCheck,
                        trueExpression: valueExpr,
                        falseExpression: resultExpr
                    )
                }

                return resultExpr
            }

        default:
            print("iOS: Unsupported native expression operator: \(op)")
            return nil
        }

        return nil
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
        // Apply paint properties
        paint.forEach { key, value in
            switch key {
            case "background-color": layer.backgroundColor = parseColor(value)
            case "background-opacity": layer.backgroundOpacity = parseValue(value)
            case "background-pattern": layer.backgroundPattern = NSExpression(forConstantValue: value)
            default: break
            }
        }

        // Apply layout properties
        layout.forEach { key, value in
            switch key {
            case "visibility": layer.isVisible = (value as? String == "visible")
            default: break
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
          if let colorArray = value as? [Any], colorArray.count >= 3 {
            // Handle RGBA array format [r, g, b, a]
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

        // Apply paint properties
        paint.forEach { key, value in
            print("iOS: Setting symbol paint property \(key) = \(value)")

            switch key {
            case "icon-opacity":
                layer.iconOpacity = createExpression(from: value)
            case "icon-color":
                layer.iconColor = createExpression(from: value)
            case "icon-halo-color":
                layer.iconHaloColor = createExpression(from: value)
            case "icon-halo-width":
                layer.iconHaloWidth = createExpression(from: value)
            case "text-opacity":
                layer.textOpacity = createExpression(from: value)
            case "text-color":
                layer.textColor = createExpression(from: value)
            case "text-halo-color":
                layer.textHaloColor = createExpression(from: value)
            case "text-halo-width":
                layer.textHaloWidth = createExpression(from: value)
            default:
                print("iOS: Unknown symbol paint property: \(key)")
            }
        }

        // Apply layout properties with proper mapping
        layout.forEach { key, value in
            // Skip source-layer as it's handled separately
            if key == "source-layer" {
                return
            }

            print("iOS: Setting symbol layout property \(key) = \(value)")

            switch key {
            case "visibility":
                layer.isVisible = (value as? String == "visible")
            case "icon-image":
                layer.iconImageName = createExpression(from: value)
                print("iOS: Set icon-image to \(value)")
            case "icon-size":
                layer.iconScale = createExpression(from: value)
                print("iOS: Set icon-size/scale")
            case "icon-allow-overlap":
                if let boolValue = value as? Bool {
                    layer.iconAllowsOverlap = NSExpression(forConstantValue: boolValue)
                    print("iOS: Set icon-allow-overlap to \(boolValue)")
                }
            case "icon-ignore-placement":
                if let boolValue = value as? Bool {
                    layer.iconIgnoresPlacement = NSExpression(forConstantValue: boolValue)
                    print("iOS: Set icon-ignore-placement to \(boolValue)")
                }
            case "icon-anchor":
                layer.iconAnchor = createExpression(from: value)
            case "icon-offset":
                layer.iconOffset = createExpression(from: value)
            case "icon-rotation":
                layer.iconRotation = createExpression(from: value)
            case "text-field":
                layer.text = createExpression(from: value)
            case "text-size":
                layer.textFontSize = createExpression(from: value)
            case "text-font":
                layer.textFontNames = createExpression(from: value)
            case "text-anchor":
                layer.textAnchor = createExpression(from: value)
            case "text-offset":
                layer.textOffset = createExpression(from: value)
            default:
                print("iOS: Unknown symbol layout property: \(key)")
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

        executeOrQueue({ mapView in
            guard let style = mapView.style else {
                completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
                return
            }

            let imageData = bytes.data

            // IMPORTANT: Use scale 1.0 for MapLibre icons, not UIScreen.main.scale
            // MapLibre expects images at 1x resolution and will handle scaling internally
            guard let image = UIImage(data: imageData, scale: 1.0) else {
                print("iOS: ERROR - Failed to decode UIImage from data")
                completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode image"])))
                return
            }

            print("iOS: Image decoded successfully - size: \(image.size.width) x \(image.size.height), scale: \(image.scale)")
            style.setImage(image, forName: id)

            // Verify the image was added
            if let verifyImage = style.image(forName: id) {
                print("iOS: ✅ Image '\(id)' added to style successfully - verified size: \(verifyImage.size.width) x \(verifyImage.size.height)")
            } else {
                print("iOS: ⚠️ WARNING - Image '\(id)' was set but cannot be retrieved from style")
            }

            completion(.success(()))
        }, completion: { _ in })
    }

    func addImages(
        ids: [String], images: [FlutterStandardTypedData],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("iOS: addImages called with \(ids.count) images")

        guard _mapView != nil else {
            print("iOS: Error - MapView not initialized for addImages")
            completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
            return
        }

        guard let style = _mapView.style else {
            print("iOS: ERROR - Style not available")
            completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
            return
        }

        guard ids.count == images.count else {
            print("iOS: ERROR - ids and images count mismatch")
            completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "ids and images count mismatch"])))
            return
        }

        var successCount = 0
        var failCount = 0

        for (index, id) in ids.enumerated() {
            let imageData = images[index].data
            if let image = UIImage(data: imageData, scale: 1.0) {
                style.setImage(image, forName: id)
                successCount += 1
            } else {
                print("iOS: Failed to decode image for id: \(id)")
                failCount += 1
            }
        }

        print("iOS: addImages complete - success: \(successCount), failed: \(failCount)")
        completion(.success(()))
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
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            print("iOS: addClusteredGeoJsonSource called with id: \(id), clustered: \(clustered)")

            // Guard against nil _mapView before accessing it
            guard _mapView != nil else {
                print("iOS: Error - MapView not yet initialized")
                completion(.failure(NSError(domain: "MapLibre", code: 0, userInfo: [NSLocalizedDescriptionKey: "MapView not initialized"])))
                return
            }

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
                      let shape = try? MLNShape(data: dataBytes, encoding: String.Encoding.utf8.rawValue) else {
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
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                // Map view not yet initialized, skip camera animation
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

            // Set camera with animation
            let animationDuration = duration > 0 ? Double(duration) / 1000.0 : 0.2
            self._mapView.setCamera(
                camera, withDuration: animationDuration, animationTimingFunction: nil)

            // Handle zoom separately if needed
            if !zoom.isNaN && zoom != -1.0 {
                self._mapView.setZoomLevel(zoom, animated: true)
            }

            completion(.success(()))
        }
    }

    // Get the current camera state
    func getCamera() -> MapCamera {
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
    func getZoomLevel() -> Double {
        guard _mapView != nil else {
            // Map view not yet initialized, return default zoom
            return 0.0
        }
        return _mapView.zoomLevel
    }

    // Get the user's current location
    func getUserLocation() -> LngLat {
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
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                // Map view not yet initialized, skip camera move
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
            guard self._mapView != nil else {
                // Map view not yet initialized, skip fit bounds
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

            let animated = duration > 0
            self._mapView.setVisibleCoordinateBounds(
                bounds, edgePadding: edgeInsets, animated: animated)

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

    // Enable/disable location tracking with bearing mode
    func trackLocation(
        track: Bool,
        bearingMode: Int64,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            guard self._mapView != nil else {
                // Map view not yet initialized, skip track location
                completion(.success(()))
                return
            }
            if track {
                // Convert bearingMode to appropriate iOS tracking mode
                switch bearingMode {
                case 0:  // none
                    self._mapView.userTrackingMode = .follow
                case 1:  // compass
                    self._mapView.userTrackingMode = .followWithHeading
                case 2:  // gps
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
            self._mapView.showsUserLocation = show
            print("iOS: showUserLocationPuck set to \(show)")
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
      print("iOS: updateGeoJsonSource called for id: \(id)")

      executeOrQueue({ mapView in
        guard let style = mapView.style else {
          completion(.failure(NSError(domain: "MapLibre", code: 1, userInfo: [NSLocalizedDescriptionKey: "Style not available"])))
          return
        }

        guard let source = style.source(withIdentifier: id) as? MLNShapeSource else {
          print("iOS: Error - Source not found or not a GeoJSON source: \(id)")
          completion(.failure(NSError(domain: "MapLibre", code: 4, userInfo: [NSLocalizedDescriptionKey: "Source not found: \(id)"])))
          return
        }

        // Parse the GeoJSON data
        if data.hasPrefix("http://") || data.hasPrefix("https://") {
          // Handle URL source
          guard let url = URL(string: data) else {
            print("iOS: Error - Invalid URL: \(data)")
            completion(.failure(NSError(domain: "MapLibre", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(data)"])))
            return
          }
          source.url = url
          print("iOS: Updated source with URL: \(data)")
        } else {
          // Handle GeoJSON data
          guard let dataBytes = data.data(using: .utf8),
                let shape = try? MLNShape(data: dataBytes, encoding: String.Encoding.utf8.rawValue) else {
            print("iOS: Error - Invalid GeoJSON data")
            completion(.failure(NSError(domain: "MapLibre", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON data"])))
            return
          }
          source.shape = shape
          print("iOS: Updated source with GeoJSON data (\(data.count) characters)")
        }

        completion(.success(()))
      }, completion: { _ in })
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