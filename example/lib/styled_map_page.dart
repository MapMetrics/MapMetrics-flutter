import 'package:flutter/material.dart';
import 'package:maplibre_example/map_styles.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class StyledMapPage extends StatefulWidget {
  const StyledMapPage({super.key});

  static const location = '/styled-map';

  @override
  State<StyledMapPage> createState() => _StyledMapPageState();
}

class _StyledMapPageState extends State<StyledMapPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Styled Map')),
      body: MapLibreMap(
        acceptLicense: true,
        options: MapOptions(
          initCenter: Position(9.17, 47.68),
          initZoom: 2,
          initStyle: MapStyles.maptilerStreets,
        ),
        children: const [
          MapScalebar(),
          SourceAttribution(),
          MapControlButtons(showTrackLocation: true),
          MapCompass(),
        ],
        onStyleLoaded: (style) {
          style.setProjection(MapProjection.globe);
        },
      ),
    );
  }
}
