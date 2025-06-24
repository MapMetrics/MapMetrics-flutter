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
    print(
      'iOS StyleController: Creating layer for source: ${layer.runtimeType}',
    );

    switch (layer) {
      case BackgroundStyleLayer():
        print('iOS StyleController: Adding background layer via Pigeon');
        await _hostApi.addBackgroundLayer(
          id: layer.id,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Background layer added successfully');

      case CircleStyleLayer():
        print('iOS StyleController: Adding circle layer via Pigeon');
        await _hostApi.addCircleLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Circle layer added successfully');

      case FillStyleLayer():
        print('iOS StyleController: Adding fill layer via Pigeon');
        await _hostApi.addFillLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Fill layer added successfully');

      case LineStyleLayer():
        print('iOS StyleController: Adding line layer via Pigeon');
        await _hostApi.addLineLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Line layer added successfully');

      case SymbolStyleLayer():
        print('iOS StyleController: Adding symbol layer via Pigeon');
        await _hostApi.addSymbolLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Symbol layer added successfully');

      case FillExtrusionStyleLayer():
        print('iOS StyleController: Adding fill extrusion layer via Pigeon');
        await _hostApi.addFillExtrusionLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Fill extrusion layer added successfully');

      case HeatmapStyleLayer():
        print('iOS StyleController: Adding heatmap layer via Pigeon');
        await _hostApi.addHeatmapLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Heatmap layer added successfully');

      case HillshadeStyleLayer():
        print('iOS StyleController: Adding hillshade layer via Pigeon');
        await _hostApi.addHillshadeLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Hillshade layer added successfully');

      case RasterStyleLayer():
        print('iOS StyleController: Adding raster layer via Pigeon');
        await _hostApi.addRasterLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout ?? {},
          paint: layer.paint ?? {},
          belowLayerId: belowLayerId,
        );
        print('iOS StyleController: Raster layer added successfully');

      default:
        throw UnimplementedError(
          'The Layer is not supported: ${layer.runtimeType}',
        );
    }
  }

  @override
  Future<void> addSource(Source source) async {
    print(
      'iOS StyleController: addSource called for ${source.runtimeType} with ID: ${source.id}',
    );

    switch (source) {
      case GeoJsonSource():
        print(
          'iOS StyleController: Processing GeoJsonSource with cluster: ${source.cluster}',
        );
        if (source.cluster) {
          // Use the new Pigeon method for clustering
          print(
            'iOS StyleController: Calling addClusteredGeoJsonSource via Pigeon',
          );
          try {
            await _hostApi.addClusteredGeoJsonSource(
              id: source.id,
              data: source.data,
              clustered: source.cluster,
              clusterRadius: source.clusterRadius.toDouble(),
              clusterMaxZoom: (source.clusterMaxZoom ?? 16.0).toDouble(),
            );
            print(
              'iOS: Successfully added clustered source via Pigeon: ${source.id}',
            );
          } catch (e) {
            print('iOS: Error adding clustered source via Pigeon: $e');
          }
        } else {
          // For non-clustered sources, we'll use the same Pigeon method with clustering disabled
          print('iOS StyleController: Using Pigeon for non-clustered source');
          try {
            await _hostApi.addClusteredGeoJsonSource(
              id: source.id,
              data: source.data,
              clustered: false,
              clusterRadius: 0.0,
              clusterMaxZoom: 0.0,
            );
            print('iOS: Added regular GeoJSON source via Pigeon: ${source.id}');
          } catch (e) {
            print('iOS: Error adding regular source via Pigeon: $e');
          }
        }
      case RasterDemSource():
        // TODO: Implement Pigeon method for RasterDemSource
        print(
          'iOS StyleController: RasterDemSource not yet implemented via Pigeon',
        );
        throw UnimplementedError(
          'RasterDemSource not yet implemented via Pigeon',
        );
      case RasterSource():
        // TODO: Implement Pigeon method for RasterSource
        print(
          'iOS StyleController: RasterSource not yet implemented via Pigeon',
        );
        throw UnimplementedError('RasterSource not yet implemented via Pigeon');
      case VectorSource():
        // TODO: Implement Pigeon method for VectorSource
        print(
          'iOS StyleController: VectorSource not yet implemented via Pigeon',
        );
        throw UnimplementedError('VectorSource not yet implemented via Pigeon');
      case ImageSource():
        // TODO: Implement Pigeon method for ImageSource
        print(
          'iOS StyleController: ImageSource not yet implemented via Pigeon',
        );
        throw UnimplementedError('ImageSource not yet implemented via Pigeon');
      case VideoSource():
        throw UnimplementedError('Video source is only supported on web.');
      default:
        throw UnimplementedError(
          'The Source is not supported: ${source.runtimeType}',
        );
    }
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<List<String>> getAttributions() async => getAttributionsSync();

  @override
  Future<void> removeImage(String id) async {
    // TODO: Implement Pigeon method for removeImage
    print('iOS StyleController: removeImage not yet implemented via Pigeon');
  }

  @override
  Future<void> removeLayer(String id) async {
    // TODO: Implement Pigeon method for removeLayer
    print('iOS StyleController: removeLayer not yet implemented via Pigeon');
  }

  @override
  Future<void> removeSource(String id) async {
    // TODO: Implement Pigeon method for removeSource
    print('iOS StyleController: removeSource not yet implemented via Pigeon');
  }

  @override
  Future<void> updateGeoJsonSource({
    required String id,
    required String data,
  }) async {
    // TODO: Implement Pigeon method for updateGeoJsonSource
    print(
      'iOS StyleController: updateGeoJsonSource not yet implemented via Pigeon',
    );
  }

  NSArray _getLayers() {
    // TODO: Implement Pigeon method for getting layers
    print('iOS StyleController: _getLayers not yet implemented via Pigeon');
    return NSArray.new1();
  }

  @override
  void setProjection(MapProjection projection) {
    // no implementation needed, globe is not supported on web.
  }

  @override
  List<String> getAttributionsSync() {
    final attributions = <String>[];
    if (_ffiStyle.sources == null) {
      // Stub or not available, return empty
      return attributions;
    }
    final sources = _ffiStyle.sources.allObjects as NSArray?;
    if (sources == null) return attributions;
    for (var i = 0; i < sources.count; i++) {
      final source = sources.objectAtIndex_(i);
      if (!MLNTileSource.isInstance(source)) continue;
      final tileSource = MLNTileSource.castFrom(source);
      final attrInfos = tileSource.attributionInfos as NSArray?;
      if (attrInfos == null) continue;
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
