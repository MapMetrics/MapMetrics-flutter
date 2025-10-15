import 'package:flutter/foundation.dart';

/// Represents a feature queried from the map with its properties.
///
/// When querying the map for rendered features at a specific screen location,
/// this class contains the feature's layer information and all associated
/// properties from the vector tile data.
///
/// {@category Basic}
@immutable
class QueriedFeature {
  /// Creates a [QueriedFeature] with the given layer information and properties.
  const QueriedFeature({
    required this.layerId,
    required this.sourceId,
    required this.sourceLayer,
    required this.properties,
  });

  /// The ID of the layer this feature belongs to.
  final String layerId;

  /// The ID of the source this feature belongs to.
  final String sourceId;

  /// The source layer name within the vector tile source.
  /// This is `null` for non-vector tile sources.
  final String? sourceLayer;

  /// The properties associated with this feature.
  ///
  /// This contains all key-value pairs from the feature's properties in the
  /// vector tile data, such as name, amenity type, opening hours, address, etc.
  final Map<String, dynamic> properties;

  @override
  String toString() =>
      'QueriedFeature(layerId: $layerId, sourceId: $sourceId, '
      'sourceLayer: $sourceLayer, properties: $properties)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueriedFeature &&
          runtimeType == other.runtimeType &&
          layerId == other.layerId &&
          sourceId == other.sourceId &&
          sourceLayer == other.sourceLayer &&
          _mapEquals(properties, other.properties);

  @override
  int get hashCode => Object.hash(
        layerId,
        sourceId,
        sourceLayer,
        Object.hashAllUnordered(properties.entries.map((e) => Object.hash(e.key, e.value))),
      );

  /// Helper method to compare two maps for equality
  bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
