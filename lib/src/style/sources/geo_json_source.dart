part of 'source.dart';

/// A GeoJSON source. Data must be provided via a "data" property, whose value
/// can be a URL or inline GeoJSON. When using in a browser, the GeoJSON data
/// must be on the same domain as the map or served with CORS headers.
///
/// https://maplibre.org/maplibre-style-spec/sources/#geojson
///
/// {@category Style}
/// {@subCategory Style Sources}
final class GeoJsonSource extends Source {
  /// The default constructor for a [GeoJsonSource] object.
  const GeoJsonSource({
    required super.id,
    required this.data,
    this.maxZoom = 18,
    this.attribution,
    this.cluster = false,
    this.clusterRadius = 50,
    this.clusterMaxZoom,
    this.clusterProperties,
  });

  /// A URL to a GeoJSON file, or GeoJSON string.
  final String data;

  /// Maximum zoom level at which to create vector tiles (higher means greater
  /// detail at high zoom levels).
  ///
  /// Defaults to 18.
  final double maxZoom;

  /// Contains an attribution to be displayed when the map is shown to a user.
  final String? attribution;

  /// If true, GeoJSON point features will be clustered together.
  /// The radius of each cluster is specified by [clusterRadius].
  /// The maximum zoom level at which to cluster points is specified by [clusterMaxZoom].
  ///
  /// Defaults to false.
  final bool cluster;

  /// The radius of each cluster if clustering is enabled.
  /// A value of 512 produces a radius equal to the width of a tile.
  ///
  /// Defaults to 50.
  final int clusterRadius;

  /// The maximum zoom level at which to cluster points if clustering is enabled.
  /// Defaults to one zoom level less than [maxZoom] so that, at the maximum zoom level,
  /// the shapes are not clustered.
  final int? clusterMaxZoom;

  /// Properties to aggregate from clustered points.
  /// The key is the property name, and the value is a list of two expressions:
  /// 1. An expression that determines how the attribute values are accumulated from the cluster points
  /// 2. An expression that determines which attribute values are accessed from individual features within a cluster
  final Map<String, List<Object>>? clusterProperties;

  // TODO add more fields https://maplibre.org/maplibre-style-spec/sources/#buffer
}
