import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clustering Example')),
      body: MapMetricsView(
        options: MapOptions(
          initCenter: Position(
            -151.5,
            63.1,
          ), // Alaska - where most earthquake data is
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
            print('Clicked at: ${event.point}');
          }
        },
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    print('iOS: Style loaded, adding earthquake source...');

    // Add GeoJSON source with clustering enabled
    const earthquakes = GeoJsonSource(
      id: 'earthquakes',
      data:
          'https://maplibre.org/maplibre-gl-js/docs/assets/earthquakes.geojson',
      cluster: true,
      clusterRadius: 50,
      clusterMaxZoom: 14,
    );
    await style.addSource(earthquakes);
    print('iOS: Added earthquake source');

    // Add layer for unclustered points FIRST (so it renders below clusters)
    const unclusteredLayer = CircleStyleLayer(
      id: 'unclustered-point',
      sourceId: 'earthquakes',
      filter: [
        '!',
        ['has', 'point_count'],
      ], // Only show features that DON'T have point_count (individual points)
      paint: {
        'circle-color': '#11b4da',
        'circle-radius': 4,
        'circle-stroke-width': 1,
        'circle-stroke-color': '#fff',
      },
    );
    await style.addLayer(unclusteredLayer);
    print('iOS: Added unclustered points layer');

    // Add layer for clusters (colored circles) - SECOND (renders above points)
    const clustersLayer = CircleStyleLayer(
      id: 'clusters',
      sourceId: 'earthquakes',
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
    await style.addLayer(clustersLayer);
    print('iOS: Added clusters layer');

    // Add layer for cluster count labels - LAST (renders on top of everything)
    const clusterCountLayer = SymbolStyleLayer(
      id: 'cluster-count',
      sourceId: 'earthquakes',
      filter: ['has', 'point_count'], // Only show labels for clusters
      layout: {
        'text-field': '{point_count_abbreviated}',
        'text-font': ['Open Sans Semibold'], // Use available font
        'text-size': 12,
      },
    );
    await style.addLayer(clusterCountLayer);
    print('iOS: Added cluster count layer');
  }
}
