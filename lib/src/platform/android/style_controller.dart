part of 'map_state.dart';

/// Android specific implementation of the [StyleController].
class StyleControllerAndroid implements StyleController {
  const StyleControllerAndroid._(this._jniStyle, this._hostApi);

  final jni.Style _jniStyle;
  final pigeon.MapLibreHostApi _hostApi;

  @override
  Future<void> addLayer(StyleLayer layer, {String? belowLayerId}) async {
    // For SymbolStyleLayer, use Pigeon to properly handle icon-image properties and filters
    // (matching iOS implementation which works correctly with SDF icons)
    if (layer is SymbolStyleLayer) {
      // Adding symbol layer via Pigeon
      final layout = Map<String, Object>.from(layer.layout ?? {});
      // Pass filter through layout with special key
      if (layer.filter != null) {
        layout['__filter__'] = layer.filter!;
      }
      // Pass minZoom/maxZoom through layout (matching iOS implementation)
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
        paint: layer.paint ?? {},
        belowLayerId: belowLayerId,
      );
      // Symbol layer added
      return;
    }

    // For CircleStyleLayer, use Pigeon to properly handle filters
    if (layer is CircleStyleLayer) {
      // Adding circle layer via Pigeon
      final layout = Map<String, Object>.from(layer.layout ?? {});
      // Pass filter through layout with special key
      if (layer.filter != null) {
        layout['__filter__'] = layer.filter!;
      }
      // Pass minZoom/maxZoom through layout (matching iOS implementation)
      if (layer.minZoom != null) {
        layout['__minZoom__'] = layer.minZoom!;
      }
      if (layer.maxZoom != null) {
        layout['__maxZoom__'] = layer.maxZoom!;
      }
      await _hostApi.addCircleLayer(
        id: layer.id,
        sourceId: layer.sourceId,
        layout: layout,
        paint: layer.paint ?? {},
        belowLayerId: belowLayerId,
      );
      print('Android StyleController: Circle layer added successfully');
      return;
    }

