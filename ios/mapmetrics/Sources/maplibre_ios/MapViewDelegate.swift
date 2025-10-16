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
  private var _customMethodChannel: FlutterMethodChannel!

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
    // Create custom MethodChannel for onStyleLoaded workaround
    _customMethodChannel = FlutterMethodChannel(
      name: "dev.flutter.mapmetrics.custom/map_\(viewId)",
      binaryMessenger: binaryMessenger
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
  func mapView(_ mapView: MLNMapView, didFinishLoading _: MLNStyle) {
    // Update _mapView reference first
    _mapView = mapView

    // setCamera() can only be used after the map did finish loading
    var camera = _mapView.camera
    camera.pitch = _mapOptions!.pitch
    _mapView.setCamera(camera, animated: false)

    print("✅ iOS: Map style loaded successfully for viewId \(_viewId)")

    // Use custom MethodChannel to notify Flutter (bypasses broken Pigeon callback)
    // Small delay to ensure Flutter side has registered the MethodChannel handler
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      guard let self = self else {
        print("⚠️ iOS: self is nil in onStyleLoaded async block")
        return
      }
      guard let channel = self._customMethodChannel else {
        print("❌ iOS ERROR: _customMethodChannel is nil for viewId \(self._viewId)")
        return
      }

      // Invoke method with error handling - don't crash if Flutter isn't ready
      channel.invokeMethod("onStyleLoaded", arguments: nil) { error in
        if let error = error {
          print("⚠️ iOS WARNING: Failed to invoke onStyleLoaded (Flutter may not be ready): \(error)")
          // Don't crash - Flutter will pick up the style when it's ready
        } else {
          print("✅ iOS: Sent onStyleLoaded via custom MethodChannel for viewId \(self._viewId)")
        }
      }
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
    _flutterApi.onMoveCamera(camera: pigeonCamera) { _ in }
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
    id: String, sourceId: String, layout: [String: Any],
    paint: [String: Any], belowLayerId: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    print("🔍 iOS: addSymbolLayer called - id: '\(id)', sourceId: '\(sourceId)'")
    print("🔍 iOS: layout keys: \(layout.keys.joined(separator: ", "))")

    guard let style = _mapView?.style else {
      print("❌ iOS ERROR: Style is nil, cannot add symbol layer")
      completion(.failure(NSError(domain: "MapLibre", code: -1, userInfo: [NSLocalizedDescriptionKey: "Style is nil"])))
      return
    }
    print("✅ iOS: Style is valid")

    // Check if layer already exists to prevent duplicate layer crash
    if let existingLayer = style.layer(withIdentifier: id) {
      print("⚠️ iOS: Layer '\(id)' already exists, skipping addSymbolLayer")
      completion(.success(()))
      return
    }

    // Get the source
    guard let source = style.source(withIdentifier: sourceId) else {
      print("❌ iOS ERROR: Source '\(sourceId)' not found for symbol layer '\(id)'")
      completion(.failure(NSError(domain: "MapLibre", code: -2, userInfo: [NSLocalizedDescriptionKey: "Source not found: \(sourceId)"])))
      return
    }
    print("✅ iOS: Source '\(sourceId)' found")

    // Create the symbol layer
    print("🔍 iOS: About to create MLNSymbolStyleLayer...")
    let symbolLayer = MLNSymbolStyleLayer(identifier: id, source: source)
    print("✅ iOS: MLNSymbolStyleLayer created successfully")

    // iOS FFI FIX: Set ALL properties safely in Swift to avoid Dart FFI crashes
    // Parse hex colors from #RRGGBBAA format
    func parseColor(_ hexString: String) -> UIColor? {
      var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
      hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

      guard hexSanitized.count == 8 || hexSanitized.count == 6 else {
        print("⚠️ iOS WARNING: Invalid hex color '\(hexString)'")
        return nil
      }

      // Handle 6-char hex (no alpha) by adding FF
      let fullHex = hexSanitized.count == 6 ? hexSanitized + "FF" : hexSanitized

      var rgb: UInt64 = 0
      Scanner(string: fullHex).scanHexInt64(&rgb)

      let r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
      let g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
      let b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
      let a = CGFloat(rgb & 0x000000FF) / 255.0

      return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    // Set layout properties - ALL properties from MarkerLayer

    // Icon properties
    if let iconImage = layout["icon-image"] as? String {
      print("🔍 iOS: Setting icon-image to '\(iconImage)'")
      symbolLayer.iconImageName = NSExpression(forConstantValue: iconImage)
      print("✅ iOS: icon-image set successfully")
    }
    if let iconAllowOverlap = layout["icon-allow-overlap"] as? Bool {
      symbolLayer.iconAllowsOverlap = NSExpression(forConstantValue: iconAllowOverlap)
    }
    if let iconIgnorePlacement = layout["icon-ignore-placement"] as? Bool {
      symbolLayer.iconIgnoresPlacement = NSExpression(forConstantValue: iconIgnorePlacement)
    }
    if let iconOptional = layout["icon-optional"] as? Bool {
      symbolLayer.iconOptional = NSExpression(forConstantValue: iconOptional)
    }
    if let iconSize = layout["icon-size"] as? Double {
      symbolLayer.iconScale = NSExpression(forConstantValue: iconSize)
    }
    if let iconRotate = layout["icon-rotate"] as? Double {
      symbolLayer.iconRotation = NSExpression(forConstantValue: iconRotate)
    }
    if let iconPadding = layout["icon-padding"] as? Double {
      symbolLayer.iconPadding = NSExpression(forConstantValue: iconPadding)
    }
    if let iconKeepUpright = layout["icon-keep-upright"] as? Bool {
      symbolLayer.keepsIconUpright = NSExpression(forConstantValue: iconKeepUpright)
    }
    if let iconOffset = layout["icon-offset"] as? [Double] {
      symbolLayer.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: iconOffset[0], dy: iconOffset[1])))
    }
    if let iconAnchor = layout["icon-anchor"] as? String {
      // Convert string to MLNIconAnchor enum
      let anchor: MLNIconAnchor
      switch iconAnchor {
      case "center": anchor = .center
      case "left": anchor = .left
      case "right": anchor = .right
      case "top": anchor = .top
      case "bottom": anchor = .bottom
      case "top-left": anchor = .topLeft
      case "top-right": anchor = .topRight
      case "bottom-left": anchor = .bottomLeft
      case "bottom-right": anchor = .bottomRight
      default: anchor = .center
      }
      symbolLayer.iconAnchor = NSExpression(forConstantValue: NSNumber(value: anchor.rawValue))
    }

    // Text properties
    if let textField = layout["text-field"] as? String {
      symbolLayer.text = NSExpression(forConstantValue: textField)
    }
    if let textFont = layout["text-font"] as? [String] {
      symbolLayer.textFontNames = NSExpression(forConstantValue: textFont)
    }
    if let textSize = layout["text-size"] as? Double {
      symbolLayer.textFontSize = NSExpression(forConstantValue: textSize)
    }
    if let textMaxWidth = layout["text-max-width"] as? Double {
      symbolLayer.maximumTextWidth = NSExpression(forConstantValue: textMaxWidth)
    }
    if let textLineHeight = layout["text-line-height"] as? Double {
      symbolLayer.textLineHeight = NSExpression(forConstantValue: textLineHeight)
    }
    if let textLetterSpacing = layout["text-letter-spacing"] as? Double {
      symbolLayer.textLetterSpacing = NSExpression(forConstantValue: textLetterSpacing)
    }
    if let textRadialOffset = layout["text-radial-offset"] as? Double {
      symbolLayer.textRadialOffset = NSExpression(forConstantValue: textRadialOffset)
    }
    if let textMaxAngle = layout["text-max-angle"] as? Double {
      symbolLayer.maximumTextAngle = NSExpression(forConstantValue: textMaxAngle)
    }
    if let textRotate = layout["text-rotate"] as? Double {
      symbolLayer.textRotation = NSExpression(forConstantValue: textRotate)
    }
    if let textPadding = layout["text-padding"] as? Double {
      symbolLayer.textPadding = NSExpression(forConstantValue: textPadding)
    }
    if let textKeepUpright = layout["text-keep-upright"] as? Bool {
      symbolLayer.keepsTextUpright = NSExpression(forConstantValue: textKeepUpright)
    }
    if let textOffset = layout["text-offset"] as? [Double] {
      symbolLayer.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: textOffset[0], dy: textOffset[1])))
    }
    if let textAllowOverlap = layout["text-allow-overlap"] as? Bool {
      symbolLayer.textAllowsOverlap = NSExpression(forConstantValue: textAllowOverlap)
    }
    if let textIgnorePlacement = layout["text-ignore-placement"] as? Bool {
      symbolLayer.textIgnoresPlacement = NSExpression(forConstantValue: textIgnorePlacement)
    }
    if let textOptional = layout["text-optional"] as? Bool {
      symbolLayer.textOptional = NSExpression(forConstantValue: textOptional)
    }

    // Set paint properties - SAFE because we're in Swift creating UIColor objects directly
    if let iconOpacity = paint["icon-opacity"] as? Double {
      symbolLayer.iconOpacity = NSExpression(forConstantValue: iconOpacity)
    }
    if let iconColor = paint["icon-color"] as? String, let color = parseColor(iconColor) {
      symbolLayer.iconColor = NSExpression(forConstantValue: color)
    }
    if let iconHaloColor = paint["icon-halo-color"] as? String, let color = parseColor(iconHaloColor) {
      symbolLayer.iconHaloColor = NSExpression(forConstantValue: color)
    }
    if let iconHaloWidth = paint["icon-halo-width"] as? Double {
      symbolLayer.iconHaloWidth = NSExpression(forConstantValue: iconHaloWidth)
    }
    if let iconHaloBlur = paint["icon-halo-blur"] as? Double {
      symbolLayer.iconHaloBlur = NSExpression(forConstantValue: iconHaloBlur)
    }
    if let textOpacity = paint["text-opacity"] as? Double {
      symbolLayer.textOpacity = NSExpression(forConstantValue: textOpacity)
    }
    if let textColor = paint["text-color"] as? String, let color = parseColor(textColor) {
      symbolLayer.textColor = NSExpression(forConstantValue: color)
    }
    if let textHaloColor = paint["text-halo-color"] as? String, let color = parseColor(textHaloColor) {
      symbolLayer.textHaloColor = NSExpression(forConstantValue: color)
    }
    if let textHaloWidth = paint["text-halo-width"] as? Double {
      symbolLayer.textHaloWidth = NSExpression(forConstantValue: textHaloWidth)
    }
    if let textHaloBlur = paint["text-halo-blur"] as? Double {
      symbolLayer.textHaloBlur = NSExpression(forConstantValue: textHaloBlur)
    }
    if let textTranslate = paint["text-translate"] as? [Double] {
      symbolLayer.textTranslation = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: textTranslate[0], dy: textTranslate[1])))
    }

    // Add the layer to the style
    if let belowId = belowLayerId, let belowLayer = style.layer(withIdentifier: belowId) {
      style.insertLayer(symbolLayer, below: belowLayer)
      print("✅ iOS: Added SymbolLayer '\(id)' below '\(belowId)' via Pigeon with all properties")
    } else {
      style.addLayer(symbolLayer)
      print("✅ iOS: Added SymbolLayer '\(id)' on top via Pigeon with all properties")
    }

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
    print("🟢 SWIFT: addImage called for \(id) with \(bytes.data.count) bytes")

    // CRITICAL: UI operations must run on main thread
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        print("❌ SWIFT ERROR: self is nil")
        completion(.failure(NSError(domain: "MapLibre", code: -3, userInfo: [NSLocalizedDescriptionKey: "View deallocated"])))
        return
      }

      print("🟡 SWIFT: On main thread, checking mapView for \(id)")

      // CRITICAL: Validate _mapView exists and is not deallocated
      guard let mapView = self._mapView else {
        print("❌ SWIFT ERROR: _mapView is nil for image \(id)")
        completion(.failure(NSError(domain: "MapLibre", code: -4, userInfo: [NSLocalizedDescriptionKey: "MapView is nil"])))
        return
      }

      print("🟡 SWIFT: MapView exists, checking style for \(id)")

      // CRITICAL: Validate style exists and is the current active style
      guard let style = mapView.style else {
        print("❌ SWIFT ERROR: Style is nil for image \(id)")
        completion(.failure(NSError(domain: "MapLibre", code: -1, userInfo: [NSLocalizedDescriptionKey: "Style is nil"])))
        return
      }

      let imageData = bytes.data
      print("🟡 SWIFT: Creating UIImage for \(id) from \(imageData.count) bytes")

      guard let image = UIImage(data: imageData, scale: UIScreen.main.scale) else {
        print("❌ SWIFT ERROR: Failed to create UIImage for \(id), data length: \(imageData.count)")
        completion(.failure(NSError(domain: "MapLibre", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create UIImage"])))
        return
      }

      print("🟡 SWIFT: Setting image in style for \(id)")
      style.setImage(image, forName: id)
      print("✅ SWIFT SUCCESS: Added image \(id) to MapLibre style")
      completion(.success(()))
    }
  }

  func addVectorTileSource(
    sourceId: String, tileUrls: [String], minZoom: Int64, maxZoom: Int64,
    completion: @escaping (Result<Int64, Error>) -> Void
  ) {
    guard let style = _mapView?.style else {
      print("❌ iOS ERROR: Style is nil, cannot add vector tile source")
      completion(.failure(NSError(domain: "MapLibre", code: -1, userInfo: [NSLocalizedDescriptionKey: "Style is nil"])))
      return
    }

    // Create options dictionary with zoom levels using native Swift NSNumber
    let options: [MLNTileSourceOption: Any] = [
      .minimumZoomLevel: NSNumber(value: minZoom),
      .maximumZoomLevel: NSNumber(value: maxZoom)
    ]

    // Create the vector tile source with options
    let vectorSource = MLNVectorTileSource(
      identifier: sourceId,
      tileURLTemplates: tileUrls,
      options: options
    )

    // Add source to the map style
    style.addSource(vectorSource)

    print("✅ iOS: Added VectorTileSource '\(sourceId)' with minZoom: \(minZoom), maxZoom: \(maxZoom)")

    // Return the pointer address as Int64
    let pointerAddress = Int64(bitPattern: UInt64(UInt(bitPattern: Unmanaged.passUnretained(vectorSource).toOpaque())))
    completion(.success(pointerAddress))
  }

  func setSymbolLayerColors(
    layerId: String,
    iconColor: String?,
    iconHaloColor: String?,
    textColor: String?,
    textHaloColor: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let style = _mapView?.style else {
      print("❌ iOS ERROR: Style is nil, cannot set symbol layer colors")
      completion(.failure(NSError(domain: "MapLibre", code: -1, userInfo: [NSLocalizedDescriptionKey: "Style is nil"])))
      return
    }

    guard let layer = style.layer(withIdentifier: layerId) as? MLNSymbolStyleLayer else {
      print("❌ iOS ERROR: Layer '\(layerId)' not found or not a symbol layer")
      completion(.failure(NSError(domain: "MapLibre", code: -2, userInfo: [NSLocalizedDescriptionKey: "Layer not found or not a symbol layer"])))
      return
    }

    // Helper function to parse hex color string (#RRGGBBAA format) to UIColor
    func parseColor(_ hexString: String) -> UIColor? {
      var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
      hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

      // Require 8-character hex with alpha channel
      guard hexSanitized.count == 8 else {
        print("⚠️ iOS WARNING: Invalid hex color format '\(hexString)', expected #RRGGBBAA")
        return nil
      }

      var rgb: UInt64 = 0
      Scanner(string: hexSanitized).scanHexInt64(&rgb)

      let r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
      let g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
      let b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
      let a = CGFloat(rgb & 0x000000FF) / 255.0

      return UIColor(red: r, green: g, blue: b, alpha: a)
    }

    // Set each color property if provided
    if let iconColorHex = iconColor, let color = parseColor(iconColorHex) {
      layer.iconColor = NSExpression(forConstantValue: color)
      print("✅ iOS: Set icon-color for layer '\(layerId)'")
    }

    if let iconHaloColorHex = iconHaloColor, let color = parseColor(iconHaloColorHex) {
      layer.iconHaloColor = NSExpression(forConstantValue: color)
      print("✅ iOS: Set icon-halo-color for layer '\(layerId)'")
    }

    if let textColorHex = textColor, let color = parseColor(textColorHex) {
      layer.textColor = NSExpression(forConstantValue: color)
      print("✅ iOS: Set text-color for layer '\(layerId)'")
    }

    if let textHaloColorHex = textHaloColor, let color = parseColor(textHaloColorHex) {
      layer.textHaloColor = NSExpression(forConstantValue: color)
      print("✅ iOS: Set text-halo-color for layer '\(layerId)'")
    }

    print("✅ iOS: Successfully set colors for symbol layer '\(layerId)'")
    completion(.success(()))
  }
}
