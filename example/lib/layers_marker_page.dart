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
      appBar: AppBar(title: const Text('Marker Layer')),
      body: MapMetricsView(
        options: MapOptions(initCenter: Position(9.17, 47.68), initZoom: 7),
        onEvent: (event) {
          if (event case MapEventClick()) {
            setState(() {
              _points.add(Point(coordinates: event.point));
            });
          }
        },
        layers: [
          MarkerLayer(
            points: _points,
            textField: 'Marker',
            textAllowOverlap: true,
            iconImage: _imageLoaded ? 'marker' : null,
            iconSize: 0.08,
            iconAnchor: IconAnchor.bottom,
            textOffset: const [0, 1],
          ),
        ],
      ),
    );
  }
}
