import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_example/map_styles.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class KioskPage extends StatefulWidget {
  const KioskPage({super.key});

  static const location = '/kiosk';

  @override
  State<KioskPage> createState() => _KioskPageState();
}

class _KioskPageState extends State<KioskPage> {
  /// The MapMetrics demo style -- no key, so nothing here to rotate or leak.
  ///
  /// This used to be a Protomaps demo URL with their key inline, inherited
  /// from the upstream MapLibre plugin. It worked, but it sent an example of
  /// OUR SDK to a third party's tile server, and the key was theirs to rotate
  /// out from under us.
  ///
  /// **Use your own key and style for your project** -- get one at
  /// https://mapatlas.eu and pass it via `MapOptions.apiKey`.
  static const _styleUrl = MapStyles.demo;

  late final MapController _controller;
  final _locations = <_Location>[
    _Location(Position(5.7056, 21.9137), 2, 0, 0),
    _Location(Position(113.685084, 1.084979), 5, 0, 60),
    _Location(Position(174.7717, -36.8821), 12, -50, 60),
    _Location(Position(172.4714, -42.4862), 6, -100, 40),
  ];
  Timer? _timer;
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapMetricsView(
        options: MapOptions(initStyle: _styleUrl, initCenter: Position(0, 0)),
        onMapCreated: (controller) => _controller = controller,
        onStyleLoaded: (_) {
          _timer = Timer.periodic(const Duration(seconds: 5), _onTimer);
        },
      ),
    );
  }

  void _onTimer(Timer timer) {
    final location = _locations[index];
    _controller.animateCamera(
      center: location.center,
      zoom: location.zoom,
      bearing: location.bearing,
      pitch: location.pitch,
    );
    index++;
    if (index >= _locations.length) index = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _Location {
  const _Location(this.center, this.zoom, this.bearing, this.pitch);

  final Position center;
  final double zoom;
  final double bearing;
  final double pitch;
}
