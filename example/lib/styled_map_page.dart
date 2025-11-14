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
  bool _autoLocationInitialized = false;

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
          print('Map created: ${controller.toString()}');
        },
        onStyleLoaded: (style) {
          style.setProjection(MapProjection.globe);
          print('Style loaded, triggering auto location...');
          _triggerAutoLocation();
        },
        mapChildren: [
          const MapScalebar(
            padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 50),
          ),
          const SourceAttribution(),
          MapControlButtons(
            showZoomInOutButton: true,
            showTrackLocation: true,
            autoInitializeLocation: false, // We handle this manually in onStyleLoaded
            onCurrentLocation: (location) {
              print("location: ${location.lat}, ${location.lng}");
            },
          ),
          // const MapCompass(),
        ],
      ),
    );
  }

  void _triggerAutoLocation() async {
    if (_mapController == null || _autoLocationInitialized) return;
    
    _autoLocationInitialized = true;
    
    try {
      print('Starting auto location initialization...');
      
      // Enable location services
      await _mapController!.enableLocation();
      print('Location enabled');
      
      // Give time for GPS to get a fix
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Start tracking user location (this will center the map)
      await _mapController!.trackLocation(trackLocation: true);
      print('Location tracking started');
      
      // Set appropriate zoom level for user location
      await _mapController!.animateCamera(
        zoom: 15.0,
        nativeDuration: const Duration(milliseconds: 1500),
      );
      
      print('Auto location initialization completed successfully');
      
    } catch (e) {
      print('Error in auto location initialization: $e');
    }
  }
}
