import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class LayersMarkerPage extends StatefulWidget {
  const LayersMarkerPage({super.key});

  static const location = '/layers/marker';

  @override
  State<LayersMarkerPage> createState() => _LayersMarkerPageState();
}

class _LayersMarkerPageState extends State<LayersMarkerPage> {
  final _points = <Point>[
    Point(coordinates: Position(9.17, 47.68)),
    Point(coordinates: Position(9.17, 48)),
    Point(coordinates: Position(9, 48)),
    Point(coordinates: Position(9.5, 48)),
  ];

  /// Set once the 'marker' sprite has been registered with the style.
  ///
  /// A symbol layer's icon-image names an image in the style's sprite; naming
  /// one that has not been registered draws no icon and reports no error. This
  /// page used to pass an iconImage guarded by a flag that was never set true,
  /// so the icon was always null and only the label could ever appear.
  ///
  /// The layer is withheld until the image exists rather than added alongside
  /// it: onStyleLoaded is not awaited before the declarative `layers:` are
  /// applied, so adding both at once is a race.
  bool _iconReady = false;

  /// Draw the marker sprite locally, rather than fetching one.
  ///
  /// An example that downloads its icon fails whenever the network or the host
  /// does, which reads as "the SDK is broken". Rendering Material's location_on
  /// glyph to PNG bytes keeps the page self-contained.
  Future<Uint8List> _renderPin({double size = 96}) async {
    const icon = Icons.location_on;
    final painter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: const Color(0xFFD32F2F),
        ),
      )
      ..layout();

    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    final image = await recorder.endRecording().toImage(
      painter.width.ceil(),
      painter.height.ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    await style.addImage('marker', await _renderPin());
    if (mounted) setState(() => _iconReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marker Layer')),
      body: MapMetricsView(
        options: MapOptions(initCenter: Position(9.17, 47.68), initZoom: 7),
        onStyleLoaded: _onStyleLoaded,
        onEvent: (event) {
          if (event case MapEventClick()) {
            setState(() {
              _points.add(Point(coordinates: event.point));
            });
          }
        },
        layers: [
          if (_iconReady)
            MarkerLayer(
              points: _points,
              iconImage: 'marker',
              // The pin's tip is at the bottom of the glyph, so anchor there:
              // with the default `center` the pin floats half a symbol above
              // the coordinate it marks.
              iconAnchor: IconAnchor.bottom,
              iconSize: 0.5,
              iconAllowOverlap: true,
              textField: 'Marker',
              textAllowOverlap: true,
              // Push the label clear of the icon rather than over it.
              textOffset: const [0, 1],
            ),
        ],
      ),
    );
  }
}
