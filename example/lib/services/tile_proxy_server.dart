import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'tile_cache_manager.dart';

/// A local tile proxy server that intercepts MapLibre tile requests
/// and serves cached tiles to reduce server load
class TileProxyServer {
  static TileProxyServer? _instance;
  HttpServer? _server;
  TileCacheManager? _cacheManager;
  int _port = 8080;
  int _totalRequests = 0;
  int _cachedResponses = 0;
  
  static const String _baseUrl = 'https://gateway.mapmetrics-atlas.net';
  static const String _token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJkZDUwODgyMi05NTAyLTRhYjUtYmZlMi01ZTZlZDU4MDljMmQiLCJzY29wZSI6WyJtYXBzIiwiYXV0b2NvbXBsZXRlIiwiZ2VvY29kZSIsImRpcmVjdGlvbnMiLCJtYXBfbWF0Y2hpbmciLCJvcHRpbWl6ZSIsIm1hdHJpeCIsImlzb2Nocm9uZSJdLCJpYXQiOjE3NjExNDQ1OTl9.MbfXeBtRpzzaLgcdTE0xzMa-OEemCWNWprEbs1RO2rI';

  TileProxyServer._internal();

  static Future<TileProxyServer> getInstance() async {
    _instance ??= TileProxyServer._internal();
    await _instance!._initialize();
    return _instance!;
  }

  Future<void> _initialize() async {
    _cacheManager = await TileCacheManager.getInstance();
  }

  /// Start the local proxy server
  Future<String> startServer() async {
    if (_server != null) {
      print('Tile proxy server already running on port $_port');
      return 'http://localhost:$_port';
    }

    try {
      // Try to find an available port
      for (int port = 8080; port < 8090; port++) {
        try {
          _server = await HttpServer.bind('127.0.0.1', port);
          _port = port;
          break;
        } catch (e) {
          print('Port $port not available, trying next...');
        }
      }

      if (_server == null) {
        throw Exception('No available ports found for tile proxy');
      }

      print('🚀 Tile proxy server started on http://localhost:$_port');
      
      // Handle incoming tile requests
      _server!.listen(_handleRequest);
      
      return 'http://localhost:$_port';
    } catch (e) {
      print('Failed to start tile proxy server: $e');
      rethrow;
    }
  }

