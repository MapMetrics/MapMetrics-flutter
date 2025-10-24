# MapMetrics Integration Guide

This guide shows you how to integrate the MapMetrics Flutter package with POI functionality into your own Flutter application.

## Step 1: Add Dependency

Add MapMetrics to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  mapmetrics:
    git:
      url: https://github.com/MapMetrics/MapMetrics-flutter.git
      # Or use local path for development:
      # path: /path/to/MapMetrics-flutter
```

Then run:
```bash
flutter pub get
```

## Step 2: Basic Map Setup

Create a basic map page in your app:

```dart
import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

class MyMapPage extends StatefulWidget {
  const MyMapPage({super.key});

  @override
  State<MyMapPage> createState() => _MyMapPageState();
}

class _MyMapPageState extends State<MyMapPage> {
  MapLibreMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Map')),
      body: MapLibreMap(
        options: MapOptions(
          initZoom: 14,
          initCenter: Position(9.17, 45.46), // Your desired location
          initStyle: 'https://demotiles.maplibre.org/style.json',
        ),
        onMapCreated: (controller) {
          _mapController = controller;
          // Initialize POI layers after map is ready
          _initializePOILayers();
        },
        onLongClick: _handleLongPress,
      ),
    );
  }

  Future<void> _initializePOILayers() async {
    // Will be implemented in next step
  }

  Future<void> _handleLongPress(Position point) async {
    // Will be implemented in next step
  }
}
```

## Step 3: Add POI Layer Setup

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class _MyMapPageState extends State<MyMapPage> {
  MapLibreMapController? _mapController;
  StyleController? _styleController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Map with POIs')),
      body: MapLibreMap(
        options: MapOptions(
          initZoom: 14,
          initCenter: Position(9.17, 45.46),
          initStyle: 'https://demotiles.maplibre.org/style.json',
        ),
        onMapCreated: (controller) {
          _mapController = controller;
        },
        onStyleLoaded: (controller) async {
          _styleController = controller;
          await _setupPOILayers();
        },
        onLongClick: _handleLongPress,
      ),
    );
  }

  Future<void> _setupPOILayers() async {
    if (_styleController == null) return;

    try {
      // 1. Add POI vector tile source
      await _styleController!.addVectorSource(
        id: 'poi-source',
        tiles: ['https://your-poi-tile-server.com/tiles/{z}/{x}/{y}.mvt'],
        minZoom: 0,
        maxZoom: 22,
      );

      // 2. Load POI icons
      await _loadPOIIcons();

      // 3. Add POI symbol layer with icon expressions
      await _styleController!.addSymbolLayer(
        id: 'poi-symbols',
        sourceId: 'poi-source',
        layout: {
          'source-layer': 'pois',
          'icon-image': [
            'case',
            // Restaurant POIs
            ['==', ['get', 'amenity'], 'restaurant'],
            'restaurant_icon',
            // Cafe POIs
            ['==', ['get', 'amenity'], 'cafe'],
            'cafe_icon',
            // Default fallback
            'default_icon',
          ],
          'icon-size': 0.8,
          'icon-allow-overlap': true,
          'text-field': ['get', 'name'],
          'text-size': 12,
          'text-offset': [0, 1.5],
          'text-anchor': 'top',
        },
        paint: {
          'text-color': '#333333',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2,
        },
      );

      print('POI layers added successfully');
    } catch (e) {
      print('Error setting up POI layers: $e');
    }
  }

  Future<void> _loadPOIIcons() async {
    // Load your POI icons from assets or network
    // Example:
    final iconData = await rootBundle.load('assets/icons/restaurant.png');
    final bytes = iconData.buffer.asUint8List();
    await _styleController!.addImage('restaurant_icon', bytes);

    // Load other icons similarly...
  }

  Future<void> _handleLongPress(Position point) async {
    if (_mapController == null) return;

    try {
      // Convert geographic position to screen coordinates
      final screenLocation = await _mapController!.toScreenLocation(point);

      // Query layers at that location
      final layers = await _mapController!.queryLayers(screenLocation);

      // Filter for POI layers
      final poiFeatures = layers.where((feature) {
        final layerId = feature['layerId'];
        return layerId == 'poi-symbols';
      }).toList();

      if (poiFeatures.isNotEmpty) {
        final poiData = poiFeatures.first;
        await _showPOIDialog(poiData);
      }
    } catch (e) {
      print('Error handling long press: $e');
    }
  }

  Future<void> _showPOIDialog(Map<String, String> poiData) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poiData['name'] ?? 'POI Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: poiData.entries.map((entry) {
              // Skip metadata keys
              if (['layerId', 'sourceId', 'sourceLayer'].contains(entry.key)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(child: Text(entry.value)),
                  ],
                ),
              );
            }).toList(),
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
}
```

## Step 4: Advanced POI Configuration (Optional)

