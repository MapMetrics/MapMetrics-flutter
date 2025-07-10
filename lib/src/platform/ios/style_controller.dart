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
    MLNStyleLayer? ffiStyleLayer;
    switch (layer) {
      case BackgroundStyleLayer():
        ffiStyleLayer = MLNBackgroundStyleLayer.alloc()
            .initWithIdentifier_(layer.id.toNSString());
        (ffiStyleLayer as MLNBackgroundStyleLayer).backgroundColor =
            NSExpression.expressionWithFormat_(
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
            ffiStyleLayer = MLNFillStyleLayer.alloc()
                .initWithIdentifier_source_(
              layer.id.toNSString(),
              ffiSource,
            );
          case CircleStyleLayer():
            ffiStyleLayer = MLNCircleStyleLayer.alloc()
                .initWithIdentifier_source_(
              layer.id.toNSString(),
              ffiSource,
            );
          case FillExtrusionStyleLayer():
            ffiStyleLayer = MLNFillExtrusionStyleLayer.alloc()
                .initWithIdentifier_source_(
              layer.id.toNSString(),
              ffiSource,
            );
          case HeatmapStyleLayer():
            ffiStyleLayer = MLNHeatmapStyleLayer.alloc()
                .initWithIdentifier_source_(
              layer.id.toNSString(),
              ffiSource,
            );
          case HillshadeStyleLayer():
            ffiStyleLayer = MLNHillshadeStyleLayer.alloc()
                .initWithIdentifier_source_(
              layer.id.toNSString(),
              ffiSource,
            );
          case LineStyleLayer():
            ffiStyleLayer = MLNLineStyleLayer.alloc()
                .initWithIdentifier_source_(
              layer.id.toNSString(),
              ffiSource,
            );
          case RasterStyleLayer():
            ffiStyleLayer = MLNRasterStyleLayer.alloc()
                .initWithIdentifier_source_(
              layer.id.toNSString(),
              ffiSource,
            );
          case SymbolStyleLayer():
            ffiStyleLayer = MLNSymbolStyleLayer.alloc()
                .initWithIdentifier_source_(
              layer.id.toNSString(),
              ffiSource,
            );
        }
    }
    if (ffiStyleLayer == null) {
      throw UnimplementedError(
        'The Layer is not supported: ${layer.runtimeType}',
      );
    }

    // Set properties AFTER the layer is properly initialized
    try {
      ffiStyleLayer.setProperties(layer.paint);
      ffiStyleLayer.setProperties(layer.layout);
    } catch (e) {
      debugPrint('Error setting layer properties: $e');
      // Continue anyway - the layer might still work
    }

    if (layer.minZoom case final double minZoom) {
      ffiStyleLayer.minimumZoomLevel = minZoom;
    }
    if (layer.maxZoom case final double maxZoom) {
      ffiStyleLayer.maximumZoomLevel = maxZoom;
    }

    // Add the layer to the style
    _ffiStyle.addLayer_(ffiStyleLayer);
  }

  @override
  Future<void> addSource(Source source) async {
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
        final vectorSource = ffiSource = MLNVectorTileSource.new1();
        if (source.url case final String url) {
          vectorSource.initWithIdentifier_configurationURLString_(
            source.id.toNSString(),
            url.toNSString(),
          );
        } else {
          final ffiUrls = NSMutableArray.new1()..init();
          for (final url in source.tiles ?? <String>[]) {
            ffiUrls.addObject_(url.toNSString());
          }
          vectorSource.initWithIdentifier_tileURLTemplates_options_(
            source.id.toNSString(),
            ffiUrls,
            NSDictionary.new1(),
          );
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
    try {
      final ffiId = id.toNSString();
      final ffiLayer = _ffiStyle.layerWithIdentifier_(ffiId);
      if (ffiLayer != null) {
        _ffiStyle.removeLayer_(ffiLayer);
      }
      // Don't release ffiId here - let ARC handle it
    } catch (e) {
      debugPrint('Error removing layer $id: $e');
    }
  }

  @override
  Future<void> removeSource(String id) async {
    try {
      final ffiId = id.toNSString();
      final ffiSource = _ffiStyle.sourceWithIdentifier_(ffiId);
      if (ffiSource != null) {
        _ffiStyle.removeSource_(ffiSource);
      }
      // Don't release ffiId here - let ARC handle it
    } catch (e) {
      debugPrint('Error removing source $id: $e');
    }
  }

  @override
  Future<void> updateGeoJsonSource({
    required String id,
    required String data,
  }) async {
    try {
      final sourceId = id.toNSString();
      final source = _ffiStyle.sourceWithIdentifier_(sourceId);
      if (source == null) {
        debugPrint('Source $id not found for update');
        return;
      }

      final shapeSource = MLNShapeSource.castFrom(source);
      final newShape = MLNShape.shapeWithData_encoding_error_(
        data.toNSDataUTF8()!,
        4, // utf-8
        nullptr,
      );

      if (newShape != null) {
        shapeSource.shape = newShape;
      }
    } catch (e) {
      debugPrint('Error updating GeoJSON source $id: $e');
    }
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
