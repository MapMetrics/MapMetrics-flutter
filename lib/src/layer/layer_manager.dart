import 'dart:async';
import 'dart:convert';

import 'package:mapmetrics/mapmetrics.dart';

/// The layer manager handles the high-level layer API used in
/// [MapLibreMap.layers]. This is an internal class that doesn't get exposed
/// publicly.
class LayerManager {
  /// Create a new [LayerManager]. Needs the [MapController] of the
  /// [MapLibreMap] and the initial list of [Layer]s.
  ///
  /// It creates all sources and layers on the map. It's not needed to compare
  /// the layers with [_oldLayers] in for the initial creation.
  LayerManager(this.style, List<Layer> layers) {
    _oldLayers = layers;
    unawaited(_addLayers(layers));
  }

  /// Create the source and style layer for each [Layer], in order.
  ///
  /// The source must exist before the layer that references it. These two calls
  /// used to be fired without awaiting either, so on iOS addCircleLayer
  /// regularly landed first and failed with `Source not found: <id>` -- an
  /// error nobody saw, because the dropped future carried it away.
  Future<void> _addLayers(List<Layer> layers) async {
    for (final (index, layer) in layers.indexed) {
      final source = GeoJsonSource(
        id: layer.getSourceId(index),
        data: _encodeGeometries(layer),
      );
      await style.addSource(source);
      await style.addLayer(layer.createStyleLayer(index));
    }
  }

  /// Encode a [Layer]'s geometries as the source data for its style layer.
  ///
  /// Emits a FeatureCollection of one Feature per geometry. Two things here are
  /// deliberate, and both were bugs:
  ///
  /// It used to emit a bare GeometryCollection. That is valid GeoJSON but is
  /// not a feature, so it exposes nothing for a style layer to draw -- on iOS
  /// it parses to MLNShapeCollection rather than the MLNShapeCollectionFeature
  /// a source needs.
  ///
  /// The JSON is built by hand rather than via geotypes' Feature.toJson, which
  /// serialises a null id as `"id": null`. RFC 7946 allows only a string or a
  /// number there, and MapLibre's parser rejects the whole document -- the
  /// native side answered "Invalid GeoJSON data" for every layer.
  ///
  /// Every widget in the high-level `layers:` API funnels through here, so both
  /// faults emptied CircleLayer, MarkerLayer, PolygonLayer and PolylineLayer
  /// alike.
  static String _encodeGeometries(Layer layer) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final geometry in layer.list)
        {
          'type': 'Feature',
          'geometry': geometry.toJson(),
          'properties': const <String, Object?>{},
        },
    ],
  });

  /// The [StyleController] of the [MapLibreMap].
  final StyleController style;

  /// The saved [Layer]s from before `setState()` gets called and the
  /// layers get changed.
  late List<Layer> _oldLayers;

  /// Called when `setState()` gets called and the widget rebuilds. This method
  /// translates the declarative layer definition of [MapLibreMap.layers] to
  /// imperative calls to the maps' [MapController].
  void updateLayers(List<Layer> layers) {
    unawaited(_updateLayers(layers));
  }

  /// Apply a changed [MapLibreMap.layers] list, in order.
  ///
  /// Like the initial creation, every call here must be awaited: a source has
  /// to exist before the layer that names it. These were fired without
  /// awaiting, so a layer added by setState -- for instance one withheld until
  /// its icon image was registered -- raced its own source and failed with
  /// "Source not found", silently, because the future was dropped.
  Future<void> _updateLayers(List<Layer> layers) async {
    for (var index = 0; index < layers.length; index++) {
      final layer = layers[index];
      final oldLayer = index > _oldLayers.length - 1 ? null : _oldLayers[index];
      // update source
      // TODO check if the entities of both lists are equal
      if (oldLayer case Layer()) {
        await style.updateGeoJsonSource(
          id: layer.getSourceId(index),
          data: _encodeGeometries(layer),
        );
      } else {
        final source = GeoJsonSource(
          id: layer.getSourceId(index),
          data: _encodeGeometries(layer),
        );
        await style.addSource(source);
      }
      // update layer
      if (layer != oldLayer) {
        if (oldLayer case Layer()) {
          await style.removeLayer(oldLayer.getLayerId(index));
        }
        await style.addLayer(layer.createStyleLayer(index));
      }
    }
    // remove any left-over sources and layers from the map
    for (var i = 0; i < (_oldLayers.length - layers.length); i++) {
      final index = layers.length + i;
      final oldLayer = _oldLayers[index];
      await style.removeLayer(oldLayer.getLayerId(index));
      await style.removeSource(oldLayer.getSourceId(index));
    }
    _oldLayers = layers;
  }
}
