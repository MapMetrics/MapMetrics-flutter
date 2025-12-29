import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

/// Manages tile caching to reduce server load by storing downloaded tiles locally
class TileCacheManager {
  static TileCacheManager? _instance;
  static const String _cacheKeyPrefix = 'tile_cache_';
  static const String _cacheStatsKey = 'tile_cache_stats';
  static const int _maxCacheSizeMB = 100; // 100MB cache limit
  static const int _maxCacheAgeHours = 24; // 24 hours cache expiration
  
  Directory? _cacheDirectory;
  SharedPreferences? _prefs;
  final Map<String, CachedTile> _memoryCache = {};
  late final http.Client _httpClient;
  
  // Cache statistics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _networkRequests = 0;
  
  TileCacheManager._internal() {
    _httpClient = http.Client();
  }
  
  static Future<TileCacheManager> getInstance() async {
    _instance ??= TileCacheManager._internal();
    await _instance!._initialize();
    return _instance!;
  }
  
  Future<void> _initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Get cache directory
      final appDir = await getApplicationSupportDirectory();
      _cacheDirectory = Directory('${appDir.path}/tile_cache');
      
      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
      }
      
      await _loadCacheStats();
      await _cleanupExpiredTiles();
      
      if (kDebugMode) {
        print('TileCacheManager initialized');
        print('Cache directory: ${_cacheDirectory!.path}');
        print('Cache stats - Hits: $_cacheHits, Misses: $_cacheMisses, Network: $_networkRequests');
      }
    } catch (e) {
      if (kDebugMode) {
        print('TileCacheManager initialization error: $e');
      }
    }
  }
  
  /// Fetches a tile with caching logic
  Future<Uint8List?> getTile(String tileUrl) async {
    final tileKey = _generateTileKey(tileUrl);
    
    try {
      // 1. Check memory cache first (fastest)
      if (_memoryCache.containsKey(tileKey)) {
        final cachedTile = _memoryCache[tileKey]!;
        if (!cachedTile.isExpired()) {
          _cacheHits++;
          await _updateCacheStats();
          return cachedTile.data;
        } else {
          _memoryCache.remove(tileKey);
        }
      }
      
      // 2. Check disk cache
      final diskCacheData = await _getDiskCachedTile(tileKey);
      if (diskCacheData != null) {
        // Add to memory cache for faster access
        _memoryCache[tileKey] = CachedTile(
          data: diskCacheData,
          timestamp: DateTime.now(),
        );
        _cacheHits++;
        await _updateCacheStats();
        return diskCacheData;
      }
      
      // 3. Cache miss - fetch from network
      _cacheMisses++;
      _networkRequests++;
      await _updateCacheStats();
      
      if (kDebugMode) {
        print('Fetching tile from network: $tileUrl');
      }
      
      return await _fetchAndCacheTile(tileUrl, tileKey);
      
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching tile $tileUrl: $e');
      }
      return null;
    }
  }
  
  Future<Uint8List?> _fetchAndCacheTile(String tileUrl, String tileKey) async {
    try {
      final response = await _httpClient.get(
        Uri.parse(tileUrl),
        headers: {
          'User-Agent': 'MapMetrics-Flutter-Cache/1.0',
          'Accept': 'image/png,image/jpeg,image/webp,*/*',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final tileData = response.bodyBytes;
        
        // Cache the tile both in memory and disk
        final cachedTile = CachedTile(
          data: tileData,
          timestamp: DateTime.now(),
        );
        
        _memoryCache[tileKey] = cachedTile;
        await _saveTileToDisk(tileKey, cachedTile);
        
        if (kDebugMode) {
          print('Cached tile: $tileKey (${tileData.length} bytes)');
        }
        
        return tileData;
      } else {
        if (kDebugMode) {
          print('Failed to fetch tile: ${response.statusCode}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Network error fetching tile: $e');
      }
      return null;
    }
  }
  
  Future<Uint8List?> _getDiskCachedTile(String tileKey) async {
    try {
      if (_cacheDirectory == null) return null;
      
      final file = File('${_cacheDirectory!.path}/$tileKey.tile');
      final metaFile = File('${_cacheDirectory!.path}/$tileKey.meta');
      
      if (await file.exists() && await metaFile.exists()) {
        final metaContent = await metaFile.readAsString();
        final meta = jsonDecode(metaContent) as Map<String, dynamic>;
        final timestamp = DateTime.parse(meta['timestamp'] as String);
        
        // Check if tile is still valid
        if (DateTime.now().difference(timestamp).inHours < _maxCacheAgeHours) {
          return await file.readAsBytes();
        } else {
          // Delete expired tile
          await file.delete();
          await metaFile.delete();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error reading cached tile: $e');
      }
    }
    
    return null;
  }
  
  Future<void> _saveTileToDisk(String tileKey, CachedTile tile) async {
    try {
      if (_cacheDirectory == null) return;
      
      final file = File('${_cacheDirectory!.path}/$tileKey.tile');
      final metaFile = File('${_cacheDirectory!.path}/$tileKey.meta');
      
      // Write tile data
      await file.writeAsBytes(tile.data);
      
      // Write metadata
      final meta = {
        'timestamp': tile.timestamp.toIso8601String(),
        'size': tile.data.length,
      };
      await metaFile.writeAsString(jsonEncode(meta));
      
      // Check cache size and cleanup if needed
      await _manageCacheSize();
      
    } catch (e) {
      if (kDebugMode) {
        print('Error saving tile to disk: $e');
      }
    }
  }
  
  String _generateTileKey(String tileUrl) {
    // Create a unique key from the tile URL
    // Remove protocol and special characters for file system compatibility
    final cleanUrl = tileUrl.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return cleanUrl.length > 200 ? cleanUrl.hashCode.toString() : cleanUrl;
  }
  
  Future<void> _cleanupExpiredTiles() async {
    try {
      if (_cacheDirectory == null) return;
      
      final files = await _cacheDirectory!.list().toList();
      final now = DateTime.now();
      int cleanedCount = 0;
      
      for (final file in files) {
        if (file is File && file.path.endsWith('.meta')) {
          try {
            final content = await file.readAsString();
            final meta = jsonDecode(content) as Map<String, dynamic>;
            final timestamp = DateTime.parse(meta['timestamp'] as String);
            
            if (now.difference(timestamp).inHours > _maxCacheAgeHours) {
              final tileKey = file.path.split('/').last.replaceAll('.meta', '');
              final tileFile = File('${_cacheDirectory!.path}/$tileKey.tile');
              
              await file.delete();
              if (await tileFile.exists()) {
                await tileFile.delete();
              }
              cleanedCount++;
            }
          } catch (e) {
            // Delete corrupted meta files
            await file.delete();
          }
        }
      }
      
      if (kDebugMode && cleanedCount > 0) {
        print('Cleaned up $cleanedCount expired tiles');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error cleaning up cache: $e');
      }
    }
  }
  
  Future<void> _manageCacheSize() async {
    try {
      if (_cacheDirectory == null) return;
      
      final files = await _cacheDirectory!.list().toList();
      int totalSize = 0;
      final List<FileInfo> tileFiles = [];
      
      // Calculate total cache size
      for (final file in files) {
        if (file is File && file.path.endsWith('.tile')) {
          final stat = await file.stat();
          totalSize += stat.size;
          tileFiles.add(FileInfo(file, stat.modified, stat.size));
        }
      }
      
      final maxSizeBytes = _maxCacheSizeMB * 1024 * 1024;
      
      if (totalSize > maxSizeBytes) {
        // Sort by last modified (oldest first)
        tileFiles.sort((a, b) => a.lastModified.compareTo(b.lastModified));
        
        int deletedSize = 0;
        int deletedCount = 0;
        
        for (final fileInfo in tileFiles) {
          if (totalSize - deletedSize <= maxSizeBytes * 0.8) break; // Keep 20% buffer
          
          final tileKey = fileInfo.file.path.split('/').last.replaceAll('.tile', '');
          final metaFile = File('${_cacheDirectory!.path}/$tileKey.meta');
          
          await fileInfo.file.delete();
          if (await metaFile.exists()) {
            await metaFile.delete();
          }
          
          deletedSize += fileInfo.size;
          deletedCount++;
          
          // Remove from memory cache too
          _memoryCache.remove(tileKey);
        }
        
        if (kDebugMode && deletedCount > 0) {
          print('Cache cleanup: deleted $deletedCount tiles (${(deletedSize / 1024 / 1024).toStringAsFixed(1)} MB)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error managing cache size: $e');
      }
    }
  }
  
  Future<void> _loadCacheStats() async {
    try {
      if (_prefs == null) return;
      
      final statsJson = _prefs!.getString(_cacheStatsKey);
      if (statsJson != null) {
        final stats = jsonDecode(statsJson) as Map<String, dynamic>;
        _cacheHits = (stats['hits'] as int?) ?? 0;
        _cacheMisses = (stats['misses'] as int?) ?? 0;
        _networkRequests = (stats['networkRequests'] as int?) ?? 0;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading cache stats: $e');
      }
    }
  }
  
  Future<void> _updateCacheStats() async {
    try {
      if (_prefs == null) return;
      
      final stats = {
        'hits': _cacheHits,
        'misses': _cacheMisses,
        'networkRequests': _networkRequests,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      await _prefs!.setString(_cacheStatsKey, jsonEncode(stats));
    } catch (e) {
      if (kDebugMode) {
        print('Error updating cache stats: $e');
      }
    }
  }
  
  /// Get cache statistics for display
  Map<String, dynamic> getCacheStats() {
    final total = _cacheHits + _cacheMisses;
    final hitRate = total > 0 ? (_cacheHits / total * 100) : 0.0;
    
    return {
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'networkRequests': _networkRequests,
      'hitRate': hitRate,
      'totalTilesInMemory': _memoryCache.length,
      'cacheDirectory': _cacheDirectory?.path ?? 'Not available',
    };
  }
  
  /// Clear all cached tiles
  Future<void> clearCache() async {
    try {
      _memoryCache.clear();
      
      if (_cacheDirectory != null && await _cacheDirectory!.exists()) {
        await _cacheDirectory!.delete(recursive: true);
        await _cacheDirectory!.create(recursive: true);
      }
      
      _cacheHits = 0;
      _cacheMisses = 0;
      _networkRequests = 0;
      await _updateCacheStats();
      
      if (kDebugMode) {
        print('Cache cleared successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing cache: $e');
      }
    }
  }
  
  /// Preload tiles for a specific area
  Future<void> preloadTilesForArea({
    required double centerLat,
    required double centerLng,
    required int zoomLevel,
    required int radiusTiles,
    required String baseUrl,
  }) async {
    try {
      final centerX = _lngToTileX(centerLng, zoomLevel);
      final centerY = _latToTileY(centerLat, zoomLevel);
      
      final List<Future<void>> preloadTasks = [];
      
      for (int x = centerX - radiusTiles; x <= centerX + radiusTiles; x++) {
        for (int y = centerY - radiusTiles; y <= centerY + radiusTiles; y++) {
          if (x >= 0 && y >= 0 && x < (1 << zoomLevel) && y < (1 << zoomLevel)) {
            final tileUrl = baseUrl.replaceAll('{z}', zoomLevel.toString())
                                 .replaceAll('{x}', x.toString())
                                 .replaceAll('{y}', y.toString());
            
            preloadTasks.add(getTile(tileUrl).then((_) {}));
          }
        }
      }
      
      await Future.wait(preloadTasks);
      
      if (kDebugMode) {
        print('Preloaded ${preloadTasks.length} tiles for area');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error preloading tiles: $e');
      }
    }
  }
  
  int _lngToTileX(double lng, int zoom) {
    return ((lng + 180.0) / 360.0 * (1 << zoom)).floor();
  }
  
  int _latToTileY(double lat, int zoom) {
    final latRad = lat * (math.pi / 180.0);
    return ((1.0 - (math.log(math.tan(latRad) + 1 / math.cos(latRad))) / math.pi) / 2.0 * (1 << zoom)).floor();
  }
  
  void dispose() {
    _httpClient.close();
  }
}

class CachedTile {
  final Uint8List data;
  final DateTime timestamp;
  
  CachedTile({
    required this.data,
    required this.timestamp,
  });
  
  bool isExpired() {
    return DateTime.now().difference(timestamp).inHours > TileCacheManager._maxCacheAgeHours;
  }
}

class FileInfo {
  final File file;
  final DateTime lastModified;
  final int size;
  
  FileInfo(this.file, this.lastModified, this.size);
}