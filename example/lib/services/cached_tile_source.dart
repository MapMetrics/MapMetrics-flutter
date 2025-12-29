import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'tile_cache_manager.dart';

/// A tile source that provides cached tiles with fallback to network
class CachedTileSource {
  static CachedTileSource? _instance;
  static const String _baseUrl = 'https://gateway.mapmetrics-atlas.net';
  static const String _token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJkZDUwODgyMi05NTAyLTRhYjUtYmZlMi01ZTZlZDU4MDljMmQiLCJzY29wZSI6WyJtYXBzIiwiYXV0b2NvbXBsZXRlIiwiZ2VvY29kZSIsImRpcmVjdGlvbnMiLCJtYXBfbWF0Y2hpbmciLCJvcHRpbWl6ZSIsIm1hdHJpeCIsImlzb2Nocm9uZSJdLCJpYXQiOjE3NjExNDQ1OTl9.MbfXeBtRpzzaLgcdTE0xzMa-OEemCWNWprEbs1RO2rI';
  
  TileCacheManager? _cacheManager;
  final Map<String, Completer<Uint8List?>> _activeRequests = {};

  CachedTileSource._internal();

  static Future<CachedTileSource> getInstance() async {
    _instance ??= CachedTileSource._internal();
    await _instance!._initialize();
    return _instance!;
  }

  Future<void> _initialize() async {
    try {
      _cacheManager = await TileCacheManager.getInstance();
      print('CachedTileSource initialized with cache manager');
    } catch (e) {
      print('Failed to initialize CachedTileSource: $e');
    }
  }

  /// Get a tile with caching - returns cached version if available, otherwise fetches from network
  Future<Uint8List?> getTile(int z, int x, int y) async {
    final tileUrl = '$_baseUrl/20250110/$z/$x/$y.mvt?token=$_token';
    final cacheKey = '${z}_${x}_$y';

    // Check if this request is already in progress
    if (_activeRequests.containsKey(cacheKey)) {
      return _activeRequests[cacheKey]!.future;
    }

    // Create a new request completer
    final completer = Completer<Uint8List?>();
    _activeRequests[cacheKey] = completer;

    try {
      if (_cacheManager != null) {
        // Try to get from cache first
        final cachedData = await _cacheManager!.getTile(tileUrl);
        if (cachedData != null) {
          completer.complete(cachedData);
          _activeRequests.remove(cacheKey);
          return cachedData;
        }
      }

      // Not in cache, fetch from network
      final response = await http.get(
        Uri.parse(tileUrl),
        headers: {
          'User-Agent': 'MapMetrics-Flutter-Cache/1.0',
          'Accept': 'application/x-protobuf',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final tileData = response.bodyBytes;
        
        // Cache the tile for future use
        if (_cacheManager != null) {
          // Use the cache manager's internal caching logic
          await _cacheManager!.getTile(tileUrl); // This will cache it
        }
        
        completer.complete(tileData);
        _activeRequests.remove(cacheKey);
        return tileData;
      } else {
        print('Failed to fetch tile $z/$x/$y: ${response.statusCode}');
        completer.complete(null);
        _activeRequests.remove(cacheKey);
        return null;
      }
    } catch (e) {
      print('Error fetching tile $z/$x/$y: $e');
      completer.complete(null);
      _activeRequests.remove(cacheKey);
      return null;
    }
  }

  /// Generate a style that uses cached tiles
  Map<String, dynamic> generateCachedStyle() {
    return {
      "version": 8,
      "name": "Cached MapMetrics Style",
      "metadata": {
        "mapmetrics:type": "cached"
      },
      "sources": {
        "mapmetrics-cached": {
          "type": "vector",
          "tiles": [
            "$_baseUrl/20250110/{z}/{x}/{y}.mvt?token=$_token"
          ],
          "minzoom": 0,
          "maxzoom": 22,
          "attribution": "© MapMetrics"
        }
      },
      "layers": [
        {
          "id": "background",
          "type": "background",
          "paint": {
            "background-color": "#f8f9fa"
          }
        },
        {
          "id": "water",
          "type": "fill",
          "source": "mapmetrics-cached",
          "source-layer": "water",
          "paint": {
            "fill-color": "#4a90e2"
          }
        },
        {
          "id": "landuse",
          "type": "fill",
          "source": "mapmetrics-cached", 
          "source-layer": "landuse",
          "paint": {
            "fill-color": [
              "match",
              ["get", "class"],
              "park", "#90c695",
              "forest", "#7fb069", 
              "residential", "#e8e8e8",
              "commercial", "#ffd7ba",
              "industrial", "#d4d4d4",
              "#f0f0f0"
            ]
          }
        },
        {
          "id": "roads",
          "type": "line",
          "source": "mapmetrics-cached",
          "source-layer": "transportation",
          "paint": {
            "line-color": [
              "match",
              ["get", "class"],
              "motorway", "#e66e00",
              "trunk", "#ff8c00", 
              "primary", "#ffa500",
              "secondary", "#ffb84d",
              "tertiary", "#ffcc80",
              "#ffffff"
            ],
            "line-width": [
              "interpolate",
              ["linear"],
              ["zoom"],
              5, [
                "match",
                ["get", "class"],
                "motorway", 1,
                "trunk", 0.8,
                "primary", 0.6,
                0.4
              ],
              15, [
                "match", 
                ["get", "class"],
                "motorway", 8,
                "trunk", 6,
                "primary", 4,
                "secondary", 3,
                "tertiary", 2,
                1
              ]
            ]
          }
        },
        {
          "id": "buildings",
          "type": "fill-extrusion", 
          "source": "mapmetrics-cached",
          "source-layer": "building",
          "minzoom": 15,
          "paint": {
            "fill-extrusion-color": "#d6d6d6",
            "fill-extrusion-height": [
              "interpolate",
              ["linear"],
              ["zoom"],
              15, 0,
              16, ["get", "height"]
            ],
            "fill-extrusion-base": ["get", "min_height"]
          }
        }
      ]
    };
  }

  void dispose() {
    _activeRequests.clear();
  }
}