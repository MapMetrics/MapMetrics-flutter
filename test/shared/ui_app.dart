import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/inherited_model.dart';

class App extends StatelessWidget {
  const App({
    required this.camera,
    required this.controller,
    this.children = const [],
    super.key,
  });

  final List<Widget> children;
  final MapController controller;
  final MapCamera? camera;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapMetrics Demo',
      home: Scaffold(
        body: MapLibreInheritedModel(
          mapCamera: camera,
          mapController: controller,
          child: Stack(children: children),
        ),
      ),
    );
  }
}
