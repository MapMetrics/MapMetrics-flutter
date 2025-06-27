import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  static const location = '/events';

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final _eventMessages = <String>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: MapMetricsView(
        options: MapOptions(
          initCenter: Position(-74.006, 40.7128),
          initZoom: 9,
        ),
        onEvent: (event) {
          final message = event.toString();
          debugPrint('[MapMetricsView] $message');
        },
      ),
    );
  }

  void _onEvent(MapEvent event) => switch (event) {
    MapEventMapCreated() => _print('map created'),
    MapEventStyleLoaded() => _print('style loaded'),
    MapEventMoveCamera() => _print(
      'move camera: center ${_formatPosition(event.camera.center)}, '
      'zoom ${event.camera.zoom.toStringAsFixed(2)}, '
      'pitch ${event.camera.pitch.toStringAsFixed(2)}, '
      'bearing ${event.camera.bearing.toStringAsFixed(2)}',
    ),
    MapEventStartMoveCamera() => _print(
      'start move camera, reason: ${event.reason.name}',
    ),
    MapEventClick() => _print('clicked: ${_formatPosition(event.point)}'),
    MapEventDoubleClick() => _print(
      'double clicked: ${_formatPosition(event.point)}',
    ),
    MapEventLongClick() => _print(
      'long clicked: ${_formatPosition(event.point)}',
    ),
    MapEventSecondaryClick() => _print(
      'secondary clicked: ${_formatPosition(event.point)}',
    ),
    MapEventIdle() => _print('idle'),
    MapEventCameraIdle() => _print('camera idle'),
  };

  void _print(String message) {
    debugPrint('[MapMetricsView] $message');
    setState(() {
      _eventMessages.add(message);
      if (_eventMessages.length > 10) _eventMessages.removeAt(0);
    });
  }

  String _formatPosition(Position point) =>
      '${point.lng.toStringAsFixed(3)}, ${point.lat.toStringAsFixed(3)}';
}
