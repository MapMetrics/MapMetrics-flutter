import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class StyleLayersCirclePage extends StatefulWidget {
  const StyleLayersCirclePage({super.key});

  static const location = '/style-layers/circle';

  @override
  State<StyleLayersCirclePage> createState() => _StyleLayersCirclePageState();
}

const _layerId = 'showcaseLayer';
const _sourceId = 'earthquakes';

class _StyleLayersCirclePageState extends State<StyleLayersCirclePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Circle Style Layer')),
      body: MapMetricsView(
        options: MapOptions(
          initCenter: Position(-152.9959, 59.8150),
          initZoom: 9,
        ),
        onStyleLoaded: _onStyleLoaded,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    const earthquakes = GeoJsonSource(
      id: _sourceId,
      data:
          'https://maplibre.org/maplibre-gl-js/docs/assets/earthquakes.geojson',
    );
    await style.addSource(earthquakes);
    await style.addLayer(_circleStyleLayer);
  }
}

const _circleStyleLayer = CircleStyleLayer(
  id: _layerId,
  sourceId: _sourceId,
  paint: {
    // Size circle radius by earthquake magnitude and zoom level.
    //
    // `interpolate` REQUIRES AT LEAST TWO STOPS. This had exactly one (zoom
    // 7), which is not a valid expression, so the layer failed validation and
    // was never added -- the example rendered a bare map with no circles on
    // it. The canonical MapLibre earthquake example interpolates between zoom
    // 7 and zoom 16; the second stop was lost when this was copied.
    'circle-radius': [
      'interpolate',
      ['linear'],
      ['zoom'],
      7,
      [
        'interpolate',
        ['linear'],
        ['get', 'mag'],
        1,
        1,
        6,
        4,
      ],
      16,
      [
        'interpolate',
        ['linear'],
        ['get', 'mag'],
        1,
        5,
        6,
        50,
      ],
    ],
    // Color circle by earthquake magnitude
    'circle-color': [
      'interpolate',
      ['linear'],
      ['get', 'mag'],
      1,
      'rgba(33,102,172,0)',
      2,
      'rgb(103,169,207)',
      3,
      'rgb(209,229,240)',
      4,
      'rgb(253,219,199)',
      5,
      'rgb(239,138,98)',
      6,
      'rgb(178,24,43)',
    ],
    'circle-stroke-color': 'white',
    'circle-stroke-width': 1,
    // Transition from heatmap to circle layer by zoom level
    'circle-opacity': [
      'interpolate',
      ['linear'],
      ['zoom'],
      7,
      0,
      8,
      1,
    ],
  },
);
