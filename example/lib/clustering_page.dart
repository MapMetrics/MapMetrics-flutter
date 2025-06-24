import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class ClusteringPage extends StatefulWidget {
  const ClusteringPage({super.key});

  static const location = '/clustering';

  @override
  State<ClusteringPage> createState() => _ClusteringPageState();
}

class _ClusteringPageState extends State<ClusteringPage> {
  @override
  void initState() {
    super.initState();
    print('ClusteringPage: initState called');
  }

  @override
  Widget build(BuildContext context) {
    print('ClusteringPage: build called');
    return Scaffold(
      appBar: AppBar(title: const Text('Clustering Example')),
      body: MapMetricsView(
        options: MapOptions(
          initCenter: Position(
            10.0,
            50.0,
          ), // Europe - where our test points are
          initZoom: 4,
        ),
        onStyleLoaded: _onStyleLoaded,
        mapChildren: [
          const MapScalebar(
            alignment: Alignment.bottomLeft,
            padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 50),
          ),
          const SourceAttribution(),
          MapControlButtons(showZoomInOutButton: true, showTrackLocation: true),
        ],
        onEvent: (event) {
          if (event case MapEventClick()) {
            // Handle click events for clusters and points
            print('ClusteringPage: Clicked at: ${event.point}');
          }
          if (event case MapEventStyleLoaded()) {
            print('ClusteringPage: MapEventStyleLoaded received');
          }
        },
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    print('ClusteringPage: Style loaded, adding test points source...');

    // Load local GeoJSON file instead of URL
    final testPointsData = await DefaultAssetBundle.of(
      context,
    ).loadString('assets/geojson/test-points.json');
    print(
      'ClusteringPage: Loaded test points data: ${testPointsData.length} characters',
    );

    // Add GeoJSON source with clustering enabled
    final testPoints = GeoJsonSource(
      id: 'test-points',
      data: testPointsData,
      cluster: true,
      clusterRadius: 50,
      clusterMaxZoom: 14,
    );
    print(
      'ClusteringPage: About to add source with cluster: ${testPoints.cluster}',
    );
    await style.addSource(testPoints);
    print('ClusteringPage: Added test points source');

    // Add layer for unclustered points FIRST (so it renders below clusters)
    const unclusteredLayer = CircleStyleLayer(
      id: 'unclustered-point',
      sourceId: 'test-points',
      filter: [
        '!',
        ['has', 'point_count'],
      ], // Only show features that DON'T have point_count (individual points)
      paint: {
        'circle-color': '#11b4da',
        'circle-radius': 8,
        'circle-stroke-width': 2,
        'circle-stroke-color': '#fff',
      },
    );
    print('ClusteringPage: About to add unclustered layer');
    await style.addLayer(unclusteredLayer);
    print('ClusteringPage: Added unclustered points layer');

    // Add layer for clusters (colored circles) - SECOND (renders above points)
    const clustersLayer = CircleStyleLayer(
      id: 'clusters',
      sourceId: 'test-points',
      filter: [
        'has',
        'point_count',
      ], // Only show features that have point_count (clusters)
      paint: {
        'circle-color': [
          'step',
          ['get', 'point_count'],
          '#51bbd6',
          100,
          '#f1f075',
          750,
          '#f28cb1',
        ],
        'circle-radius': [
          'step',
          ['get', 'point_count'],
          20,
          100,
          30,
          750,
          40,
        ],
      },
    );
    print('ClusteringPage: About to add clusters layer');
    await style.addLayer(clustersLayer);
    print('ClusteringPage: Added clusters layer');

    // Add layer for cluster count labels - LAST (renders on top of everything)
    const clusterCountLayer = SymbolStyleLayer(
      id: 'cluster-count',
      sourceId: 'test-points',
      filter: ['has', 'point_count'], // Only show labels for clusters
      layout: {
        'text-field': '{point_count_abbreviated}',
        'text-font': ['Open Sans Semibold'], // Use available font
        'text-size': 12,
      },
    );
    print('ClusteringPage: About to add cluster count layer');
    await style.addLayer(clusterCountLayer);
    print('ClusteringPage: Added cluster count layer');
  }
}
