import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_example/reverse_geocoding_list_page.dart';
import 'package:mapmetrics/mapmetrics.dart';

/// Restroom Finder Page - Displays restroom-friendly places using custom icon
/// Shows: toilets, restaurants, cafes, bars, hotels, gas stations, malls, and places with toilets=yes/public
class NewPoiDemoPage extends StatefulWidget {
  const NewPoiDemoPage({super.key});

  static const String route = '/restroom-finder';

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

  /// Load custom restroom icon from assets
  Future<void> _loadCustomIcon() async {
    try {
      final data = await rootBundle.load('assets/poi/restroom_icon.png');
      await _styleController.addImage('restroom-icon', data.buffer.asUint8List());
      debugPrint('✅ Restroom icon loaded');
    } catch (e) {
      debugPrint('❌ Error loading restroom icon: $e');
      rethrow;
    }
  }

  /// Build POI filter for restroom-friendly places
  /// Matches web filter logic exactly for consistent POI display
  /// Shows: toilets, restaurants, cafes, bars, pubs, gas stations, highway services, shops with toilets=yes, and any place with toilets=yes/public
  List<dynamic> _buildPoiFilter() {
    return [
      'all',
      // Only show Point geometries (critical for proper rendering)
      [
        '==',
        ['geometry-type'],
        'Point',
      ],
      [
        'any',
        // Direct restroom facilities
        [
          '==',
          ['get', 'amenity'],
          'toilets',
        ],

        // Food & beverage establishments (assumed to have restrooms)
        [
          'in',
          ['get', 'amenity'],
          [
            'literal',
            ['restaurant', 'cafe', 'fast_food', 'bar', 'pub'],
          ],
        ],

        // Fuel & services (gas stations, truck stops, rest areas)
        [
          'in',
          ['get', 'amenity'],
          [
            'literal',
            ['fuel', 'truck_stop', 'rest_area'],
          ],
        ],

        // Hotels and similar (assumed restrooms)
        [
          'in',
          ['get', 'tourism'],
          [
            'literal',
            ['hotel', 'motel', 'hostel', 'guest_house'],
          ],
        ],

        // Malls and large stores (assumed restrooms)
        [
          'in',
          ['get', 'shop'],
          [
            'literal',
            ['mall', 'department_store'],
          ],
        ],

        // Highway rest areas and service areas
        [
          'in',
          ['get', 'highway'],
          [
            'literal',
            ['services', 'rest_area'],
          ],
        ],

        // Retail with toilets (conditional - must have toilets=yes tag)
        [
          'all',
          ['has', 'shop'],
          [
            '==',
            ['get', 'toilets'],
            'yes',
          ],
        ],

        // Any POI explicitly marked with public restrooms
        [
          '==',
          ['get', 'toilets'],
          'yes',
        ],
        [
          '==',
          ['get', 'toilets'],
          'public',
        ],
      ],
    ];
  }

