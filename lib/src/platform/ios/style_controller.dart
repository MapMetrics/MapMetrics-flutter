part of 'map_state.dart';

/// Android specific implementation of the [StyleController].
class StyleControllerIos implements StyleController {
  StyleControllerIos._(this._ffiStyle, this._hostApi);

  final MLNStyle _ffiStyle;
  final pigeon.MapLibreHostApi _hostApi;

  @override
  Future<void> addImage(String id, Uint8List bytes) async {
    await _hostApi.addImage(id, bytes);
  }

  @override
  Future<void> addImages(Map<String, Uint8List> images) async {
    for (final entry in images.entries) {
      await _hostApi.addImage(entry.key, entry.value);
    }
  }

  @override
  Future<void> addSprite(String spriteJson, Uint8List spriteImage) async {
    await _hostApi.addSprite(spriteJson, spriteImage);
  }

  /// Pack `filter`, `minZoom` and `maxZoom` into `layout` under sentinel keys.
  ///
  /// Pigeon has no field for them, so they ride across the channel inside the
  /// layout map and the native side lifts them back out. Only the circle and
  /// symbol layers ever did this, which is why the other layer types did not
  /// expose the properties at all.
  static Map<String, Object> _layoutWithSentinels(StyleLayer layer) {
    final map = Map<String, Object>.from(layer.layout);
    if (layer.filter != null) map['__filter__'] = layer.filter!;
    if (layer.minZoom != null) map['__minZoom__'] = layer.minZoom!;
    if (layer.maxZoom != null) map['__maxZoom__'] = layer.maxZoom!;
    return map;
  }

  @override
  Future<void> addLayer(StyleLayer layer, {String? belowLayerId}) async {
    switch (layer) {
      case BackgroundStyleLayer():
        await _hostApi.addBackgroundLayer(
          id: layer.id,
          layout: _layoutWithSentinels(layer),
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      case CircleStyleLayer():
        final circleLayout = Map<String, Object>.from(layer.layout);
        if (layer.filter != null) {
          circleLayout['__filter__'] = layer.filter!;
        }
        if (layer.minZoom != null) {
          circleLayout['__minZoom__'] = layer.minZoom!;
        }
        if (layer.maxZoom != null) {
          circleLayout['__maxZoom__'] = layer.maxZoom!;
        }
        await _hostApi.addCircleLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: circleLayout,
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      case FillStyleLayer():
        await _hostApi.addFillLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: _layoutWithSentinels(layer),
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      case LineStyleLayer():
        await _hostApi.addLineLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: _layoutWithSentinels(layer),
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      case SymbolStyleLayer():
        final layout = Map<String, Object>.from(layer.layout);
        if (layer.filter != null) {
          layout['__filter__'] = layer.filter!;
        }
        if (layer.minZoom != null) {
          layout['__minZoom__'] = layer.minZoom!;
        }
        if (layer.maxZoom != null) {
          layout['__maxZoom__'] = layer.maxZoom!;
        }
        await _hostApi.addSymbolLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layout,
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      case FillExtrusionStyleLayer():
        await _hostApi.addFillExtrusionLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout,
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      case HeatmapStyleLayer():
        await _hostApi.addHeatmapLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout,
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      case HillshadeStyleLayer():
        await _hostApi.addHillshadeLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout,
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      case RasterStyleLayer():
        await _hostApi.addRasterLayer(
          id: layer.id,
          sourceId: layer.sourceId,
          layout: layer.layout,
          paint: layer.paint,
          belowLayerId: belowLayerId,
        );

      default:
        throw UnimplementedError(
          'The Layer is not supported: ${layer.runtimeType}',
        );
    }
  }

  @override
  Future<void> addSource(Source source) async {
    switch (source) {
      case GeoJsonSource():
        // Encode clusterProperties as JSON string for Pigeon transport
        String? clusterPropsJson;
        if (source.clusterProperties != null) {
          clusterPropsJson = json.encode(source.clusterProperties);
        }
        // These used to catch-and-print. That made addSource resolve
        // successfully after the native side had refused the data, so callers
        // went on to add layers against a source that did not exist and the map
        // just stayed empty. A source that fails to add is not a warning.
        if (source.cluster) {
          await _hostApi.addClusteredGeoJsonSource(
            id: source.id,
            data: source.data,
            clustered: source.cluster,
            clusterRadius: source.clusterRadius.toDouble(),
            clusterMaxZoom: (source.clusterMaxZoom ?? 16.0).toDouble(),
            clusterPropertiesJson: clusterPropsJson,
          );
        } else {
          await _hostApi.addClusteredGeoJsonSource(
            id: source.id,
            data: source.data,
            clustered: false,
            clusterRadius: 0.0,
            clusterMaxZoom: 0.0,
          );
        }
      case RasterDemSource():
        throw UnimplementedError(
          'RasterDemSource not yet implemented via Pigeon',
        );
      case RasterSource():
        await _hostApi.addRasterSource(
          id: source.id,
          tiles: source.tiles ?? [],
          minZoom: source.minZoom,
          maxZoom: source.maxZoom,
          tileSize: source.tileSize.toDouble(),
          attribution: source.attribution,
        );
      case VectorSource():
        try {
          await _hostApi.addVectorSource(
            id: source.id,
            tiles: source.tiles ?? [],
            minZoom: source.minZoom,
            maxZoom: source.maxZoom,
          );
        } catch (e) {
          print('iOS: Error adding vector source via Pigeon: $e');
          rethrow;
        }
      case ImageSource():
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
  }

  @override
  Future<void> removeLayer(String id) async {
    try {
      await _hostApi.removeLayer(id);
    } catch (e) {
      print('iOS: Error removing layer $id: $e');
      rethrow;
    }
  }

  @override
  Future<void> removeSource(String id) async {
    try {
      await _hostApi.removeSource(id);
    } catch (e) {
      print('iOS: Error removing source $id: $e');
      rethrow;
    }
  }

  Future<void> updateGeoJsonSource({
    required String id,
    required String data,
  }) async {
    try {
      await _hostApi.updateGeoJsonSource(id, data);
    } catch (e) {
      print('iOS: Error updating source $id: $e');
      rethrow;
    }
  }

  @override
  void updateGeoJsonSourceSync({
    required String id,
    required String data,
  }) {
    // iOS uses Pigeon (async) — delegate to async version
    updateGeoJsonSource(id: id, data: data);
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
