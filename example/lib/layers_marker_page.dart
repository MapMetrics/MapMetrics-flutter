import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_example/style_layers_symbol_page.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class LayersMarkerPage extends StatefulWidget {
  const LayersMarkerPage({super.key});

  static const location = '/layers/marker';

  @override
  State<LayersMarkerPage> createState() => _LayersMarkerPageState();
}

class _LayersMarkerPageState extends State<LayersMarkerPage> {
  final _points = <Point>[
    Point(coordinates: Position(9.17, 47.68)),
    Point(coordinates: Position(9.17, 48)),
    Point(coordinates: Position(9, 48)),
    Point(coordinates: Position(9.5, 48)),
  ];

  bool _imageLoaded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marker Layers')),
      body: MapLibreMap(
        options: MapOptions(initZoom: 7, initCenter: Position(9.17, 47.68)),
        onEvent: (event) async {
          switch (event) {
            case MapEventStyleLoaded():
              // Load image synchronously during style load
              debugPrint('🟢 LayersMarkerPage: Style loaded, loading image');

              try {
                final response = await http.get(
                  Uri.parse(StyleLayersSymbolPage.imageUrl),
                ).timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    debugPrint('❌ LayersMarkerPage: HTTP timeout');
                    throw TimeoutException('HTTP request timeout');
                  },
                );

                debugPrint('🟢 LayersMarkerPage: HTTP success, status: ${response.statusCode}');
                final bytes = response.bodyBytes;

                if (!mounted) {
                  debugPrint('⚠️ LayersMarkerPage: Widget unmounted after download');
                  return;
                }

                await event.style.addImage('marker', bytes);

                debugPrint('✅ LayersMarkerPage: Image loaded, now enabling layer');

                // Trigger rebuild to create the layer NOW that the image is loaded
                if (mounted) {
                  setState(() {
                    _imageLoaded = true;
                  });
                }
              } catch (e, stack) {
                debugPrint('❌ LayersMarkerPage: Error loading image: $e');
                debugPrint('Stack: $stack');
                // Don't crash - markers will display without icon
              }
            case MapEventClick():
              // add a new marker on click
              if (!mounted) return;
              setState(() {
                _points.add(Point(coordinates: event.point));
              });
            default:
              // ignore all other events
              break;
          }
        },
        // Only create the layer AFTER the image is loaded
        layers: _imageLoaded
            ? [
                MarkerLayer(
                  points: _points,
                  textField: 'Marker',
                  textAllowOverlap: true,
                  iconImage: 'marker',
                  iconSize: 0.15,
                  iconAllowOverlap: true,
                  iconIgnorePlacement: true,
                  iconAnchor: IconAnchor.bottom,
                  textOffset: const [0, 1],
                ),
              ]
            : [],
      ),
    );
  }
}
