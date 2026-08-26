import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class StyleLayersLinePage extends StatefulWidget {
  const StyleLayersLinePage({super.key});

  static const location = '/style-layers/line';

  @override
  State<StyleLayersLinePage> createState() => _StyleLayersLinePageState();
}

class _StyleLayersLinePageState extends State<StyleLayersLinePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Line Style Layer')),
      body: MapMetricsView(
        options: MapOptions(
          // Same fault as the fill example: the layer draws
          // assets/geojson/path.json, which runs lng 8.80..9.25,
          // lat 47.95..48.08, while the camera sat on New York.
          initCenter: Position(9.02, 48.01),
          initZoom: 9,
        ),
        onStyleLoaded: _onStyleLoaded,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    final geojsonLine = await rootBundle.loadString('assets/geojson/path.json');
    await style.addSource(GeoJsonSource(id: 'Path', data: geojsonLine));
    await style.addLayer(
      const LineStyleLayer(
        id: 'geojson-line',
        sourceId: 'Path',
        paint: {'line-color': '#F00', 'line-width': 3},
      ),
    );
  }
}