    // For other layers, continue using JNI
    using((arena) {
      final jLayer = switch (layer) {
        FillStyleLayer() => jni.FillLayer(
          layer.id.toJString(),
          layer.sourceId.toJString(),
        ),
        CircleStyleLayer() => (() {
          final jLayer = jni.CircleLayer(
            layer.id.toJString(),
            layer.sourceId.toJString(),
          );
          // Set source-layer if it exists in layout
          if (layer.layout['source-layer'] case final String sourceLayer) {
            jLayer.withSourceLayer(sourceLayer.toJString());
          }
          return jLayer;
        })(),
        BackgroundStyleLayer() => jni.BackgroundLayer(layer.id.toJString()),
        FillExtrusionStyleLayer() => jni.FillExtrusionLayer(
          layer.id.toJString(),
          layer.sourceId.toJString(),
        ),
        HeatmapStyleLayer() => jni.HeatmapLayer(
          layer.id.toJString(),
          layer.sourceId.toJString(),
        ),
        HillshadeStyleLayer() => jni.HillshadeLayer(
          layer.id.toJString(),
          layer.sourceId.toJString(),
        ),
        LineStyleLayer() => jni.LineLayer(
          layer.id.toJString(),
          layer.sourceId.toJString(),
        ),
        RasterStyleLayer() => jni.RasterLayer(
          layer.id.toJString(),
          layer.sourceId.toJString(),
        ),
        _ =>
          throw UnimplementedError(
            'The Layer is not supported: ${layer.runtimeType}',
          ),
      };

      // paint and layout properties
      // Filter out 'source-layer' from layout as it's handled separately
      final layoutEntries = layer.layout.entries
          .where((e) => e.key != 'source-layer')
          .toList(growable: false);
      final paintEntries = layer.paint.entries.toList(growable: false);
      final props = JArray(
        jni.PropertyValue.nullableType(JObject.nullableType),
        layoutEntries.length + paintEntries.length,
      )..releasedBy(arena);
      for (var i = 0; i < paintEntries.length; i++) {
        final entry = paintEntries[i];
        props[i] = jni.PaintPropertyValue(
          entry.key.toJString(),
          entry.value.toJObject(arena),
          T: JObject.type,
        );
      }
      for (var i = 0; i < layoutEntries.length; i++) {
        final entry = layoutEntries[i];
        props[paintEntries.length + i] = jni.LayoutPropertyValue(
          entry.key.toJString(),
          entry.value.toJObject(arena),
          T: JObject.type,
        );
      }
      jLayer.releasedBy(arena);
      jLayer.setProperties(props);

      // add to style
      if (belowLayerId == null) {
        _jniStyle.addLayer(jLayer);
      } else {
        _jniStyle.addLayerBelow(jLayer, belowLayerId.toJString());
      }
    });
  }

  @override
  Future<void> addSource(Source source) async {
    final jniId = source.id.toJString();
    final jni.Source jniSource;
    switch (source) {
      case GeoJsonSource():
        final jniOptions = jni.GeoJsonOptions();
        final jniData = source.data.toJString();

        // Apply clustering options
        if (source.cluster) {
          jniOptions.withCluster(true);
          jniOptions.withClusterRadius(source.clusterRadius);
          if (source.clusterMaxZoom != null) {
            jniOptions.withClusterMaxZoom(source.clusterMaxZoom!);
          }
        }

        // Apply cluster properties (propagate custom properties to clusters)
        if (source.clusterProperties != null) {
          debugPrint('🔧 clusterProperties: ${source.clusterProperties!.keys.toList()}');
          for (final entry in source.clusterProperties!.entries) {
            final expressions = entry.value;
            if (expressions.length == 2) {
              try {
                final reduceJson = json.encode(expressions[0]);
                final mapJson = json.encode(expressions[1]);
                debugPrint('🔧 clusterProp "${entry.key}" reduceJson=$reduceJson mapJson=$mapJson');
                final reduceExpr =
                    _createExpressionFromJson(reduceJson);
                final mapExpr =
                    _createExpressionFromJson(mapJson);
                debugPrint('🔧 clusterProp "${entry.key}" reduceExpr=$reduceExpr mapExpr=$mapExpr');
                if (reduceExpr != null && mapExpr != null) {
                  jniOptions.withClusterProperty(
                    entry.key.toJString(),
                    reduceExpr,
                    mapExpr,
                  );
                  reduceExpr.release();
                  mapExpr.release();
                  debugPrint('✅ clusterProp "${entry.key}" applied successfully');
                } else {
                  debugPrint('❌ clusterProp "${entry.key}" FAILED - null expressions');
                }
              } catch (e) {
                debugPrint('❌ clusterProp "${entry.key}" ERROR: $e');
              }
            }
          }
        }

        if (source.data.startsWith('{')) {
          jniSource = jni.GeoJsonSource.new$4(jniId, jniData, jniOptions);
        } else {
          final jniUri = jni.URI.create(jniData);
          jniSource = jni.GeoJsonSource.new$8(jniId, jniUri!, jniOptions);
          jniUri.release();
        }
        jniOptions.release();
      case RasterDemSource():
        jniSource = jni.RasterDemSource.new$4(
          jniId,
          source.url!.toJString(),
          source.tileSize,
        );
        // TODO apply other properties
        jniSource.setVolatile(source.volatile.toJBoolean());
      case RasterSource():
        if (source.url case final String url) {
          jniSource = jni.RasterSource.new$4(
            jniId,
            url.toJString(),
            source.tileSize,
          );
        } else {
          final tiles = source.tiles!.map((e) => e.toJString());
          final tilesArray = JArray.of(JString.nullableType, tiles);
          final tileSet =
              jni.TileSet(
                  '{}'.toJString(),
                  tilesArray.as(JArray.type(JString.type)),
                )
                ..setMaxZoom(source.maxZoom)
                ..setMinZoom(source.minZoom);
          jniSource = jni.RasterSource.new$6(jniId, tileSet, source.tileSize);
          tilesArray.release();
          tileSet.release();
        }
        // TODO apply other properties
        jniSource.setVolatile(source.volatile.toJBoolean());
      case VectorSource():
        if (source.url case final String url) {
          jniSource = jni.VectorSource.new$3(jniId, url.toJString());
        } else if (source.tiles case final List<String> tiles) {
          // Use tiles array
          final jniTiles = tiles.map((e) => e.toJString());
          final tilesArray = JArray.of(JString.nullableType, jniTiles);
          final tileSet =
              jni.TileSet(
                  '{}'.toJString(),
                  tilesArray.as(JArray.type(JString.type)),
                )
                ..setMaxZoom(source.maxZoom)
                ..setMinZoom(source.minZoom);
          jniSource = jni.VectorSource.new$4(jniId, tileSet);
          tilesArray.release();
          tileSet.release();
        } else {
          throw Exception('VectorSource must have either url or tiles specified');
        }
        // TODO apply other properties
        jniSource.setVolatile(source.volatile.toJBoolean());
      case ImageSource():
        // https://maplibre.org/maplibre-native/android/api/-map-libre%20-native%20-android/org.maplibre.android.geometry/-lat-lng-quad/index.html
        final jniQuad = jni.LatLngQuad(
          source.coordinates.topLeft.toLatLng(),
          source.coordinates.topRight.toLatLng(),
          source.coordinates.bottomRight.toLatLng(),
          source.coordinates.bottomLeft.toLatLng(),
        );
        final jniUri = jni.URI(source.url.toJString());
        jniSource = jni.ImageSource.new$2(jniId, jniQuad, jniUri);
        jniUri.release();
        jniQuad.release();
      case VideoSource():
        throw UnimplementedError('Video source is only supported on web.');
      default:
        throw UnimplementedError(
          'The Source is not supported: ${source.runtimeType}',
        );
    }
    _jniStyle.addSource(jniSource);
    jniSource.release();
  }

  @override
  Future<void> removeLayer(String id) async =>
      _jniStyle.removeLayer(id.toJString());

  @override
  Future<void> removeSource(String id) async =>
      _jniStyle.removeSource(id.toJString());

  @override
  Future<void> addImage(String id, Uint8List bytes) =>
  // TODO: use JNI for this method
  _hostApi.addImage(id, bytes);

  @override
  Future<void> addImages(Map<String, Uint8List> images) =>
      _hostApi.addImages(images.keys.toList(), images.values.toList());

  @override
  Future<void> addSprite(String spriteJson, Uint8List spriteImage) =>
      _hostApi.addSprite(spriteJson, spriteImage);

  @override
  Future<void> removeImage(String id) async =>
      _jniStyle.removeImage(id.toJString());

  @override
  Future<void> updateGeoJsonSource({
    required String id,
    required String data,
  }) async {
    final source =
        _jniStyle.getSourceAs(id.toJString(), T: jni.GeoJsonSource.type)!;
    source.setGeoJson$3(data.toJString());
  }

  @override
  void updateGeoJsonSourceSync({
    required String id,
    required String data,
  }) {
    final source =
        _jniStyle.getSourceAs(id.toJString(), T: jni.GeoJsonSource.type)!;
    source.setGeoJson$3(data.toJString());
  }

  @override
  Future<List<String>> getAttributions() async => getAttributionsSync();

  @override
  List<String> getAttributionsSync() {
    final jSources = _jniStyle.getSources();
    final attributions = <String>[];
    for (final jSource in jSources) {
      final jniAttribution = jSource?.getAttribution();
      if (jniAttribution == null) continue;
      final attribution = jniAttribution.toDartString(releaseOriginal: true);
      if (attribution.trim().isEmpty) continue;
      attributions.add(attribution);
    }
    jSources.release();
    return attributions;
  }

  @override
  void dispose() {
    if (!_jniStyle.isReleased) {
      _jniStyle.release();
    }
  }

  JList<jni.Layer?> _getLayers() => _jniStyle.getLayers();

  @override
  void setProjection(MapProjection projection) {
    // globe is not supported on android.
  }

  /// Create a MapLibre Expression from a JSON string via JNI reflection.
  /// Uses Expression.raw(String) which parses a MapLibre expression JSON array.
  static JObject? _createExpressionFromJson(String jsonString) {
    try {
      final expressionClass = JClass.forName(
        r'org/maplibre/android/style/expressions/Expression',
      );
      final rawMethodId = expressionClass.staticMethodId(
        r'raw',
        r'(Ljava/lang/String;)Lorg/maplibre/android/style/expressions/Expression;',
      );
      final callStaticObjectMethod =
          jni_internal.ProtectedJniExtensions.lookup<
                NativeFunction<
                  JniResult Function(
                    Pointer<Void>,
                    JMethodIDPtr,
                    VarArgs<(Pointer<Void>,)>,
                  )
                >
              >('globalEnv_CallStaticObjectMethod')
              .asFunction<
                JniResult Function(
                  Pointer<Void>,
                  JMethodIDPtr,
                  Pointer<Void>,
                )
              >();
      final jString = jsonString.toJString();
      final result = callStaticObjectMethod(
        expressionClass.reference.pointer,
        rawMethodId as JMethodIDPtr,
        jString.reference.pointer,
      );
      jString.release();
      expressionClass.release();
      final obj = result.object<JObject?>(const JObjectNullableType());
      debugPrint('🔧 Expression.raw() result: $obj');
      return obj;
    } catch (e) {
      debugPrint('❌ Expression.raw() FAILED: $e');
      return null;
    }
  }
}
