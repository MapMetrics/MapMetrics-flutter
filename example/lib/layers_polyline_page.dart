import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class LayersPolylinePage extends StatefulWidget {
  const LayersPolylinePage({super.key});

  static const location = '/layers/polyline';

  @override
  State<LayersPolylinePage> createState() => _LayersPolylinePageState();
}

class _LayersPolylinePageState extends State<LayersPolylinePage> {
  final _polylines = <LineString>[
    LineString(
      coordinates: [Position(9.17, 47.68), Position(9.5, 48), Position(9, 48)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Polyline Layer')),
      body: MapMetricsView(
        options: MapOptions(initCenter: Position(9.17, 47.68), initZoom: 7),
        layers: [
          PolylineLayer(polylines: _polylines, color: Colors.blue, width: 3),
        ],
      ),
    );
  }
}
