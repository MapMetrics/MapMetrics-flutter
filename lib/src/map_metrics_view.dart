import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class MapMetricsView extends StatelessWidget {
  const MapMetricsView({
    super.key,
    this.acceptLicense = true,
    this.options = const MapOptions(),
    this.gestureRecognizers,
    this.onMapCreated,
    this.onStyleLoaded,
    this.onEvent,
    this.layers = const [],
    this.mapChildren = const [],
  });

  final bool acceptLicense;
  final MapOptions options;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;
  final MapCreatedCallback? onMapCreated;
  final StyleLoadedCallback? onStyleLoaded;
  final MapEventCallback? onEvent;
  final List<Layer> layers;

  /// Widgets rendered on top of the map (can appear over fixed image).
  final List<Widget> mapChildren;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MapLibreMap(
          acceptLicense: acceptLicense,
          options: options,
          gestureRecognizers: gestureRecognizers,
          onMapCreated: onMapCreated,
          onStyleLoaded: onStyleLoaded,
          onEvent: onEvent,
          layers: layers,
          children: mapChildren,
        ),

        // Fixed image at bottom-left
        Positioned(
          left: 10,
          bottom: 40,
          child: IgnorePointer(
            // Prevents blocking touch events below
            child: Image.asset(
              'packages/mapmetrics/assets/logo_tr.png',
              width: 100,
              height: 25,
            ),
          ),
        ),
      ],
    );
  }
}