  /// Handle incoming HTTP requests and serve cached tiles
  Future<void> _handleRequest(HttpRequest request) async {
    _totalRequests++;
    
    try {
      final path = request.uri.path;
      
      // Handle style.json request
      if (path == '/style.json') {
        await _serveProxyStyle(request);
        return;
      }
      
      // Handle tile requests: /{dataset}/{z}/{x}/{y}.mvt
      final tileRegex = RegExp(r'^/([^/]+)/(\d+)/(\d+)/(\d+)\.mvt$');
      final match = tileRegex.firstMatch(path);
      
      if (match != null) {
        final dataset = match.group(1)!;
        final z = int.parse(match.group(2)!);
        final x = int.parse(match.group(3)!);
        final y = int.parse(match.group(4)!);
        
        await _serveTile(request, dataset, z, x, y);
      } else {
        // Handle other requests (styles, sprites, etc.)
        await _serveOtherResource(request);
      }
    } catch (e) {
      print('Error handling request ${request.uri}: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  /// Serve the proxy style JSON
  Future<void> _serveProxyStyle(HttpRequest request) async {
    try {
      final proxyUrl = 'http://localhost:$_port';
      final style = await generateProxyStyleFromOriginal(proxyUrl);
      
      request.response.headers.set('Content-Type', 'application/json');
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      
      request.response.write(jsonEncode(style));
      await request.response.close();
      
      print('📄 Served proxy style JSON');
    } catch (e) {
      print('❌ Error serving proxy style: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  /// Serve a map tile with caching
  Future<void> _serveTile(HttpRequest request, String dataset, int z, int x, int y) async {
    try {
      final originalUrl = '$_baseUrl/$dataset/$z/$x/$y.mvt?token=$_token';
      
      // Check cache first
      Uint8List? tileData;
      bool fromCache = false;
      
      if (_cacheManager != null) {
        tileData = await _cacheManager!.getTile(originalUrl);
        if (tileData != null && tileData.isNotEmpty) {
          fromCache = true;
          _cachedResponses++;
          print('🎯 Serving cached tile $z/$x/$y (${tileData.length} bytes)');
        } else if (tileData != null && tileData.isEmpty) {
          // Don't serve empty tiles, fetch fresh ones
          tileData = null;
          print('💾 Cached tile $z/$x/$y is empty, fetching fresh');
        }
      }
      
      // If not in cache, fetch from server
      if (tileData == null) {
        print('📡 Fetching tile $z/$x/$y from server...');
        final response = await http.get(
          Uri.parse(originalUrl),
          headers: {
            'User-Agent': 'MapMetrics-Flutter-Cache-Proxy/1.0',
            'Accept': 'application/x-protobuf',
          },
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          tileData = response.bodyBytes;
          print('✅ Downloaded tile $z/$x/$y (${tileData.length} bytes)');
        } else {
          print('❌ Failed to fetch tile $z/$x/$y: ${response.statusCode} (${response.bodyBytes.length} bytes)');
          request.response.statusCode = response.statusCode == 200 ? 404 : response.statusCode;
          await request.response.close();
          return;
        }
      }
      
      // Serve the tile only if we have valid data
      if (tileData != null && tileData.isNotEmpty) {
        request.response.headers.set('Content-Type', 'application/x-protobuf');
        request.response.headers.set('Content-Length', tileData.length);
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        request.response.headers.set('X-Cache-Status', fromCache ? 'HIT' : 'MISS');
        request.response.headers.set('X-Tile-Coords', '$z/$x/$y');
        
        request.response.add(tileData);
        await request.response.close();
      } else {
        print('❌ No valid tile data to serve for $z/$x/$y');
        request.response.statusCode = 404;
        await request.response.close();
      }
      
      // Log cache statistics periodically
      if (_totalRequests % 50 == 0) {
        final hitRate = _totalRequests > 0 ? (_cachedResponses / _totalRequests * 100) : 0;
        print('📊 Tile Proxy Stats: $_totalRequests requests, $_cachedResponses cached (${hitRate.toStringAsFixed(1)}% hit rate)');
      }
      
    } catch (e) {
      print('Error serving tile $z/$x/$y: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  /// Handle non-tile requests (styles, sprites, etc.)
  Future<void> _serveOtherResource(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final queryString = request.uri.query.isNotEmpty ? '?${request.uri.query}' : '';
      final originalUrl = '$_baseUrl$path$queryString';
      
      print('🔄 Proxying request: $originalUrl');
      
      // Forward the request to the original server
      final response = await http.get(
        Uri.parse(originalUrl),
        headers: {
          'User-Agent': 'MapMetrics-Flutter-Cache-Proxy/1.0',
        },
      ).timeout(const Duration(seconds: 15));
      
      // Forward the response
      request.response.statusCode = response.statusCode;
      
      // Copy headers
      response.headers.forEach((name, value) {
        request.response.headers.add(name, value);
      });
      
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.add(response.bodyBytes);
      await request.response.close();
      
    } catch (e) {
      print('Error proxying request ${request.uri}: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  /// Generate a proxy style by using a cached version or creating a working fallback
  Future<Map<String, dynamic>> generateProxyStyleFromOriginal(String proxyUrl) async {
    // For now, use a working fallback style with better colors that match MapMetrics
    // This avoids network issues when fetching the original style
    print('🎨 Using optimized cached style');
    return _getOptimizedStyle(proxyUrl);
  }
  
  /// Optimized style that closely matches MapMetrics appearance
  Map<String, dynamic> _getOptimizedStyle(String proxyUrl) {
    return {
      "version": 8,
      "name": "MapMetrics Cached Style (Optimized)",
      "metadata": {
        "mapmetrics:type": "cached-proxy-optimized"
      },
      "sources": {
        "mapmetrics": {
          "type": "vector",
          "tiles": [
            "$proxyUrl/20250110/{z}/{x}/{y}.mvt"
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
            "background-color": "#f1f2f6"
          }
        },
        {
          "id": "water",
          "type": "fill",
          "source": "mapmetrics",
          "source-layer": "water",
          "paint": {
            "fill-color": "#74b9ff",
            "fill-opacity": 0.8
          }
        },
        {
          "id": "landuse-park",
          "type": "fill",
          "source": "mapmetrics",
          "source-layer": "landuse",
          "filter": ["==", ["get", "class"], "park"],
          "paint": {
            "fill-color": "#a8e6cf",
            "fill-opacity": 0.8
          }
        },
        {
          "id": "landuse-residential",
          "type": "fill",
          "source": "mapmetrics",
          "source-layer": "landuse",
          "filter": ["==", ["get", "class"], "residential"],
          "paint": {
            "fill-color": "#ffeaa7",
            "fill-opacity": 0.3
          }
        },
        {
          "id": "roads-motorway",
          "type": "line",
          "source": "mapmetrics",
          "source-layer": "transportation",
          "filter": ["==", ["get", "class"], "motorway"],
          "paint": {
            "line-color": "#e17055",
            "line-width": [
              "interpolate",
              ["linear"],
              ["zoom"],
              5, 1,
              18, 16
            ]
          }
        },
        {
          "id": "roads-trunk",
          "type": "line", 
          "source": "mapmetrics",
          "source-layer": "transportation",
          "filter": ["==", ["get", "class"], "trunk"],
          "paint": {
            "line-color": "#fdcb6e",
            "line-width": [
              "interpolate",
              ["linear"],
              ["zoom"],
              5, 0.8,
              18, 12
            ]
          }
        },
        {
          "id": "roads-primary",
          "type": "line",
          "source": "mapmetrics",
          "source-layer": "transportation",
          "filter": ["==", ["get", "class"], "primary"],
          "paint": {
            "line-color": "#fab1a0",
            "line-width": [
              "interpolate",
              ["linear"],
              ["zoom"],
              5, 0.6,
              18, 8
            ]
          }
        },
        {
          "id": "roads-other",
          "type": "line",
          "source": "mapmetrics", 
          "source-layer": "transportation",
          "filter": ["all", ["!=", ["get", "class"], "motorway"], ["!=", ["get", "class"], "trunk"], ["!=", ["get", "class"], "primary"]],
          "paint": {
            "line-color": "#ddd",
            "line-width": [
              "interpolate",
              ["linear"],
              ["zoom"],
              5, 0.4,
              18, 4
            ]
          }
        },
        {
          "id": "buildings",
          "type": "fill",
          "source": "mapmetrics",
          "source-layer": "building",
          "minzoom": 14,
          "paint": {
            "fill-color": "#e0e0e0",
            "fill-opacity": 0.6
          }
        }
      ]
    };
  }
  
  /// Fallback style in case original style cannot be fetched
  Map<String, dynamic> _getFallbackStyle(String proxyUrl) {
    return _getOptimizedStyle(proxyUrl);
  }

  /// Get proxy server statistics
  Map<String, dynamic> getProxyStats() {
    final hitRate = _totalRequests > 0 ? (_cachedResponses / _totalRequests * 100) : 0.0;
    return {
      'totalRequests': _totalRequests,
      'cachedResponses': _cachedResponses,
      'hitRate': hitRate,
      'serverUrl': 'http://localhost:$_port',
      'isRunning': _server != null,
    };
  }

  /// Stop the proxy server
  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      print('🛑 Tile proxy server stopped');
    }
  }

  void dispose() {
    stopServer();
  }
}