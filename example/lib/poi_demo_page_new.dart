import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapmetrics/mapmetrics.dart';

/// POI Demo Page - Displays toilet-friendly places using custom icon
/// Uses simplified POI rendering with single custom icon
@immutable
class NewPoiDemoPage extends StatefulWidget {
  const NewPoiDemoPage({super.key});

  static const String route = '/new-poi-demo';

  @override
  State<NewPoiDemoPage> createState() => _NewPoiDemoPageState();
}

class _NewPoiDemoPageState extends State<NewPoiDemoPage> {
  late MapController _mapController;
  late StyleController _styleController;

  @override
  void dispose() {
    super.dispose();
  }

  /// Load custom toilet icon from assets
  Future<void> _loadCustomIcon() async {
    try {
      final data = await rootBundle.load('assets/poi/toilets.jpeg');
      await _styleController.addImage('custom-poi-icon', data.buffer.asUint8List());
      debugPrint('✅ Custom POI icon loaded');
    } catch (e) {
      debugPrint('❌ Error loading custom icon: $e');
      rethrow;
    }
  }

  /// Build POI filter for toilet-friendly places
  /// Includes: restrooms, restaurants, gas stations, retail with toilets
  List<dynamic> _buildPoiFilter() {
    return [
      'any',
      // Always show public restrooms
      ['==', ['get', 'amenity'], 'toilets'],
      // Restaurants and food places
      ['==', ['get', 'amenity'], 'restaurant'],
      ['==', ['get', 'amenity'], 'cafe'],
      ['==', ['get', 'amenity'], 'fast_food'],
      ['==', ['get', 'amenity'], 'bar'],
      ['==', ['get', 'amenity'], 'pub'],
      // Gas stations and truck stops
      ['==', ['get', 'amenity'], 'fuel'],
      ['==', ['get', 'amenity'], 'truck_stop'],
      ['==', ['get', 'amenity'], 'rest_area'],
    ];
  }

  /// Build text color expression based on POI category
  List<dynamic> _buildTextColorExpression() {
    return [
      'case',
      // Restrooms - Blue
      ['==', ['get', 'amenity'], 'toilets'], '#2196F3',
      // Food - Gold
      ['in', ['get', 'amenity'], ['literal', ['restaurant', 'cafe', 'fast_food', 'bar', 'pub']]], '#FFD700',
      // Gas/Fuel - Orange
      ['in', ['get', 'amenity'], ['literal', ['fuel', 'truck_stop', 'charging_station']]], '#FF9800',
      // Retail - Purple
      ['has', 'shop'], '#9B59B6',
      // Default - Gray
      '#666666',
    ];
  }

  /// Setup POI layer with custom icon markers
  Future<void> _setupPoiLayer() async {
    try {
      debugPrint('🔵 Starting POI layer setup...');

      // Wait a bit for style to be ready
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Load custom icon first
      debugPrint('🔵 Loading custom icon...');
      await _loadCustomIcon();

    //  await _loadIconsFromSprite();

      // Add POI source explicitly
      debugPrint('🔵 Adding POI vector source...');
      await _styleController.addSource(
        const VectorSource(
          id: 'poi-source',
          tiles: [
            'https://poi-tile-server-development.jim9710.workers.dev/tiles/{z}/{x}/{y}.mvt',
          ],
          minZoom: 0,
          maxZoom: 14,
        ),
      );
      debugPrint('✅ POI source added!');

      debugPrint('🔵 Adding symbol layer with custom icons (no filter - all POIs)...');

      // Try to remove existing layer if it exists
      try {
        await _styleController.removeLayer('custom-poi-symbols');
        debugPrint('🗑️ Removed existing layer');
      } catch (e) {
        debugPrint('ℹ️ No existing layer to remove: $e');
      }

      // Add POI symbol layer with custom icon for all POIs
      await _styleController.addLayer(
        SymbolStyleLayer(
          id: 'custom-poi-symbols',
          sourceId: 'poi-source',
          minZoom: 8,  // Match poi_demo_page minZoom
          maxZoom: 24,
          // No filter - show all POIs
          layout: {
            'source-layer': 'pois',
            'icon-image': 'custom-poi-icon',
            'icon-size': [
              'interpolate',
              ['linear'],
              ['zoom'],
              8, 0.06,   // Small at zoom 8
              10, 0.09,  // Small at zoom 10
              14, 0.15,
              16, 0.21,  // Larger at zoom 16
              20, 0.3,
            ],
            'icon-allow-overlap': true,  // Allow all POIs to be visible
            'icon-ignore-placement': false,
            'icon-padding': [
              'interpolate',
              ['linear'],
              ['zoom'],
              8, 10,   // More padding at low zoom for spacing
              12, 8,
              16, 5,
              20, 3,
            ],
          },
          paint: {
            'icon-opacity': 1.0,
          },
        ),
      );

      debugPrint('✅ POI layer added successfully!');
    } catch (e) {
      debugPrint('❌ Error setting up POI layer: $e');
      rethrow;
    }
  }

