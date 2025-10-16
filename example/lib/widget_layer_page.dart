import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class WidgetLayerPage extends StatefulWidget {
  const WidgetLayerPage({super.key});

  static const location = '/widget-layer';

  @override
  State<WidgetLayerPage> createState() => _WidgetLayerPageState();
}

class _WidgetLayerPageState extends State<WidgetLayerPage> {
  @override
  void initState() {
    super.initState();
    print('WidgetLayerPage: initState called');
  }

  @override
  Widget build(BuildContext context) {
    print('WidgetLayerPage: build called');
    return Scaffold(
      appBar: AppBar(title: const Text('Widget Layer')),
      body: MapMetricsView(
        options: MapOptions(
          initCenter: Position(-74.006, 40.7128),
          initZoom: 9,
        ),
        onStyleLoaded: _onStyleLoaded,
        onEvent: (event) {
          if (event case MapEventClick()) {
            print('WidgetLayerPage: Clicked at: ${event.point}');
          }
          if (event case MapEventStyleLoaded()) {
            print('WidgetLayerPage: MapEventStyleLoaded received');
          }
        },
        mapChildren: [
          WidgetLayer(
            markers: [
              // A 3D marker
              Marker(
                size: const Size.square(50),
                point: Position(-10, 0),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 50,
                ),
                alignment: Alignment.bottomCenter,
              ),
              Marker(
                size: const Size.square(50),
                point: Position(-5, 0),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 50,
                ),
                alignment: Alignment.bottomCenter,
                rotate: true,
              ),
              Marker(
                size: const Size.square(50),
                point: Position(0, 0),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 50,
                ),
                alignment: Alignment.bottomCenter,
                flat: true,
              ),
              Marker(
                size: const Size.square(50),
                point: Position(5, 0),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 50,
                ),
                alignment: Alignment.bottomCenter,
                flat: true,
                rotate: true,
              ),
            ],
          ),
          // display the UI widgets above the widget markers.
          const SourceAttribution(),
        ],
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    print('WidgetLayerPage: Style loaded');
    // Widget layer example doesn't need additional style setup
  }
}
