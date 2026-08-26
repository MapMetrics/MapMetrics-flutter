import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class StyleLayersFillPage extends StatefulWidget {
  const StyleLayersFillPage({super.key});

  static const location = '/style-layers/fill';

  @override
  State<StyleLayersFillPage> createState() => _StyleLayersFillPageState();
}

class _StyleLayersFillPageState extends State<StyleLayersFillPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fill Style Layer')),
      body: MapMetricsView(
        options: MapOptions(
          // The layer fills assets/geojson/lake-constance.json, which spans
          // lng 8.86..9.75, lat 47.48..47.82. The camera pointed at
          // (-74.006, 40.7128) -- New York -- so the example rendered a lake
          // in Germany while looking at Manhattan, and showed a blank map.
          //
          // Zoom 8 rather than 9: the polygon is ~0.9 degrees wide, and at
          // zoom 9 the viewport is only ~0.55 degrees across, so the lake
          // would not fit on screen.
          initCenter: Position(9.31, 47.65),
          initZoom: 8,
        ),
        onStyleLoaded: _onStyleLoaded,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    final geojsonPolygon = await rootBundle.loadString(
      'assets/geojson/lake-constance.json',
    );
    await style.addSource(
      GeoJsonSource(id: 'LakeConstance-Source', data: geojsonPolygon),
    );
    await style.addLayer(
      const FillStyleLayer(
        id: 'LakeConstance-Layer',
        sourceId: 'LakeConstance-Source',
        paint: {'fill-color': '#429ef5'},
      ),
    );
  }
}
