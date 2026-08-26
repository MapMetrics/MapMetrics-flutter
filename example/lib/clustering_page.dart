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
          // Opens at 3, not 4. The 15 test points span Europe; at zoom 4 they
          // are far enough apart that none of them merge, so the page showed
          // loose individual dots and no cluster bubbles at all -- a
          // clustering example demonstrating no clustering. At 3 they group
          // and the counts are visible on open. Zooming in still shows
          // clusters splitting apart, which is the other half of the point.
          initZoom: 3,
          minZoom: 1, // Allow zooming out to level 1
          maxZoom: 20, // Allow zooming in to level 20
        ),
        onStyleLoaded: _onStyleLoaded,
        mapChildren: const [
          MapScalebar(
            padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 50),
          ),
          SourceAttribution(),
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
        'text-font': ['Noto Sans Medium'],
        // NOT 'Open Sans Semibold'. The comment here used to say "use
        // available font" while naming one the glyph endpoint does not
        // serve: .../fonts/Open%20Sans%20Semibold/0-255.pbf returns 404.
        // A missing fontstack means the text simply never renders, with no
        // error -- so the clusters drew as circles with no counts in them.
        // Verified against the glyph CDN, per fontstack, ranges 0-255 and
        // 256-511: Noto Sans Regular/Medium/Italic and Montserrat Bold
        // return 200; every Open Sans weight, Noto Sans Bold/SemiBold/Light,
        // Montserrat Regular/SemiBold, Roboto and Inter return 404.
        // Noto Sans Medium is chosen over Montserrat Bold because the demo
        // style's own layers use it, so it cannot be pruned without
        // breaking the basemap.
        'text-size': 12,
      },
    );
    print('ClusteringPage: About to add cluster count layer');
    await style.addLayer(clusterCountLayer);
    print('ClusteringPage: Added cluster count layer');
  }
}