  Future<void> _loadIconsFromSprite() async {
    try {
      // Load the MapLibre sprite.json (generated from symbols.sdf)
      final spriteJsonData = await rootBundle.loadString(
        'assets/poi/poi-sprite.json',
      );
      final spriteJson = jsonDecode(spriteJsonData) as Map<String, dynamic>;

      // Load the PNG sprite sheet
      final pngData = await rootBundle.load('assets/poi/poi-sprite.png');
      final pngBytes = pngData.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final spriteImage = frame.image;

      // Extract and load icons using sprite.json coordinates
      int loadedCount = 0;
      for (final entry in spriteJson.entries) {
        final name = entry.key;
        final iconData = entry.value as Map<String, dynamic>;

        final x = iconData['x'] as int;
        final y = iconData['y'] as int;
        final width = iconData['width'] as int;
        final height = iconData['height'] as int;

        if (width <= 0 || height <= 0) continue;

        // Extract icon from sprite sheet
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final srcRect = Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          width.toDouble(),
          height.toDouble(),
        );
        final dstRect = Rect.fromLTWH(
          0,
          0,
          width.toDouble(),
          height.toDouble(),
        );
        canvas.drawImageRect(spriteImage, srcRect, dstRect, Paint());

        final picture = recorder.endRecording();
        final iconImage = await picture.toImage(width, height);
        final byteData = await iconImage.toByteData(
          format: ui.ImageByteFormat.png,
        );

        if (byteData != null) {
          final iconBytes = byteData.buffer.asUint8List();
          await _styleController.addImage(name, iconBytes);
          loadedCount++;
        }
      }

      print('✅ Successfully loaded $loadedCount POI icons from sprite.json');
      print('ℹ️  Using manual loading for remote style compatibility');
      print(
        '💡 For native sprite loading: add "sprite": "asset://assets/poi/poi-sprite" to style JSON',
      );
    } catch (e, stack) {
      print('Error loading icons from sprite: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }

  /// Handle long press on map to show POI details
  Future<void> _handleLongPress(Position point) async {
    try {
      // Convert geographic position to screen coordinates
      final screenLocation = await _mapController.toScreenLocation(point);

      // Query layers at that location
      final layers = await _mapController.queryLayers(screenLocation);

      debugPrint('🔍 Long press - found ${layers.length} layers at $screenLocation');

      if (layers.isEmpty) {
        debugPrint('  No layers found');
        return;
      }

      // Debug: Show ALL POI amenity types found
      final amenityTypes = <String>{};
      for (var layer in layers) {
        if (layer['layerId'] == 'custom-poi-symbols') {
          final props = layer['properties'] as Map<String, dynamic>?;
          if (props != null && props['amenity'] != null) {
            amenityTypes.add(props['amenity'].toString());
          }
        }
      }
      if (amenityTypes.isNotEmpty) {
        debugPrint('📍 POI amenity types at this location: ${amenityTypes.join(', ')}');
      }

      // Debug: Show ALL data from each layer
      for (var i = 0; i < layers.length; i++) {
        final layer = layers[i];
        debugPrint('═══════════════════════════════════════');
        debugPrint('Layer $i - COMPLETE DATA:');
        debugPrint('$layer');
        debugPrint('═══════════════════════════════════════');
      }

      // Find POI layer data
      Map<String, dynamic>? poiData;
      for (final layer in layers) {
        if (layer['layerId'] == 'custom-poi-symbols') {
          poiData = layer;
          break;
        }
      }

      if (poiData != null) {
        debugPrint('✅ Found POI data: ${poiData['properties']}');
      } else {
        debugPrint('⚠️ No POI layer found in query results');
      }

      if (poiData == null) {
        return;
      }

      final props = poiData['properties'] as Map<String, dynamic>? ?? {};

      debugPrint('📋 POI Properties: $props');

      // Get title - try name, then type
      final name = props['name']?.toString();
      final type = props['amenity']?.toString() ??
          props['shop']?.toString() ??
          props['tourism']?.toString() ??
          'Unknown';
      final title = name ?? type.replaceAll('_', ' ').toUpperCase();

      // Show POI details in dialog
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name != null) _buildDetailRow('Type', type),
                  if (name == null) const Text('(No name available)', style: TextStyle(fontStyle: FontStyle.italic)),
                  const SizedBox(height: 8),
                  if (props['addr:street'] != null || props['addr:city'] != null) ...[
                    const Divider(),
                    const Text('Address:', style: TextStyle(fontWeight: FontWeight.bold)),
                    if (props['addr:street'] != null)
                      Text('  ${props['addr:housenumber'] ?? ''} ${props['addr:street']}'.trim()),
                    if (props['addr:city'] != null)
                      Text('  ${props['addr:postcode'] ?? ''} ${props['addr:city']}'.trim()),
                  ],
                  if (props['phone'] != null || props['contact:phone'] != null)
                    _buildDetailRow('Phone', props['phone'] ?? props['contact:phone']),
                  if (props['website'] != null || props['contact:website'] != null)
                    _buildDetailRow('Website', props['website'] ?? props['contact:website']),
                  if (props['opening_hours'] != null)
                    _buildDetailRow('Hours', props['opening_hours']),
                  if (props['cuisine'] != null)
                    _buildDetailRow('Cuisine', props['cuisine']),
                  if (props['toilets'] != null)
                    _buildDetailRow('Toilets', props['toilets']),
                  if (props['wheelchair'] != null)
                    _buildDetailRow('Wheelchair', props['wheelchair']),
                  if (props['internet_access'] != null)
                    _buildDetailRow('WiFi', props['internet_access']),
                  const Divider(),
                  Text(
                    'Category: ${props['amenity'] ?? props['shop'] ?? props['tourism'] ?? 'N/A'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error handling long press: $e');
    }
  }

  /// Build detail row for POI information
  Widget _buildDetailRow(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value.toString().replaceAll('_', ' ')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POI Finder - Restrooms, Restaurants, Gas, Retail'),
      ),
      body: MapLibreMap(
        options: MapOptions(
          initCenter: Position(4.89, 52.37), // Amsterdam
          initZoom: 14, // Match source maxZoom for optimal POI display
          initStyle: 'https://gateway.mapmetrics-atlas.net/styles/?fileName=dd508822-9502-4ab5-bfe2-5e6ed5809c2d/portal.json&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJkZDUwODgyMi05NTAyLTRhYjUtYmZlMi01ZTZlZDU4MDljMmQiLCJzY29wZSI6WyJtYXBzIiwiYXV0b2NvbXBsZXRlIiwiZ2VvY29kZSIsImRpcmVjdGlvbnMiLCJtYXBfbWF0Y2hpbmciLCJvcHRpbWl6ZSIsIm1hdHJpeCIsImlzb2Nocm9uZSJdLCJpYXQiOjE3NjExNDQ1OTl9.MbfXeBtRpzzaLgcdTE0xzMa-OEemCWNWprEbs1RO2rI',
          //'https://gateway.mapmetrics-atlas.net/styles/?fileName=7c3625ac-1f52-479e-8e6f-12299aae7e87/moon.json&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI3YzM2MjVhYy0xZjUyLTQ3OWUtOGU2Zi0xMjI5OWFhZTdlODciLCJzY29wZSI6WyJtYXBzIl0sImlhdCI6MTc2MDM0MTcwOX0.SKiNhdhqkq0FwzM4tn2Txmajw2YAJth6MQfYkAYPp_E',
        ),
        children: const [
          MapControlButtons(showZoomInOutButton: true,)
        ],
        onMapCreated: (controller) {
          _mapController = controller;
        },
        onStyleLoaded: (styleController) async {
          _styleController = styleController;
          await _setupPoiLayer();
        },
        onEvent: (event) {
          if (event is MapEventLongClick) {
            _handleLongPress(event.point);
          }
        },
      ),
    );
  }
}
