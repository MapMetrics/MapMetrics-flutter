import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/tile_cache_manager.dart';
import '../services/tile_proxy_server.dart';

class TileCacheViewModel extends ChangeNotifier {
  // Private fields
  TileCacheManager? _cacheManager;
  TileProxyServer? _proxyServer;
  String? _proxyUrl;
  bool _isInitialized = false;
  Timer? _statsTimer;
  
  // Cache statistics
  Map<String, dynamic> _stats = {};

  // Public getters
  bool get isInitialized => _isInitialized;
  String? get proxyUrl => _proxyUrl;
  Map<String, dynamic> get stats => _stats;
  
  // Computed properties
  double get hitRate => (_stats['hitRate'] as num?)?.toDouble() ?? 0.0;
  int get totalRequests => (_stats['totalRequests'] as int?) ?? 0;
  int get cachedResponses => (_stats['cachedResponses'] as int?) ?? 0;
  int get networkRequests => (_stats['networkRequests'] as int?) ?? 0;
  String get proxyStyleUrl => _proxyUrl != null ? '$_proxyUrl/style.json' : '';

  /// Initialize tile cache system
  Future<void> initialize() async {
    try {
      // Initialize cache manager
      _cacheManager = await TileCacheManager.getInstance();
      
      // Start proxy server
      _proxyServer = await TileProxyServer.getInstance();
      _proxyUrl = await _proxyServer!.startServer();
      
      // Mark as ready
      _isInitialized = true;
      
      // Start stats updates
      _startStatsTimer();
      
      debugPrint('✅ Tile cache system initialized: $_proxyUrl');
      notifyListeners();
      
    } catch (e) {
      debugPrint('❌ Failed to initialize tile cache system: $e');
    }
  }

  /// Start periodic stats updates
  void _startStatsTimer() {
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _updateStats();
    });
    _updateStats(); // Initial update
  }

  /// Update cache statistics
  void _updateStats() {
    if (_cacheManager != null && _proxyServer != null) {
      final cacheStats = _cacheManager!.getCacheStats();
      final proxyStats = _proxyServer!.getProxyStats();
      
      _stats = {
        ...cacheStats,
        ...proxyStats,
      };
      
      notifyListeners();
    }
  }

  /// Clear all caches
  Future<void> clearCache() async {
    if (_cacheManager != null) {
      await _cacheManager!.clearCache();
      _updateStats();
    }
  }

  /// Preload tiles for current area
  Future<void> preloadArea({
    required double centerLat,
    required double centerLng,
    required int zoomLevel,
    int radiusTiles = 3,
  }) async {
    if (_cacheManager != null) {
      await _cacheManager!.preloadTilesForArea(
        centerLat: centerLat,
        centerLng: centerLng,
        zoomLevel: zoomLevel,
        radiusTiles: radiusTiles,
        baseUrl: 'https://gateway.mapmetrics-atlas.net/tiles/{z}/{x}/{y}',
      );
      _updateStats();
    }
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _proxyServer?.dispose();
    _cacheManager?.dispose();
    super.dispose();
  }
}