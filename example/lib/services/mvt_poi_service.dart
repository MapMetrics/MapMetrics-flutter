import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vector_tile/vector_tile.dart';
import '../models/poi_feature.dart';

/// Tile coordinate tuple
class TileCoordinate {
  final int x;
  final int y;
  final int z;

  TileCoordinate(this.x, this.y, this.z);

  @override
  bool operator ==(Object other) =>
      other is TileCoordinate && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Tile($z/$x/$y)';
}

/// Service for fetching and parsing MVT (Mapbox Vector Tile) POI data
class MvtPoiService {
  static const _tileServerUrl =
      'https://poi-tile-server-development.jim9710.workers.dev/tiles';
  static const _poiLayerName = 'pois';

  /// Fetch nearby restrooms from MVT tiles
  /// Returns a list of POI features sorted by distance
  Future<List<PoiFeature>> fetchNearbyRestrooms({
    required double lat,
    required double lon,
    int zoom = 14,
    double radiusKm = 7.0,
  }) async {
    debugPrint('🔵 Fetching restrooms near ($lat, $lon) at zoom $zoom, radius ${radiusKm}km');

    // Calculate which tiles cover the search area
    final tiles = _calculateTilesCovering(lat, lon, zoom, radiusKm);
    debugPrint('🔵 Need to fetch ${tiles.length} tiles: ${tiles.map((t) => t.toString()).join(', ')}');

    // Fetch and parse all tiles in parallel
    final allFeatures = <PoiFeature>[];
    // Dedupe by stable coordinate key; many features lack an `id` property
    final seenKeys = <String>{};

    await Future.wait(
      tiles.map((tile) async {
        try {
          final features = await _fetchAndParseTile(tile, lat, lon);

          // Add features, removing duplicates by coordinate
          for (final feature in features) {
            final key =
                '${feature.lat.toStringAsFixed(6)},${feature.lon.toStringAsFixed(6)}';
            if (seenKeys.add(key)) allFeatures.add(feature);
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching tile ${tile}: $e');
          // Continue with other tiles
        }
      }),
    );

    debugPrint('✅ Found ${allFeatures.length} total POIs');

    // Filter for restroom-relevant POIs
    final restrooms = allFeatures.where(_isRestroomPoi).toList();
    debugPrint('✅ Filtered to ${restrooms.length} restrooms');

    // Filter by distance and sort
    final nearbyRestrooms = restrooms
        .where((poi) {
          final isWithinRadius = poi.distance <= radiusKm;
          if (!isWithinRadius) {
            debugPrint('❌ POI "${poi.name}" rejected: ${poi.distance.toStringAsFixed(2)}km > ${radiusKm}km');
          }
          return isWithinRadius;
        })
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));