For more complex POI setups with multiple categories (like the example app), you can:

### Create a POI Service Class

```dart
class POIService {
  final StyleController styleController;

  POIService(this.styleController);

  // POI category definitions
  static const List<String> categories = [
    'landuse', 'power', 'barrier', 'emergency', 'man_made',
    'public_transport', 'highway', 'railway', 'aeroway', 'natural',
    'historic', 'healthcare', 'craft', 'office', 'sport',
    'leisure', 'tourism', 'shop', 'amenity',
  ];

  Future<void> setupPOIs({
    required String sourceId,
    required String tileUrl,
    required Map<String, Uint8List> iconImages,
  }) async {
    // Add source
    await styleController.addVectorSource(
      id: sourceId,
      tiles: [tileUrl],
      minZoom: 0,
      maxZoom: 22,
    );

    // Add all icon images
    for (final entry in iconImages.entries) {
      await styleController.addImage(entry.key, entry.value);
    }

    // Build complex icon-image expression
    final iconExpression = _buildIconExpression();

    // Add symbol layer
    await styleController.addSymbolLayer(
      id: 'poi-symbols',
      sourceId: sourceId,
      layout: {
        'source-layer': 'pois',
        'icon-image': iconExpression,
        'icon-size': 0.8,
        'icon-allow-overlap': true,
        'text-field': [
          'coalesce',
          ['get', 'name'],
          ['get', 'name:en'],
          ''
        ],
        'text-size': 12,
        'text-offset': [0, 1.5],
        'text-anchor': 'top',
      },
      paint: {
        'text-color': '#333333',
        'text-halo-color': '#FFFFFF',
        'text-halo-width': 2,
      },
    );
  }

  List<dynamic> _buildIconExpression() {
    // Build nested case expressions for all categories
    List<dynamic> caseExpr = ['case'];

    for (final category in categories) {
      // Check if category property exists and has a value
      caseExpr.add(['has', category]);
      caseExpr.add([
        'match',
        ['get', category],
        'restaurant', 'restaurant_icon',
        'cafe', 'cafe_icon',
        // Add more mappings...
        'default_icon'
      ]);
    }

    // Fallback
    caseExpr.add('default_icon');

    return caseExpr;
  }
}
```

## Step 5: Platform-Specific Setup

### Android (android/app/build.gradle)

```gradle
android {
    defaultConfig {
        minSdkVersion 21  // MapLibre requires API 21+
    }
}
```

### iOS (ios/Podfile)

Make sure you have:
```ruby
platform :ios, '12.0'  # MapLibre requires iOS 12+

use_frameworks!
```

## Step 6: Load Icons from Assets

Add your POI icons to `assets/icons/` and update `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/icons/
```

## Complete Minimal Example

```dart
import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My POI App',
      home: const POIMapPage(),
    );
  }
}

class POIMapPage extends StatefulWidget {
  const POIMapPage({super.key});

  @override
  State<POIMapPage> createState() => _POIMapPageState();
}

class _POIMapPageState extends State<POIMapPage> {
  MapLibreMapController? _mapController;
  StyleController? _styleController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('POI Map')),
      body: MapLibreMap(
        options: MapOptions(
          initZoom: 14,
          initCenter: Position(9.17, 45.46),
          initStyle: 'https://demotiles.maplibre.org/style.json',
        ),
        onMapCreated: (controller) => _mapController = controller,
        onStyleLoaded: (controller) {
          _styleController = controller;
          _setupPOIs();
        },
        onLongClick: _handlePOIClick,
      ),
    );
  }

  Future<void> _setupPOIs() async {
    // Add your POI setup code here
  }

  Future<void> _handlePOIClick(Position point) async {
    // Add your POI click handling here
  }
}
```

## Reference Implementation

For a complete working example, refer to:
- `/example/lib/poi_demo_page.dart` - Full POI implementation
- `/example/lib/widget_layer_interactive_page.dart` - Layer interaction examples

## Tips

1. **Performance**: Load only visible POI icons to reduce memory usage
2. **Caching**: Cache POI tile data for offline support
3. **Customization**: Create custom icon expressions based on your POI categories
4. **Error Handling**: Always wrap map operations in try-catch blocks
5. **Testing**: Test on both iOS and Android - the native expression converter ensures consistent behavior

## Troubleshooting

### Icons not showing
- Ensure icons are loaded before adding the symbol layer
- Check icon names match between expression and loaded images
- Verify tile server is returning data at the current zoom level

### Click detection not working
- Verify long press handler is registered
- Check that `queryLayers` is returning features
- Ensure layer IDs match in filter condition

### iOS-specific issues
- Rebuild after changes: `flutter clean && flutter build ios`
- Check Xcode console for native logs

## Support

For issues or questions, refer to the example app in the `/example` directory or check the GitHub repository.