  /// Setup POI layer with custom restroom icon markers
  Future<void> _setupPoiLayer() async {
    try {
      debugPrint('🔵 Starting POI layer setup...');

      // Wait a bit for style to be ready
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Load custom icon first
      debugPrint('🔵 Loading custom icon...');
      await _loadCustomIcon();

      // Add POI source explicitly
      debugPrint('🔵 Adding POI vector source...');
      await _styleController.addSource(
        const VectorSource(
          id: 'poi-source',
          tiles: ['https://poi-tile-server-development.jim9710.workers.dev/tiles/{z}/{x}/{y}.mvt'],
          minZoom: 10, // Changed from 0 to match web - optimal tile loading
          maxZoom: 16, // Changed from 14 to 16 - tiles available up to zoom 16
        ),
      );
      debugPrint('✅ POI source added!');

      debugPrint('🔵 Adding restroom symbol layer with filter...');

      // Try to remove existing layer if it exists
      try {
        await _styleController.removeLayer('restroom-symbols');
        debugPrint('🗑️ Removed existing layer');
      } catch (e) {
        debugPrint('ℹ️ No existing layer to remove: $e');
      }

      // Add restroom POI symbol layer with filter
      await _styleController.addLayer(
        SymbolStyleLayer(
          id: 'restroom-symbols',
          sourceId: 'poi-source',
          minZoom: 10,
          // Start showing at zoom 10 to match web behavior
          maxZoom: 24,
          filter: _buildPoiFilter(),
          // Apply restroom-relevant filter
          layout: {
            'source-layer': 'pois',
            'icon-image': 'restroom-icon',
            'icon-size': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10, 0.12, // Small at zoom 10
              12, 0.15,
              14, 0.2,
              16, 0.25,
              18, 0.3, // Larger at zoom 18
              20, 0.35,
            ],
            'icon-allow-overlap': [
              'step',
              ['zoom'],
              false, // No overlap below zoom 16
              16, true, // Allow overlap only at zoom 16+ for dense areas
            ],
            'icon-ignore-placement': [
              'step',
              ['zoom'],
              false, // Respect placement below zoom 16
              16, true, // Ignore placement at zoom 16+ for dense areas
            ],
            'icon-padding': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10, 20, // More padding at low zoom for spacing
              12, 15, // Medium padding at initial load
              14, 10, // Less padding as you zoom in
              16, 8,
              18, 5,
              20, 5,
            ],
            'icon-optional': true, // Don't hide POI if icon is missing
          },
          paint: {
            'icon-opacity': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10, 0.4, // Semi-transparent at zoom 10
              12, 0.6, // Initial load - medium opacity
              14, 0.85, // Getting clearer
              16, 1.0, // Fully opaque at zoom 16+
            ],
          },
        ),
      );

      debugPrint('✅ POI layer added successfully!');
    } catch (e) {
      debugPrint('❌ Error setting up POI layer: $e');
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
        if (layer['layerId'] == 'restroom-symbols') {
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
        if (layer['layerId'] == 'restroom-symbols') {
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
      final type = props['amenity']?.toString() ?? props['shop']?.toString() ?? props['tourism']?.toString() ?? 'Unknown';
      final title = name ?? type.replaceAll('_', ' ').toUpperCase();

      // Show POI details in dialog
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder:
              (context) => AlertDialog(
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
                        if (props['addr:street'] != null) Text('  ${props['addr:housenumber'] ?? ''} ${props['addr:street']}'.trim()),
                        if (props['addr:city'] != null) Text('  ${props['addr:postcode'] ?? ''} ${props['addr:city']}'.trim()),
                      ],
                      if (props['phone'] != null || props['contact:phone'] != null) _buildDetailRow('Phone', props['phone'] ?? props['contact:phone']),
                      if (props['website'] != null || props['contact:website'] != null) _buildDetailRow('Website', props['website'] ?? props['contact:website']),
                      if (props['opening_hours'] != null) _buildDetailRow('Hours', props['opening_hours']),
                      if (props['cuisine'] != null) _buildDetailRow('Cuisine', props['cuisine']),
                      if (props['toilets'] != null) _buildDetailRow('Toilets', props['toilets']),
                      if (props['wheelchair'] != null) _buildDetailRow('Wheelchair', props['wheelchair']),
                      if (props['internet_access'] != null) _buildDetailRow('WiFi', props['internet_access']),
                      const Divider(),
                      Text('Category: ${props['amenity'] ?? props['shop'] ?? props['tourism'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
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
        children: [SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))), Expanded(child: Text(value.toString().replaceAll('_', ' ')))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restroom Finder')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Keep using hardcoded lat/lon from route mapping in main.dart
          Navigator.pushNamed(context, ReverseGeocoadingListPage.route);
        },
        child: const Icon(Icons.place),
      ),
      body: MapLibreMap(
        options: MapOptions(
          initCenter: Position(4.89, 52.37), // Amsterdam
          initZoom: 12, // Wider view - gradual reveal as user zooms in
          initStyle:
            'https://gateway.mapmetrics-atlas.net/styles/?fileName=ed9bb17e-54c0-45c0-bbb4-fbe7c65ae60d/Sayak_app.json&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJlZDliYjE3ZS01NGMwLTQ1YzAtYmJiNC1mYmU3YzY1YWU2MGQiLCJzY29wZSI6WyJtYXBzIiwiZ2VvY29kZSIsImF1dG9jb21wbGV0ZSJdLCJpYXQiOjE3NjMyMjc1Mzh9.nIOQwQd0F8QHjcYz_NsWk0cvSgSskRdH42shqhSelJE',
              // 'https://gateway.mapmetrics-atlas.net/styles/?fileName=dd508822-9502-4ab5-bfe2-5e6ed5809c2d/portal.json&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJkZDUwODgyMi05NTAyLTRhYjUtYmZlMi01ZTZlZDU4MDljMmQiLCJzY29wZSI6WyJtYXBzIiwiYXV0b2NvbXBsZXRlIiwiZ2VvY29kZSIsImRpcmVjdGlvbnMiLCJtYXBfbWF0Y2hpbmciLCJvcHRpbWl6ZSIsIm1hdHJpeCIsImlzb2Nocm9uZSJdLCJpYXQiOjE3NjExNDQ1OTl9.MbfXeBtRpzzaLgcdTE0xzMa-OEemCWNWprEbs1RO2rI',
        ),
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
