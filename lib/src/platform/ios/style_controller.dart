part of 'map_state.dart';

/// Android specific implementation of the [StyleController].
class StyleControllerIos implements StyleController {
  StyleControllerIos._(this._ffiStyle, this._hostApi);

  final MLNStyle _ffiStyle;
  final pigeon.MapLibreHostApi _hostApi;

  @override
  Future<void> addImage(String id, Uint8List bytes) async {
    // TODO Unhandled Exception: FailedToLoadClassException: Failed to load Objective-C class: NSImage
    // https://developer.apple.com/documentation/foundation/nsitemproviderreading/2919479-objectwithitemproviderdata
    /*_ffiStyle.setImage_forName_(
      NSImage.objectWithItemProviderData_typeIdentifier_error_(
        bytes.toNSData(),
        // The uniform type identifier (UTI) representing the data type of data.
        'public.image'.toNSString(),
        nullptr,
      )!,
      id.toNSString(),
    );*/
    await _hostApi.addImage(id, bytes);
  }

  @override
  Future<void> addLayer(StyleLayer layer, {String? belowLayerId}) async {
    // Check if layer already exists to prevent duplicate layer crash
    final existingLayer = _ffiStyle.layerWithIdentifier_(layer.id.toNSString());
    if (existingLayer != null) {
      debugPrint('⚠️ iOS: Layer "${layer.id}" already exists, skipping addLayer');
      return;
    }

    // iOS FFI FIX: For SymbolStyleLayer, use Pigeon to create layer entirely in Swift
    // This avoids ALL iOS FFI crashes related to parseNSExpression and color properties
    if (layer is SymbolStyleLayer) {
      // Helper function to convert Flutter's #AARRGGBB format to iOS #RRGGBBAA format
      String convertColorFormat(String flutterColor) {
        if (flutterColor.length != 9 || !flutterColor.startsWith('#')) {
          return flutterColor;
        }
        // Flutter format: #AARRGGBB → iOS format: #RRGGBBAA
        final aa = flutterColor.substring(1, 3); // Alpha
        final rrggbb = flutterColor.substring(3); // RGB
        return '#$rrggbb$aa';
      }

      // Convert color formats in paint map
      final paint = Map<String, Object>.from(layer.paint);
      if (paint['icon-color'] is String) {
        paint['icon-color'] = convertColorFormat(paint['icon-color'] as String);
      }
      if (paint['icon-halo-color'] is String) {
        paint['icon-halo-color'] = convertColorFormat(paint['icon-halo-color'] as String);
      }
      if (paint['text-color'] is String) {
        paint['text-color'] = convertColorFormat(paint['text-color'] as String);
      }
      if (paint['text-halo-color'] is String) {
        paint['text-halo-color'] = convertColorFormat(paint['text-halo-color'] as String);
      }

      debugPrint('✅ iOS: Creating SymbolStyleLayer "${layer.id}" via Pigeon');
      await _hostApi.addSymbolLayer(
        id: layer.id,
        sourceId: layer.sourceId,
        layout: layer.layout,
        paint: paint,
        belowLayerId: belowLayerId,
      );
      return;
    }

    // For other layer types, use FFI as before
    MLNStyleLayer? ffiStyleLayer;
    switch (layer) {
      case BackgroundStyleLayer():
        ffiStyleLayer =
            MLNBackgroundStyleLayer.new1()
              ..initWithIdentifier_(layer.id.toNSString())
              ..backgroundColor = NSExpression.expressionWithFormat_(
                layer.color.toHexString(alpha: false).toNSString(),
              );
      case StyleLayerWithSource():
        final ffiSource = _ffiStyle.sourceWithIdentifier_(
          layer.sourceId.toNSString(),
        );
        if (ffiSource == null) {
          throw Exception('Source "${layer.sourceId}" does not exist.');
        }
        switch (layer) {
          case FillStyleLayer():
            ffiStyleLayer =
                MLNFillStyleLayer.new1()..initWithIdentifier_source_(
                  layer.id.toNSString(),
                  ffiSource,
                );
          case CircleStyleLayer():
            ffiStyleLayer =
                MLNCircleStyleLayer.new1()..initWithIdentifier_source_(
                  layer.id.toNSString(),
                  ffiSource,
                );
          case FillExtrusionStyleLayer():
            ffiStyleLayer =
                MLNFillExtrusionStyleLayer.new1()..initWithIdentifier_source_(
                  layer.id.toNSString(),
                  ffiSource,
                );
          case HeatmapStyleLayer():
            ffiStyleLayer =
                MLNHeatmapStyleLayer.new1()..initWithIdentifier_source_(
                  layer.id.toNSString(),
                  ffiSource,
                );
          case HillshadeStyleLayer():
            ffiStyleLayer =
                MLNHillshadeStyleLayer.new1()..initWithIdentifier_source_(
                  layer.id.toNSString(),
                  ffiSource,
                );
          case LineStyleLayer():
            ffiStyleLayer =
                MLNLineStyleLayer.new1()..initWithIdentifier_source_(
                  layer.id.toNSString(),
                  ffiSource,
                );
          case RasterStyleLayer():
            ffiStyleLayer =
                MLNRasterStyleLayer.new1()..initWithIdentifier_source_(
                  layer.id.toNSString(),
                  ffiSource,
                );
          case SymbolStyleLayer():
            // Should not reach here since we handled SymbolStyleLayer above
            throw UnimplementedError('SymbolStyleLayer should be handled via Pigeon');
        }
    }

    if (ffiStyleLayer == null) {
      throw UnimplementedError(
        'The Layer is not supported: ${layer.runtimeType}',
      );
    }

    ffiStyleLayer.setProperties(layer.paint);
    ffiStyleLayer.setProperties(layer.layout);
    if (layer.minZoom case final double minZoom) {
      ffiStyleLayer.minimumZoomLevel = minZoom;
    }
    if (layer.maxZoom case final double maxZoom) {
      ffiStyleLayer.maximumZoomLevel = maxZoom;
    }
    _ffiStyle.addLayer_(ffiStyleLayer);
  }

