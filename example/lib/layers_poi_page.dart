import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_example/models/poi_models.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class LayersPOIPage extends StatefulWidget {
  const LayersPOIPage({super.key});

  static const location = '/layers/poi';

  @override
  State<LayersPOIPage> createState() => _LayersPOIPageState();
}

class _LayersPOIPageState extends State<LayersPOIPage> {
  StyleController? _styleController;
  POIConfig? _poiConfig;
  List<POI> _pois = [];
  bool _loading = true;
  String? _error;
  double _currentZoom = 13;
  bool _iconsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPOIConfig();
  }

  /// Load POI configuration from CDN
  Future<void> _loadPOIConfig() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      // For now, use the default config
      // In production, you could fetch from the CDN:
      // final response = await http.get(Uri.parse(
      //   'https://cdn.mapmetrics-atlas.net/Images/poi-config.json'
      // ));
      // final config = json.decode(response.body);

      _poiConfig = POIConfig.defaultConfig();

      // Load sample POI data
      _loadSamplePOIs();

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load POI configuration: $e';
        _loading = false;
      });
    }
  }

  /// Load sample POI data around a location
  void _loadSamplePOIs() {
    // Sample POIs around Zurich, Switzerland
    _pois = [
      POI(
        id: '1',
        name: 'Restaurant Helvetia',
        coordinates: Position(8.541, 47.377),
        type: 'restaurant',
        category: 'amenity',
        description: 'Traditional Swiss cuisine',
        address: 'Stauffacherstrasse 1, 8004 Zürich',
        phone: '+41 44 241 08 08',
        openingHours: 'Mo-Sa 11:00-23:00',
      ),
      POI(
        id: '2',
        name: 'Café Central',
        coordinates: Position(8.540, 47.379),
        type: 'cafe',
        category: 'amenity',
        description: 'Cozy café with great coffee',
        address: 'Central 1, 8001 Zürich',
      ),
      POI(
        id: '3',
        name: 'Swiss National Museum',
        coordinates: Position(8.540, 47.378),
        type: 'museum',
        category: 'tourism',
        description: 'Swiss cultural history and art',
        address: 'Museumstrasse 2, 8001 Zürich',
        website: 'https://www.nationalmuseum.ch',
        openingHours: 'Tu-Su 10:00-17:00',
        wheelchair: 'yes',
      ),
      POI(
        id: '4',
        name: 'Zurich HB Parking',
        coordinates: Position(8.538, 47.378),
        type: 'parking',
        category: 'amenity',
        parking: 'yes',
        fee: 'CHF 4/hour',
      ),
      POI(
        id: '5',
        name: 'Pharmacy Bellevue',
        coordinates: Position(8.545, 47.367),
        type: 'pharmacy',
        category: 'amenity',
        phone: '+41 44 251 00 33',
        openingHours: 'Mo-Fr 08:00-19:00; Sa 09:00-16:00',
      ),
      POI(
        id: '6',
        name: 'Hotel Schweizerhof',
        coordinates: Position(8.538, 47.376),
        type: 'hotel',
        category: 'tourism',
        description: '5-star luxury hotel',
        website: 'https://www.schweizerhof-zuerich.ch',
        phone: '+41 44 218 88 88',
        wheelchair: 'yes',
        parking: 'yes',
      ),
      POI(
        id: '7',
        name: 'Coop Supermarket',
        coordinates: Position(8.542, 47.376),
        type: 'supermarket',
        category: 'shop',
        openingHours: 'Mo-Sa 07:00-22:00; Su 09:00-20:00',
      ),
      POI(
        id: '8',
        name: 'Lindenhof Park',
        coordinates: Position(8.541, 47.373),
        type: 'park',
        category: 'leisure',
        description: 'Historic park with panoramic views',
        access: 'public',
      ),
      POI(
        id: '9',
        name: 'Fitness Studio',
        coordinates: Position(8.543, 47.377),
        type: 'fitness_centre',
        category: 'leisure',
        openingHours: 'Mo-Fr 06:00-22:00; Sa-Su 08:00-20:00',
      ),
      POI(
        id: '10',
        name: 'Central Post Office',
        coordinates: Position(8.539, 47.377),
        type: 'post_office',
        category: 'amenity',
        openingHours: 'Mo-Fr 08:00-18:30; Sa 09:00-16:00',
      ),
    ];
  }

  /// Load POI icons into the map style
  Future<void> _loadPOIIcons(StyleController controller) async {
    if (_iconsLoaded || _poiConfig == null) return;

    try {
      // In a production app, you would load the actual sprite sheet from CDN
      // For this example, we'll use a simple marker icon
      const markerUrl = 'https://upload.wikimedia.org/wikipedia/commons/f/f2/678111-map-marker-512.png';

      final response = await http.get(Uri.parse(markerUrl));
      final bytes = response.bodyBytes;

      // Add the default marker image
      await controller.addImage('marker-m', bytes);

      // In production, you would load all the different POI icons from the sprite sheet
      // For now, we'll just use the same marker for all POIs
      // You could also load different colored markers for different categories

      setState(() {
        _iconsLoaded = true;
      });
    } catch (e) {
      debugPrint('Failed to load POI icons: $e');
    }
  }

  /// Add POI source and layer to the map
  Future<void> _addPOILayer(StyleController controller) async {
    if (_pois.isEmpty || _poiConfig == null) return;

    try {
      // Convert POIs to GeoJSON
      final features = _pois.map((poi) => poi.toGeoJson()).toList();
      final geoJson = {
        'type': 'FeatureCollection',
        'features': features,
      };

      // Add GeoJSON source
      await controller.addSource(
        GeoJsonSource(
          id: 'poi-source',
          data: json.encode(geoJson),
        ),
      );

      // Add symbol layer for POI icons
      final iconSize = _poiConfig!.getIconSize(_currentZoom);
      final allowOverlap = _poiConfig!.shouldAllowOverlap(_currentZoom);

      await controller.addLayer(
        SymbolStyleLayer(
          id: 'poi-icons',
          sourceId: 'poi-source',
          layout: {
            'icon-image': 'marker-m', // In production, use icon mapping
            'icon-size': iconSize,
            'icon-allow-overlap': allowOverlap,
            'icon-anchor': 'bottom',
            'text-field': ['get', 'name'],
            'text-size': 12,
            'text-anchor': 'top',
            'text-offset': [0, 0.5],
            'text-optional': true,
          },
          paint: {
            'text-color': '#000000',
            'text-halo-color': '#FFFFFF',
            'text-halo-width': 1,
          },
        ),
      );

      debugPrint('POI layer added with ${_pois.length} POIs');
    } catch (e) {
      debugPrint('Failed to add POI layer: $e');
    }
  }

  /// Update POI layer when zoom changes
  /// Note: MapLibre Flutter doesn't support dynamic layer property updates yet,
  /// so we recreate the layer with new properties
  Future<void> _updatePOILayer() async {
    if (_styleController == null || _poiConfig == null || !_iconsLoaded) return;

    try {
      // Remove existing layer
      await _styleController!.removeLayer('poi-icons');

      // Add layer with updated properties
      await _addPOILayer(_styleController!);

      debugPrint('POI layer updated for zoom $_currentZoom');
    } catch (e) {
      debugPrint('Failed to update POI layer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POI Layer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPOIConfig,
            tooltip: 'Reload POIs',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                          onPressed: _loadPOIConfig,
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
                        initCenter: Position(8.541, 47.377),
                      ),
                      onStyleLoaded: (style) async {
                        _styleController = style;
                        await _loadPOIIcons(style);
                        await _addPOILayer(style);
                      },
                      onEvent: (event) async {
                        switch (event) {
                          case MapEventMoveCamera():
                            final newZoom = event.camera.zoom;
                            if ((newZoom - _currentZoom).abs() > 0.5) {
                              setState(() {
                                _currentZoom = newZoom;
                              });
                              await _updatePOILayer();
                            }
                          case MapEventClick():
                            // POI click handling - show a simple message for now
                            // In a real app, you'd query the map for features at this point
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Clicked at: ${event.point.lng.toStringAsFixed(4)}, ${event.point.lat.toStringAsFixed(4)}',
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          default:
                            break;
                        }
                      },
                    ),
                    // Zoom level indicator
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'Zoom: ${_currentZoom.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // POI count indicator
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${_pois.length} POIs',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Show POI details in a bottom sheet
  void _showPOIDetails(Map<String, dynamic> properties) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, size: 32, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        properties['name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (properties['type'] != null)
                        Text(
                          properties['type'],
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (properties['description'] != null) ...[
              _buildInfoRow(Icons.info_outline, properties['description']),
              const SizedBox(height: 8),
            ],
            if (properties['address'] != null) ...[
              _buildInfoRow(Icons.place, properties['address']),
              const SizedBox(height: 8),
            ],
            if (properties['phone'] != null) ...[
              _buildInfoRow(Icons.phone, properties['phone']),
              const SizedBox(height: 8),
            ],
            if (properties['website'] != null) ...[
              _buildInfoRow(Icons.language, properties['website']),
              const SizedBox(height: 8),
            ],
            if (properties['opening_hours'] != null) ...[
              _buildInfoRow(Icons.access_time, properties['opening_hours']),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
