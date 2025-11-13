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

  MapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Styled Map')),
      body: MapMetricsView(
        options: const MapOptions(
          initZoom: 2,
          initStyle: MapStyles.maptilerStreets,
        ),
        onMapCreated: (controller) {
          _mapController = controller;
        },
        onStyleLoaded: (style) {
          style.setProjection(MapProjection.globe);
        },
        mapChildren: [
          const MapScalebar(
            padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 50),
          ),
          const SourceAttribution(),
          MapControlButtons(
            showZoomInOutButton: true,
            showTrackLocation: true,
            autoInitializeLocation: true, // This enables automatic location on start
            onCurrentLocation: (location) {
              print("location: ${location.lat}, ${location.lng}");
            },
          ),
          // const MapCompass(),
        ],
      ),
    );
  }
}
