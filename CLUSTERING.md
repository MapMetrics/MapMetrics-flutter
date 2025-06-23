# Clustering Support in MapMetrics Flutter

MapMetrics Flutter now supports clustering for GeoJSON point data. This feature allows you to group nearby points into clusters when zoomed out, improving performance and readability.

## Features

- **Automatic Clustering**: Points within a specified radius are automatically grouped into clusters
- **Configurable Cluster Radius**: Control how close points need to be to form a cluster
- **Maximum Zoom Level**: Set the zoom level at which clustering stops
- **Cluster Properties**: Aggregate properties from clustered points (coming soon)

## Usage

### Basic Clustering

To enable clustering on a GeoJSON source, simply add the clustering parameters:

```dart
const earthquakes = GeoJsonSource(
  id: 'earthquakes',
  data: 'https://gateway.mapmetrics.org/assets/earthquakes.geojson',
  cluster: true,           // Enable clustering
  clusterRadius: 50,       // Cluster radius in pixels
  clusterMaxZoom: 14,      // Max zoom level for clustering
);
```

### Adding Layers for Clusters

You'll need to add multiple layers to properly display clusters:

1. **Cluster Circles**: Visual representation of clusters
2. **Cluster Count Labels**: Show the number of points in each cluster
3. **Unclustered Points**: Individual points when not clustered

```dart
// Layer for cluster circles
const clustersLayer = CircleStyleLayer(
  id: 'clusters',
  sourceId: 'earthquakes',
  paint: {
    'circle-color': [
      'step',
      ['get', 'point_count'],
      '#51bbd6',  // Color for small clusters
      100,
      '#f1f075',  // Color for medium clusters
      750,
      '#f28cb1',  // Color for large clusters
    ],
    'circle-radius': [
      'step',
      ['get', 'point_count'],
      20,   // Size for small clusters
      100,
      30,   // Size for medium clusters
      750,
      40,   // Size for large clusters
    ],
  },
);

// Layer for cluster count labels
const clusterCountLayer = SymbolStyleLayer(
  id: 'cluster-count',
  sourceId: 'earthquakes',
  layout: {
    'text-field': '{point_count_abbreviated}',
    'text-font': ['Noto Sans Medium'],
    'text-size': 12,
  },
);

// Layer for unclustered points
const unclusteredLayer = CircleStyleLayer(
  id: 'unclustered-point',
  sourceId: 'earthquakes',
  paint: {
    'circle-color': '#11b4da',
    'circle-radius': 4,
    'circle-stroke-width': 1,
    'circle-stroke-color': '#fff',
  },
);
```

### Complete Example

Here's a complete example showing how to implement clustering:

```dart
class ClusteringExample extends StatefulWidget {
  @override
  State<ClusteringExample> createState() => _ClusteringExampleState();
}

class _ClusteringExampleState extends State<ClusteringExample> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clustering Example')),
      body: MapMetricsView(
        options: MapOptions(
          initCenter: Position(-103.59179687498357, 40.66995747013945),
          initZoom: 3,
        ),
        onStyleLoaded: _onStyleLoaded,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    // Add GeoJSON source with clustering
    const earthquakes = GeoJsonSource(
      id: 'earthquakes',
      data: 'https://gateway.mapmetrics.org/assets/earthquakes.geojson',
      cluster: true,
      clusterRadius: 50,
      clusterMaxZoom: 14,
    );
    await style.addSource(earthquakes);

    // Add cluster layers
    await style.addLayer(clustersLayer);
    await style.addLayer(clusterCountLayer);
    await style.addLayer(unclusteredLayer);
  }
}
```

## Configuration Options

### GeoJsonSource Clustering Parameters

- **`cluster`** (bool, default: false): Enable or disable clustering
- **`clusterRadius`** (int, default: 50): The radius of each cluster in pixels
- **`clusterMaxZoom`** (int, optional): Maximum zoom level at which to cluster points
- **`clusterProperties`** (Map<String, List<Object>>, optional): Properties to aggregate from clustered points

### Cluster Radius Guidelines

- **50 pixels**: Good for most use cases, provides a balance between performance and detail
- **30 pixels**: Tighter clustering, shows more individual points
- **80 pixels**: Looser clustering, better for very dense datasets

### Maximum Zoom Level

The `clusterMaxZoom` parameter determines when clustering stops:
- **14**: Good for city-level detail
- **16**: Good for neighborhood-level detail
- **18**: Good for street-level detail

## Platform Support

Clustering is supported on:
- ✅ Android (using MapLibre Android SDK)
- ✅ iOS (using MapLibre iOS SDK)
- 🔄 Web (support coming soon)

## Example in the Demo App

You can see clustering in action by running the demo app and navigating to:
**Style Layers > Clustering**

This example shows earthquake data with automatic clustering based on zoom level and proximity.

## Performance Benefits

Clustering provides significant performance improvements for large datasets:
- Reduces the number of rendered elements
- Improves map responsiveness
- Better memory usage
- Smoother zoom and pan operations

## Future Enhancements

- Cluster property aggregation
- Custom cluster icons
- Cluster click handling
- Animated cluster transitions 