    debugPrint('✅ ${nearbyRestrooms.length} restrooms within ${radiusKm}km');
    return nearbyRestrooms;
  }

  /// Calculate which tiles cover a circular area
  List<TileCoordinate> _calculateTilesCovering(
    double lat,
    double lon,
    int zoom,
    double radiusKm,
  ) {
    final centerTile = _latLonToTile(lat, lon, zoom);
    final tiles = <TileCoordinate>{centerTile};

    // Calculate approximate tile size in km at this latitude
    final tileWidthKm = _getTileWidthKm(lat, zoom);

    // How many tiles do we need to cover the radius?
    final tilesNeeded = (radiusKm / tileWidthKm).ceil();

    // Add surrounding tiles
    for (var dx = -tilesNeeded; dx <= tilesNeeded; dx++) {
      for (var dy = -tilesNeeded; dy <= tilesNeeded; dy++) {
        tiles.add(TileCoordinate(
          centerTile.x + dx,
          centerTile.y + dy,
          zoom,
        ));
      }
    }

    return tiles.toList();
  }

  /// Fetch and parse a single MVT tile
  Future<List<PoiFeature>> _fetchAndParseTile(
    TileCoordinate tile,
    double userLat,
    double userLon,
  ) async {
    // Fetch tile data
    final url = '$_tileServerUrl/${tile.z}/${tile.x}/${tile.y}.mvt';
    debugPrint('  🔵 Fetching: $url');

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch tile: ${response.statusCode}');
    }

    // Parse MVT
    final vectorTile = VectorTile.fromBytes(bytes: response.bodyBytes);

    // Find POI layer
    final poiLayer = vectorTile.layers.where((l) => l.name == _poiLayerName).firstOrNull;
    if (poiLayer == null) {
      debugPrint('  ⚠️ No "$_poiLayerName" layer in tile $tile');
      return [];
    }

    debugPrint('  ✅ Found ${poiLayer.features.length} POIs in tile $tile');

    // Log sample POI properties for debugging
    if (poiLayer.features.isNotEmpty) {
      final sample = poiLayer.features.first;
      final sampleProps = sample.decodeProperties();
      debugPrint('  📋 Sample POI properties: $sampleProps');
    }

    // Parse features
    final features = <PoiFeature>[];
    for (final feature in poiLayer.features) {
      try {
        final poi = _parseFeature(feature, tile, userLat, userLon);
        if (poi != null) {
          features.add(poi);
        }
      } catch (e) {
        debugPrint('  ⚠️ Error parsing feature: $e');
        // Continue with next feature
      }
    }

    return features;
  }

  /// Parse a single MVT feature into a PoiFeature
  PoiFeature? _parseFeature(
    VectorTileFeature feature,
    TileCoordinate tile,
    double userLat,
    double userLon,
  ) {
    // Get feature properties
    final properties = feature.decodeProperties();

    // Get geometry (we only care about Point geometries)
    if (feature.type != VectorTileGeomType.POINT) {
      return null;
    }

    // Convert to GeoJSON Point with tile coordinates to get lat/lon
    final geoJson = feature.toGeoJson<GeoJsonPoint>(x: tile.x, y: tile.y, z: tile.z);
    if (geoJson == null || geoJson.geometry == null) {
      return null;
    }

    // Access coordinates from GeoJSON Point geometry [lon, lat]
    final coords = geoJson.geometry!.coordinates;
    if (coords.length < 2) {
      return null;
    }

    final lon = coords[0];
    final lat = coords[1];

    // Calculate distance from user location
    final distance = _calculateDistance(
      userLat,
      userLon,
      lat,
      lon,
    );

    // Create POI feature
    return PoiFeature.fromMvt(
      properties: properties,
      lat: lat,
      lon: lon,
      distance: distance,
    );
  }

  /// Convert lat/lon to tile coordinates
  TileCoordinate _latLonToTile(double lat, double lon, int zoom) {
    final x = ((lon + 180.0) / 360.0 * pow(2, zoom)).floor();
    final latRad = lat * pi / 180.0;
    final y = ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * pow(2, zoom)).floor();
    return TileCoordinate(x, y, zoom);
  }

  /// Calculate approximate tile width in kilometers at given latitude
  double _getTileWidthKm(double lat, int zoom) {
    const earthCircumferenceKm = 40075.0;
    final latRad = lat * pi / 180.0;
    return (earthCircumferenceKm * cos(latRad)) / pow(2, zoom);
  }

  /// Calculate Haversine distance between two points in kilometers
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km

    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  /// Check if POI matches restroom filter criteria
  /// Matches filter logic from new_poi_demo_page.dart exactly
  bool _isRestroomPoi(PoiFeature poi) {
    debugPrint(
        '🔍 Evaluating POI: ${poi.name} (amenity: ${poi.amenity}, shop: ${poi.shop}, highway: ${poi.highway}, tourism: ${poi.tourism}, toilets: ${poi.toilets})');

    // Direct restroom facilities
    if (poi.amenity == 'toilets') {
      debugPrint('  ✅ MATCH: amenity=toilets');
      return true;
    }

    // Food & beverage establishments (assumed to have restrooms)
    if (poi.amenity != null &&
        ['restaurant', 'cafe', 'fast_food', 'bar', 'pub'].contains(poi.amenity)) {
      debugPrint('  ✅ MATCH: food/beverage amenity=${poi.amenity}');
      return true;
    }

    // Fuel & services (gas stations, truck stops, rest areas)
    if (poi.amenity != null &&
        ['fuel', 'truck_stop', 'rest_area'].contains(poi.amenity)) {
      debugPrint('  ✅ MATCH: fuel/services amenity=${poi.amenity}');
      return true;
    }

    // Highway rest areas and service areas
    if (poi.highway != null &&
        ['services', 'rest_area'].contains(poi.highway)) {
      debugPrint('  ✅ MATCH: highway=${poi.highway}');
      return true;
    }

    // Hotels and similar (assumed to have restrooms)
    if (poi.tourism != null &&
        ['hotel', 'motel', 'hostel', 'guest_house']
            .contains(poi.tourism)) {
      debugPrint('  ✅ MATCH: tourism=${poi.tourism}');
      return true;
    }

    // Malls and large stores (assumed to have restrooms)
    if (poi.shop != null && ['mall', 'department_store'].contains(poi.shop)) {
      debugPrint('  ✅ MATCH: shop=${poi.shop} (mall/department_store)');
      return true;
    }

    // Retail with toilets (conditional - must have toilets=yes tag)
    if (poi.shop != null && poi.toilets == 'yes') {
      debugPrint('  ✅ MATCH: shop with toilets=${poi.toilets}');
      return true;
    }

    // Any POI explicitly marked with public restrooms
    if (poi.toilets == 'yes' || poi.toilets == 'public') {
      debugPrint('  ✅ MATCH: toilets=${poi.toilets}');
      return true;
    }

    debugPrint('  ❌ REJECTED: No matching criteria');
    return false;
  }
}
