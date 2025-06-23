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
  late final MapController _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fill Style Layer')),
      body: MapMetricsView(
        options: MapOptions(
          initCenter: Position(-74.006, 40.7128),
          initZoom: 9,
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
