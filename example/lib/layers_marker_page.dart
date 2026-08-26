import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  // `_imageLoaded` was declared false and never set true -- nothing in this
  // page ever registered a 'marker' image -- so iconImage below was always
  // null. With the label font also 404ing on the glyph CDN, this example
  // rendered nothing at all: no icon, no text, just a bare map.
  //
  // The flag is gone rather than wired up: MarkerLayer draws its textField
  // without an icon, which is enough to demonstrate the layer. Registering a
  // custom sprite is what layers_custom_marker_page is for.

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
            textOffset: const [0, 1],
          ),
        ],
      ),
    );
  }
}
