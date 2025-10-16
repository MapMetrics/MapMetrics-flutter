import 'package:flutter/material.dart';
import 'package:maplibre_example/services/poi_config_loader.dart';
import 'package:maplibre_example/services/poi_popup_builder.dart';
import 'package:maplibre_example/services/sprite_sheet_loader.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class LayersPOIVectorPage extends StatefulWidget {
  const LayersPOIVectorPage({super.key});

  static const location = '/layers/poi-vector';

  @override
  State<LayersPOIVectorPage> createState() => _LayersPOIVectorPageState();
}

class _LayersPOIVectorPageState extends State<LayersPOIVectorPage> {
  StyleController? _styleController;
  MapController? _mapController;
  POIRendererConfig? _config;
  bool _loading = true;
  String? _error;
  double _currentZoom = 16;
  int _loadedIconsCount = 0;
  Map<String, dynamic>? _selectedPOI;

  // Instance flag to prevent duplicate setup during hot reload
  bool _poiSetupComplete = false;

  // POI vector tile server URL
  static const String poiTileServerUrl =
      'https://poi-tile-server-development.jim9710.workers.dev/tiles/{z}/{x}/{y}.mvt';

  // MapMetrics style URL
  static const String mapStyleUrl =
      'https://gateway.mapmetrics-atlas.net/styles/?fileName=7c3625ac-1f52-479e-8e6f-12299aae7e87/moon.json&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI3YzM2MjVhYy0xZjUyLTQ3OWUtOGU2Zi0xMjI5OWFhZTdlODciLCJzY29wZSI6WyJtYXBzIl0sImlhdCI6MTc2MDM0MTcwOX0.SKiNhdhqkq0FwzM4tn2Txmajw2YAJth6MQfYkAYPp_E';

  // Sprite sheet URLs
  static const String spriteSheetUrl =
      'https://cdn.mapmetrics-atlas.net/Images/resources-hdpi_clear/symbols.png';
  static const String spriteSdfUrl =
      'https://cdn.mapmetrics-atlas.net/Images/resources-hdpi_clear/symbols.sdf';

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  /// Load POI configuration from CDN
  Future<void> _loadConfiguration() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final config = await POIConfigLoader.loadConfig();

