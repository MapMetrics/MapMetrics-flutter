import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class CustomMarkerPage extends StatefulWidget {
  const CustomMarkerPage({super.key});
  static const location = '/custom-marker';

  @override
  State<CustomMarkerPage> createState() => _CustomMarkerPageState();
}

class _CustomMarkerPageState extends State<CustomMarkerPage> {
  late final MapController _controller;
  final _mapKey = GlobalKey();

  final List<Position> _markerPositions = [
    Position(4.83, 52.37),
    Position(4.89, 52.37),
    Position(4.95, 52.37),
    Position(5.01, 52.37),
  ];

  final List<String> _markerLabels = [
    'Marker 1',
    'Marker 2',
    'Marker 3',
    'Marker 4',
  ];

  Position? _originalPosition;
  MapGestures _mapGestures = const MapGestures.all();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Markers')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              'Tap or Long tap map: Create marker.\nTap marker: Show dialog.\nLong tap marker: Show popup menu.\nTap+drag marker: Move marker.',
              textAlign: TextAlign.left,
            ),
          ),
          Expanded(
            child: MapMetricsView(
              key: _mapKey,
              options: MapOptions(
                initZoom: 11,
                initCenter: Position(4.92, 52.37),
                gestures: _mapGestures,
              ),
              onMapCreated: (controller) => _controller = controller,
              onEvent: (event) async {
                if (event is MapEventClick) {
                  _addMarker(event.point);
                } else if (event is MapEventLongClick) {
                  _addMarker(event.point);
                }
              },
              mapChildren: [
                WidgetLayer(
                  allowInteraction: true,
                  markers: List.generate(
                    _markerPositions.length,
                    (index) => Marker(
                      size: const Size(70, 80),
                      point: _markerPositions[index],
                      child: GestureDetector(
                        onTap: () => _onTap(index),
                        onLongPressStart:
                            (details) => _onLongPress(index, details),
                        onPanStart: (details) => _onPanStart(details, index),
                        onPanUpdate:
                            (details) async => _onPanUpdate(details, index),
                        onPanEnd: (details) async => _onPanEnd(details, index),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 50,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Text(
                                _markerLabels[index],
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                ),
                const MapScalebar(
                  padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 50),
                ),
                const SourceAttribution(),
                const MapControlButtons(),
                const MapCompass(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addMarker(Position position) {
    _markerPositions.add(position);
    _markerLabels.add('Marker ${_markerPositions.length}');
    setState(() {});
  }

  Future<Position> _toLngLat(Offset eventOffset) async {
    final pixelRatio =
        (!kIsWeb && Platform.isAndroid)
            ? MediaQuery.devicePixelRatioOf(context)
            : 1.0;

    final mapRenderBox =
        _mapKey.currentContext?.findRenderObject() as RenderBox?;

    assert(mapRenderBox != null, 'RenderBox of Map should never be null');

    final mapOffset = mapRenderBox!.localToGlobal(Offset.zero);

    final offset = Offset(
      eventOffset.dx - mapOffset.dx,
      eventOffset.dy - mapOffset.dy,
    );

    return _controller.toLngLat(offset.scale(pixelRatio, pixelRatio));
  }

  void _onLongPress(int index, LongPressStartDetails details) {
    final offset = details.globalPosition;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        MediaQuery.of(context).size.width - offset.dx,
        MediaQuery.of(context).size.height - offset.dy,
      ),
      items: [
        const PopupMenuItem<void>(child: Text('Edit')),
        PopupMenuItem<void>(
          onTap: () async {
            final isConfirmed = await _showConfirmationDialogDelete(index);
            if (isConfirmed) {
              _markerPositions.removeAt(index);
              _markerLabels.removeAt(index);
              setState(() {});
            }
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }

  Future<void> _onPanEnd(DragEndDetails details, int index) async {
    final isAccepted = await _showConfirmationDialogMove();

    if (!isAccepted) {
      _markerPositions[index] = _originalPosition!;
    } else {
      final newPosition = await _toLngLat(details.globalPosition);
      _markerPositions[index] = newPosition;
    }

    _originalPosition = null;

    setState(() {
      _mapGestures = const MapGestures.all();
    });
  }

  void _onPanStart(DragStartDetails details, int index) {
    _originalPosition = _markerPositions[index].clone();

    setState(() {
      _mapGestures = const MapGestures.all(pan: false);
    });
  }

  Future<void> _onPanUpdate(DragUpdateDetails details, int index) async {
    final newPosition = await _toLngLat(details.globalPosition);
    _markerPositions[index] = newPosition;

    setState(() {});
  }

  void _onTap(int index) {
    _showMarkerDetails(index);
  }

  Future<bool> _showConfirmationDialogDelete(int index) async {
    final isConfirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Delete ${_markerLabels[index]}?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: const Text('Delete'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
    );
    return isConfirmed ?? false;
  }

  Future<bool> _showConfirmationDialogMove() async {
    final isConfirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Accept new position?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Discard'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: const Text('Accept'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
    );
    return isConfirmed ?? false;
  }

  Future<void> _showMarkerDetails(int index) async {
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(_markerLabels[index]),
            content: Text(
              'Details of ${_markerLabels[index]} at:\n'
              'LatLng: ${_markerPositions[index].lat}, ${_markerPositions[index].lng}',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
    );
  }
}