  @override
  Future<void> addSource(Source source) async {
    // Check if source already exists to prevent duplicate source crash
    final existingSource = _ffiStyle.sourceWithIdentifier_(source.id.toNSString());
    if (existingSource != null) {
      debugPrint('⚠️ iOS: Source "${source.id}" already exists, skipping addSource');
      return;
    }

    final MLNSource ffiSource;
    switch (source) {
      case GeoJsonSource():
        final shapeSource = MLNShapeSource.new1();
        if (source.data.startsWith('{')) {
          shapeSource.initWithIdentifier_shape_options_(
            source.id.toNSString(),
            MLNShape.shapeWithData_encoding_error_(
              source.data.toNSDataUTF8()!,
              nsUTF8StringEncoding,
              nullptr,
            ),
            NSDictionary.new1(),
          );
        } else {
          shapeSource.initWithIdentifier_URL_options_(
            source.id.toNSString(),
            source.data.toNSURL()!,
            NSDictionary.new1(),
          );
        }
        ffiSource = shapeSource;
      case RasterDemSource():
        final demSource = ffiSource = MLNRasterDEMSource.new1();
        if (source.url case final String url) {
          demSource.initWithIdentifier_configurationURL_tileSize_(
            source.id.toNSString(),
            url.toNSURL()!,
            source.tileSize.toDouble(),
          );
        } else {
          final ffiUrls = NSMutableArray.new1();
          for (final url in source.tiles ?? <String>[]) {
            ffiUrls.addObject_(url.toNSString());
          }
          demSource.initWithIdentifier_tileURLTemplates_options_(
            source.id.toNSString(),
            ffiUrls,
            NSDictionary.new1(),
          );
        }
      case RasterSource():
        final rasterSource = ffiSource = MLNRasterTileSource.new1();
        if (source.url case final String url) {
          rasterSource.initWithIdentifier_configurationURL_tileSize_(
            source.id.toNSString(),
            url.toNSURL()!,
            source.tileSize.toDouble(),
          );
        } else {
          final ffiUrls = NSMutableArray.new1()..init();
          for (final url in source.tiles ?? <String>[]) {
            ffiUrls.addObject_(url.toNSString());
          }
          rasterSource.initWithIdentifier_tileURLTemplates_options_(
            source.id.toNSString(),
            ffiUrls,
            NSDictionary.new1(),
          );
        }
      case VectorSource():
        if (source.url case final String url) {
          // For URL-based sources, use the FFI method
          final vectorSource = ffiSource = MLNVectorTileSource.new1();
          vectorSource.initWithIdentifier_configurationURLString_(
            source.id.toNSString(),
            url.toNSString(),
          );
        } else {
          // For tile template sources, use Pigeon method to create source in Swift
          // This bypasses Dart's NSNumber creation limitation
          final minZoom = (source.minZoom ?? 0).toInt();
          final maxZoom = (source.maxZoom ?? 22).toInt();

          debugPrint('✅ iOS: Creating VectorSource via Pigeon - minZoom: $minZoom, maxZoom: $maxZoom');

          await _hostApi.addVectorTileSource(
            sourceId: source.id,
            tileUrls: source.tiles ?? [],
            minZoom: minZoom,
            maxZoom: maxZoom,
          );

          // Source was created and added in Swift, so we're done
          // Return early to skip the _ffiStyle.addSource_ call below
          return;
        }
      case ImageSource():
        final coordinates =
            Struct.create<MLNCoordinateQuad>()
              ..bottomLeft =
                  source.coordinates.bottomLeft.toCLLocationCoordinate2D()
              ..bottomRight =
                  source.coordinates.bottomRight.toCLLocationCoordinate2D()
              ..topLeft = source.coordinates.topLeft.toCLLocationCoordinate2D()
              ..topRight =
                  source.coordinates.topRight.toCLLocationCoordinate2D();
        final imageSource = ffiSource = MLNImageSource.new1();
        imageSource.initWithIdentifier_coordinateQuad_URL_(
          source.id.toNSString(),
          coordinates,
          source.url.toNSURL()!,
        );
      case VideoSource():
        throw UnimplementedError('Video source is only supported on web.');
      default:
        throw UnimplementedError(
          'The Source is not supported: ${source.runtimeType}',
        );
    }
    _ffiStyle.addSource_(ffiSource);
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<List<String>> getAttributions() async => getAttributionsSync();

  @override
  Future<void> removeImage(String id) async {
    final ffiId = id.toNSString();
    _ffiStyle.removeImageForName_(ffiId);
    ffiId.release();
  }

  @override
  Future<void> removeLayer(String id) async {
    final ffiId = id.toNSString();
    final ffiLayer = _ffiStyle.layerWithIdentifier_(ffiId);
    if (ffiLayer == null) return;
    _ffiStyle.removeLayer_(ffiLayer);
    ffiId.release();
  }

  @override
  Future<void> removeSource(String id) async {
    final ffiId = id.toNSString();
    final ffiSource = _ffiStyle.sourceWithIdentifier_(ffiId);
    if (ffiSource == null) return;
    _ffiStyle.removeSource_(ffiSource);
    ffiId.release();
  }

  @override
  Future<void> updateGeoJsonSource({
    required String id,
    required String data,
  }) async {
    final source = _ffiStyle.sourceWithIdentifier_(id.toNSString())!;
    final shapeSource = MLNShapeSource.castFrom(source);
    shapeSource.shape = MLNShape.shapeWithData_encoding_error_(
      data.toNSDataUTF8()!,
      4, // utf-8
      nullptr,
    );
  }

  NSArray _getLayers() => _ffiStyle.layers;

  @override
  void setProjection(MapProjection projection) {
    // no implementation needed, globe is not supported on web.
  }

  @override
  List<String> getAttributionsSync() {
    final attributions = <String>[];
    final sources = _ffiStyle.sources.allObjects;
    for (var i = 0; i < sources.count; i++) {
      final source = sources.objectAtIndex_(i);
      if (!MLNTileSource.isInstance(source)) continue;
      final tileSource = MLNTileSource.castFrom(source);
      final attrInfos = tileSource.attributionInfos;
      for (var j = 0; j < attrInfos.count; j++) {
        final attr = MLNAttributionInfo.castFrom(attrInfos.objectAtIndex_(j));
        attributions.add(
          '<a href="${attr.URL?.absoluteString?.toDartString()}">${attr.title.string.toDartString()}</a>',
        );
      }
    }
    return attributions;
  }
}