      setState(() {
        _config = config;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load POI configuration: $e';
        _loading = false;
      });
    }
  }

  /// Load multiple POI icons from CDN for different amenity types
  Future<void> _loadPOIIcons(StyleController style) async {
    try {
      debugPrint('Loading POI icons from CDN...');

      // Load sprite sheet and metadata from CDN
      final spriteSheet = await SpriteSheetLoader.loadSpriteSheet(spriteSheetUrl);
      final spriteMetadata = await SpriteSheetLoader.loadSDF(spriteSdfUrl);

      // Define POI types and their corresponding icon names
      final iconMappings = {
        'restaurant': 'restaurant-m',
        'cafe': 'cafe-m',
        'bar': 'bar-m',
        'pub': 'bar-m',  // Use bar-m for pubs (no pub-m icon)
        'fast_food': 'fastfood-m',  // FIXED: was 'fast-food-m'
        'hotel': 'hotel-m',
        'hostel': 'hostel-m',
        'motel': 'hotel-m',  // Use hotel-m for motels (no motel-m icon)
        'shop': 'shop-m',
        'supermarket': 'supermarket-m',
        'convenience': 'convenience-m',
        'pharmacy': 'pharmacy-m',
        'hospital': 'hospital-m',
        'clinic': 'hospital-m',  // Use hospital-m for clinics (no clinic-m icon)
        'bank': 'bank-m',
        'atm': 'atm-m',
        'fuel': 'fuel-m',
        'parking': 'parking-m',
        'bus_station': 'bus-m',
        'train_station': 'train-m',
        'subway': 'subway-m',
        'airport': 'airport-m',
        'museum': 'museum-m',
        'theatre': 'theatre-m',
        'cinema': 'cinema-m',
        'library': 'library-m',
        'school': 'school-m',
        'university': 'college-m',  // FIXED: was 'university-m' (use college-m)
        'police': 'police-m',
        'fire_station': 'fire_station-m',  // FIXED: was 'fire-station-m'
        'post_office': 'postbox-m',  // FIXED: was 'post-office-m'
        'place_of_worship': 'place-of-worship-m',
        'tourism': 'tourism-m',
        'attraction': 'tourism-m',  // Use tourism-m for attractions (no attraction-m icon)
        'viewpoint': 'viewpoint-m',
        'bench': 'tourism-m',  // Use tourism-m for benches (no bench-m icon)
      };

      int loadedCount = 0;
      int failedCount = 0;

      // Load each icon
      for (final entry in iconMappings.entries) {
        final amenityType = entry.key;
        final iconName = entry.value;

        final sprite = spriteMetadata[iconName];
        if (sprite != null && sprite.isValid) {
          try {
            final iconBytes = await SpriteSheetLoader.extractSprite(spriteSheet, sprite);
            await style.addImage(iconName, iconBytes);
            loadedCount++;
            debugPrint('✓ Added $iconName icon for $amenityType (${iconBytes.length} bytes)');
          } catch (e) {
            failedCount++;
            debugPrint('✗ Error adding $iconName: $e');
          }
        } else {
          failedCount++;
          debugPrint('✗ Icon not found in sprite sheet: $iconName');
        }
      }

      setState(() {
        _loadedIconsCount = loadedCount;
      });

      debugPrint('Icon loading complete: $loadedCount loaded, $failedCount failed');
    } catch (e) {
      debugPrint('Error loading POI icons: $e');
    }
  }

  /// Load and process sprite sheet
  Future<void> _loadSpriteSheet(StyleController style) async {
    if (_config == null) return;

    try {
      debugPrint('Loading sprite sheet from CDN...');

      // Load sprite sheet image (PNG) from CDN
      final spriteSheet = await SpriteSheetLoader.loadSpriteSheet(spriteSheetUrl);

      // Load sprite metadata (SDF XML format) from CDN
      final spriteMetadata = await SpriteSheetLoader.loadSDF(spriteSdfUrl);

      // Process sprite sheet and extract all sprites
      final sprites = await SpriteSheetLoader.processSpriteSheet(
        spriteSheet: spriteSheet,
        metadata: spriteMetadata,
        skipPatterns: _config!.skipPatterns,
        onProgress: (count, total) {
          // Update progress
          debugPrint('Processed $count/$total sprites');
        },
      );

      // Add all extracted sprites to the map
      debugPrint('Adding ${sprites.length} sprites to MapLibre...');
      int successCount = 0;
      int failCount = 0;

      for (final entry in sprites.entries) {
        final name = entry.key;
        final imageBytes = entry.value;

        try {
          await style.addImage(name, imageBytes);
          successCount++;

          // Log specifically for our test icon
          if (name == 'bench-m' || name == 'bench' || name == 'tourism-m' || name == 'tourism') {
            debugPrint('✓ Added test icon: $name (${imageBytes.length} bytes)');
          }
        } catch (e) {
          failCount++;
          debugPrint('✗ Error adding sprite $name: $e');
        }
      }

      setState(() {
        _loadedIconsCount = sprites.length;
      });

      debugPrint('Sprite sheet complete: $successCount added, $failCount failed');
      debugPrint('=== SPRITE AVAILABILITY CHECK ===');
      debugPrint('bench-m available: ${sprites.containsKey("bench-m")}');
      debugPrint('bench available: ${sprites.containsKey("bench")}');
      debugPrint('restaurant-m available: ${sprites.containsKey("restaurant-m")}');
      debugPrint('cafe-m available: ${sprites.containsKey("cafe-m")}');
      debugPrint('shop-m available: ${sprites.containsKey("shop-m")}');
      debugPrint('tourism-m available: ${sprites.containsKey("tourism-m")}');
      debugPrint('tourism available: ${sprites.containsKey("tourism")}');
      debugPrint('First 10 loaded sprites: ${sprites.keys.take(10).toList()}');
    } catch (e) {
      debugPrint('Error loading sprite sheet: $e');
      // Continue anyway - POIs will use fallback icon if available
    }
  }

  /// Add POI vector tile source to the map
  Future<void> _addPOISource(StyleController style) async {
    try {
      debugPrint('Adding POI vector tile source...');
      debugPrint('POI Tile URL: $poiTileServerUrl');
      debugPrint('IMPORTANT: Zoom to level 10-16 to see POI data!');

      // Add vector tile source from POI tile server
      await style.addSource(
        VectorSource(
          id: 'pois',
          tiles: const [poiTileServerUrl],
          minZoom: 10,  // Server minimum zoom level
          maxZoom: 16,  // Server maximum zoom level (tile server only generates up to zoom 16)
        ),
      );

      debugPrint('POI source added successfully');
    } catch (e) {
      // Check if error is about duplicate source
      if (e.toString().contains('already exists') || e.toString().contains('Redundant')) {
        debugPrint('⚠️ POI source already exists, skipping...');
        return; // Don't rethrow, just skip
      }
      debugPrint('Error adding POI source: $e');
      rethrow;
    }
  }

  /// Build icon expression for dynamic icon mapping
  /// Uses the POI config's buildIconExpression() to create MapLibre expressions
  /// On iOS, uses simplified case expression without nested ['all', ...] operators
  dynamic _buildIconExpression() {
    if (_config == null) {
      return 'tourism-m';  // Simple constant fallback
    }

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // iOS can handle case expressions but not complex nested ['all', ...] operators
      // Use the iOS-specific builder that generates a flatter expression tree
      debugPrint('📱 iOS: Using iOS-compatible case expression for dynamic icons');
      return _config!.buildIconExpressionIOS();
    }

    // Use the config's buildIconExpression() method to generate
    // the complete MapLibre expression for dynamic icon mapping (including religion-based icons)
    return _config!.buildIconExpression();
  }

  /// Add test circle layer to visualize all POI locations
  Future<void> _addTestCircleLayer(StyleController style) async {
    try {
      debugPrint('=== ADDING POI CIRCLE LAYER ===');
      debugPrint('Source ID: pois');
      debugPrint('Source layer: pois');
      debugPrint('Current zoom: $_currentZoom');

      // Add circle layer with source-layer in layout (not paint)
      // Use zoom-based interpolation so circles scale with zoom level
      await style.addLayer(
        CircleStyleLayer(
          id: 'poi-test-circles',
          sourceId: 'pois',
          layout: {
            'source-layer': 'pois',  // Specify which layer in the vector tile
          },
          paint: {
            // Scale circle radius based on zoom level
            // At zoom 10: 6px, at zoom 16: 10px, at zoom 22: 14px
            'circle-radius': <Object>[
              'interpolate',
              <Object>['linear'],
              <Object>['zoom'],
              10, 6,   // zoom 10: 6px radius
              13, 8,   // zoom 13: 8px radius
              16, 10,  // zoom 16: 10px radius
              19, 12,  // zoom 19: 12px radius
              22, 14,  // zoom 22: 14px radius
            ],
            'circle-color': '#FF0000',  // Bright red
            'circle-opacity': 1.0,  // Fully opaque
            'circle-stroke-width': 3,
            'circle-stroke-color': '#FFFF00',  // YELLOW outline for max contrast
            'circle-stroke-opacity': 1.0,
          },
        ),
      );

      debugPrint('=== POI CIRCLE LAYER ADDED SUCCESSFULLY ===');
      debugPrint('Circles should be HUGE red dots with yellow outlines');
      debugPrint('Make sure you are zoomed to level 10-16!');
      debugPrint('If you don\'t see them, POI data is not loading from tiles');
    } catch (e) {
      debugPrint('!!! ERROR adding circle layer: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Add POI layer with dynamic icon mapping based on amenity type
  Future<void> _addPOILayer(StyleController style) async {
    try {
      debugPrint('=== ADDING POI ICON LAYER (DYNAMIC) ===');

      // Get the dynamic icon expression from config (checks ALL properties: amenity, shop, tourism, etc.)
      final iconExpression = _buildIconExpression();

      debugPrint('Icon expression type: ${iconExpression.runtimeType}');
      debugPrint('Icon expression value: $iconExpression');

      // On iOS, use simpler constant size to avoid expression parsing issues
      final dynamic iconSizeValue;
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        iconSizeValue = 2.0;  // Simple constant size
        debugPrint('📱 iOS: Using constant icon size: $iconSizeValue');
      } else {
        // Get icon size configuration from config and make icons 4x bigger
        final baseIconSizeExpression = _config?.iconConfig.toIconSizeExpression() ?? ['literal', 1.0];

        // Multiply all size values by 4.0 to make icons much bigger
        final iconSizeExpression = <Object>['interpolate', <Object>['linear'], <Object>['zoom']];
        if (baseIconSizeExpression is List && baseIconSizeExpression.length > 3) {
          for (var i = 3; i < baseIconSizeExpression.length; i += 2) {
            iconSizeExpression.add(baseIconSizeExpression[i] as Object); // zoom level
            final size = baseIconSizeExpression[i + 1];
            iconSizeExpression.add((size is num ? size * 4.0 : size) as Object); // size * 4.0
          }
        } else {
          // Fallback if config expression is invalid
          iconSizeExpression.addAll(<Object>[10, 1.2, 12, 1.6, 14, 2.0, 16, 2.8, 18, 3.6, 20, 4.4]);
        }
        iconSizeValue = iconSizeExpression;
      }

      debugPrint('Creating SymbolStyleLayer with icon mapping...');

      await style.addLayer(
        SymbolStyleLayer(
          id: 'poi-icons',
          sourceId: 'pois',
          minZoom: 8,  // Show icons starting at zoom level 8 (lowered from 10 for more visibility)
          // maxZoom removed - let iOS use its default max zoom (22)
          layout: <String, Object>{
            'source-layer': 'pois',  // Specify which layer in the vector tile
            'icon-image': iconExpression as Object,  // Dynamic icon from config (checks amenity, shop, tourism, etc.)
            'icon-size': iconSizeValue as Object,  // Size based on platform
            'icon-allow-overlap': true,  // Allow icons to overlap each other
            'icon-ignore-placement': true,  // Don't hide icons when they collide with other symbols
          },
        ),
      );

      debugPrint('=== POI ICON LAYER ADDED SUCCESSFULLY ===');
      debugPrint('Dynamic icon mapping enabled for $_loadedIconsCount icon types');
      debugPrint('Icon expression checks: amenity, shop, tourism, leisure, sport, office, craft, healthcare, historic, natural, aeroway, railway, highway, public_transport, man_made, emergency, barrier, power');
    } catch (e) {
      // Check if error is about duplicate layer
      if (e.toString().contains('already exists') || e.toString().contains('Redundant')) {
        debugPrint('⚠️ POI layer already exists, skipping...');
        return; // Don't rethrow, just skip
      }
      debugPrint('!!! ERROR adding POI icon layer: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Handle click events and query for POI features with properties
  Future<void> _handleMapClick(Position position) async {
    if (_mapController == null || _styleController == null) return;

    try {
      debugPrint('=== POI CLICK DEBUG ===');
      debugPrint('Click position: lng=${position.lng}, lat=${position.lat}');

      // Convert the clicked position to screen coordinates
      final screenLocation = await _mapController!.toScreenLocation(position);
      debugPrint('Screen location: dx=${screenLocation.dx}, dy=${screenLocation.dy}');

      // Query for POI features with properties using the new API
      final features = await _mapController!.queryFeatures(
        screenLocation,
        ['poi-icons'], // Query the POI icons layer
      );

      if (features.isNotEmpty) {
        final poi = features.first;
        debugPrint('✓ POI CLICKED!');
        debugPrint('  Layer: ${poi.layerId}');
        debugPrint('  Properties:');

        // Log all available properties
        poi.properties.forEach((key, value) {
          debugPrint('    $key: $value');
        });

        // Highlight specific important properties
        debugPrint('');
        debugPrint('=== KEY POI INFORMATION ===');
        if (poi.properties['name'] != null) {
          debugPrint('  Name: ${poi.properties['name']}');
        }
        if (poi.properties['amenity'] != null) {
          debugPrint('  Amenity: ${poi.properties['amenity']}');
        }
        if (poi.properties['opening_hours'] != null) {
          debugPrint('  Opening Hours: ${poi.properties['opening_hours']}');
        }
        if (poi.properties['addr:street'] != null || poi.properties['addr:city'] != null) {
          final street = poi.properties['addr:street'] ?? '';
          final city = poi.properties['addr:city'] ?? '';
          final postcode = poi.properties['addr:postcode'] ?? '';
          debugPrint('  Address: $street, $city $postcode');
        }
        if (poi.properties['phone'] != null) {
          debugPrint('  Phone: ${poi.properties['phone']}');
        }
        if (poi.properties['website'] != null) {
          debugPrint('  Website: ${poi.properties['website']}');
        }

        // Store selected POI for popup display
        setState(() {
          _selectedPOI = poi.properties;
        });
      } else {
        debugPrint('No POI clicked at this location');
      }

      debugPrint('=====================');
    } catch (e) {
      debugPrint('Error handling map click: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  /// Close POI popup
  void _closePopup() {
    setState(() {
      _selectedPOI = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POI Vector Tiles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConfiguration,
            tooltip: 'Reload Configuration',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading POI configuration...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadConfiguration,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    MapLibreMap(
                      options: MapOptions(
                        initZoom: _currentZoom,
                        initCenter: Position(5.472009, 51.451771),
                        initStyle: mapStyleUrl,
                      ),
                      onStyleLoaded: (style) async {
                        // Prevent duplicate setup if style is reloaded
                        if (_poiSetupComplete) {
                          debugPrint('⚠️ Style already loaded, skipping POI setup');
                          return;
                        }

                        _styleController = style;
                        debugPrint('=== STYLE LOADED - STARTING POI SETUP ===');

                        try {
                          await _loadSpriteSheet(style);  // Load ALL sprites from sprite sheet
                          await _addPOISource(style);
                          // await _addTestCircleLayer(style);  // Debug circles - DISABLED
                          await _addPOILayer(style);  // Icon layer with dynamic mapping

                          _poiSetupComplete = true; // Mark setup as complete
                          debugPrint('=== POI SETUP COMPLETE ===');
                        } catch (e) {
                          debugPrint('❌ POI SETUP FAILED: $e');
                          debugPrint('Stack trace: ${StackTrace.current}');
                          // Don't mark as complete so it can retry
                        }
                      },
                      onEvent: (event) {
                        if (event is MapEventMapCreated) {
                          // Store the map controller for feature querying
                          _mapController = event.mapController;
                          debugPrint('MapController created and stored');
                        } else if (event is MapEventMoveCamera) {
                          setState(() {
                            _currentZoom = event.camera.zoom;
                          });
                        } else if (event is MapEventClick) {
                          // Handle POI click
                          _handleMapClick(event.point);
                        }
                      },
                    ),
                    // Info panel
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Zoom: ${_currentZoom.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Icons loaded: $_loadedIconsCount',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Legend
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'POI VECTOR TILES',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '• Multiple icon types',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '• ${_loadedIconsCount} icons loaded',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const Text(
                              '• Zoom 10-16 for data',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // POI popup overlay
                    if (_selectedPOI != null && _config != null)
                      Positioned(
                        top: MediaQuery.of(context).size.height / 2 - 100,
                        left: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: _closePopup,
                          child: POIPopupBuilder.buildPopup(
                            properties: _selectedPOI!,
                            config: _config!,
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
