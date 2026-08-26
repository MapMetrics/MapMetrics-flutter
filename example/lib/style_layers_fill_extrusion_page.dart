import 'package:flutter/material.dart';
import 'package:maplibre_example/map_styles.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class StyleLayersFillExtrusionPage extends StatefulWidget {
  const StyleLayersFillExtrusionPage({super.key});

  static const location = '/style-layers/fill-extrusion';

  @override
  State<StyleLayersFillExtrusionPage> createState() =>
      _StyleLayersFillExtrusionPageState();
}

const _sourceId = 'floorplan';

class _StyleLayersFillExtrusionPageState
    extends State<StyleLayersFillExtrusionPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fill Extrusion Style Layer')),
      body: MapMetricsView(
        options: MapOptions(
          // The indoor-3d-map data is a single building in Chicago. At zoom 12
          // it is a few pixels across, and with no pitch a fill-extrusion is
          // drawn straight down -- you see the footprint and no height at all,
          // which reads as "the layer does not work".
          //
          // A fill-extrusion needs a tilted camera to show anything. 16 puts
          // the building on screen; 45 degrees of pitch makes the extrusion
          // visible as extrusion.
          //
          // The demo style's sources stop at zoom 12, so the basemap under the
          // building is overzoomed here. The extruded geometry is GeoJSON and
          // renders at full detail regardless.
          initCenter: Position(-87.6169, 41.8662),
          initZoom: 16,
          initPitch: 45,
        ),
        onStyleLoaded: _onStyleLoaded,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    await style.addSource(
      const GeoJsonSource(
        id: _sourceId,
        data:
            'https://maplibre.org/maplibre-gl-js/docs/assets/indoor-3d-map.geojson',
      ),
    );
    await style.addLayer(_fillExtrusionStyleLayer);
  }
}

const _fillExtrusionStyleLayer = FillExtrusionStyleLayer(
  id: 'room-extrusion',
  sourceId: _sourceId,
  paint: {
    // See the MapLibre Style Specification for details on data expressions.
    // https://maplibre.org/maplibre-style-spec/expressions/

    // Get the fill-extrusion-color from the source 'color' property.
    'fill-extrusion-color': ['get', 'color'],

    // Get fill-extrusion-height from the source 'height' property.
    'fill-extrusion-height': ['get', 'height'],

    // Get fill-extrusion-base from the source 'base_height' property.
    'fill-extrusion-base': ['get', 'base_height'],

    // Make extrusions slightly opaque for see through indoor walls.
    'fill-extrusion-opacity': 0.5,
  },
);
