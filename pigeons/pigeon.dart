import 'package:pigeon/pigeon.dart';

/// A longitude/latitude coordinate object.
class LngLat {
  const LngLat({required this.lng, required this.lat});

  /// The longitude
  final double lng;

  /// The latitude
  final double lat;
}

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/pigeon.g.dart',
    dartOptions: DartOptions(),
    dartPackageName: 'mapmetrics',
    copyrightHeader: 'pigeons/header.txt',
    // linux
    gobjectHeaderOut: 'linux/pigeon.g.h',
    gobjectSourceOut: 'linux/pigeon.g.cc',
    gobjectOptions: GObjectOptions(),
    // windows
    cppOptions: CppOptions(namespace: 'pigeon_maplibre'),
    cppHeaderOut: 'windows/runner/pigeon.g.h',
    cppSourceOut: 'windows/runner/pigeon.g.cpp',
    // android
    kotlinOut:
    'android/src/main/kotlin/com/github/mapmetrics/maplibre/Pigeon.g.kt',
    kotlinOptions: KotlinOptions(),
    // ios
    swiftOut: 'ios/mapmetrics/Sources/maplibre_ios/Pigeon.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
@HostApi()
abstract class MapLibreHostApi {
  void dispose();

  /// Add a fill layer to the map style.
  @async
  void addFillLayer({
    required String id,
    required String sourceId,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Add a circle layer to the map style.
  @async
  void addCircleLayer({
    required String id,
    required String sourceId,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Add a background layer to the map style.
  @async
  void addBackgroundLayer({
    required String id,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Add a fill extrusion layer to the map style.
  @async
  void addFillExtrusionLayer({
    required String id,
    required String sourceId,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Add a heatmap layer to the map style.
  @async
  void addHeatmapLayer({
    required String id,
    required String sourceId,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Add a hillshade layer to the map style.
  @async
  void addHillshadeLayer({
    required String id,
    required String sourceId,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Add a line layer to the map style.
  @async
  void addLineLayer({
    required String id,
    required String sourceId,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Add a raster layer to the map style.
  @async
  void addRasterLayer({
    required String id,
    required String sourceId,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Add a symbol layer to the map style.
  @async
  void addSymbolLayer({
    required String id,
    required String sourceId,
    required Map<String, Object> layout,
    required Map<String, Object> paint,
    String? belowLayerId,
  });

  /// Loads an image to the map. An image needs to be loaded before it can
  /// get used.
  @async
  Uint8List loadImage(String url);

  /// Add an image to the map.
  @async
  void addImage(String id, Uint8List bytes);

  /// Add multiple images to the map in a single batch operation.
  /// This is significantly faster than calling addImage multiple times.
  @async
  void addImages(List<String> ids, List<Uint8List> images);

  /// Load a sprite sheet and add all icons to the map in a single native operation.
  /// This is the fastest way to load many icons - all extraction happens natively.
  /// spriteJson: The sprite.json content as a string
  /// spriteImage: The sprite.png as bytes
  @async
  void addSprite(String spriteJson, Uint8List spriteImage);

  /// Add a GeoJSON source with clustering to the map style.
  @async
  void addClusteredGeoJsonSource({
    required String id,
    required String data,
    required bool clustered,
    required double clusterRadius,
    required double clusterMaxZoom,
    String? clusterPropertiesJson,
  });

  /// Add a vector source to the map style.
  @async
  void addVectorSource({
    required String id,
    required List<String> tiles,
    required double minZoom,
    required double maxZoom,
  });

  /// Add a raster source to the map style.
  @async
  void addRasterSource({
    required String id,
    required List<String> tiles,
    required double minZoom,
    required double maxZoom,
    required double tileSize,
    String? attribution,
  });

  /// Minimal test method to debug Pigeon generation.
  @async
  void testMethod(String value);

  /// Animate the camera to a new position.
  /// Use -1.0 or double.nan for any value you do not want to change.
  @async
  void animateCamera(
      double latitude,
      double longitude,
      double zoom,
      double bearing,
      double pitch,
      int duration,
      );

  /// Get the current camera state.
  MapCamera getCamera();

  /// Get the current zoom level.
  double getZoomLevel();

  /// Get the user's current location.
  LngLat getUserLocation();

  /// Move the camera to a new position without animation.
  /// Use -1.0 or double.nan for any value you do not want to change.
  @async
  void moveCamera(double lat, double lng, double zoom, double bearing, double pitch);

  /// Update map options including bounds and gesture settings.
  @async
  void updateMapOptions(
      double minZoom,
      double maxZoom,
      double minPitch,
      double maxPitch,
      double boundsWest,
      double boundsSouth,
      double boundsEast,
      double boundsNorth,
      bool rotateEnabled,
      bool panEnabled,
      bool zoomEnabled,
      bool pitchEnabled
      );

  /// Enable location services and show user location on map.
  @async
  void enableLocation(
      int fastestInterval,
      int maxWaitTime,
      bool pulseFade,
      bool accuracyAnimation,
      bool compassAnimation,
      bool pulse
      );

  /// Fit the map camera to show the specified bounds.
  @async
  void fitBounds(
      double west,
      double south,
      double east,
      double north,
      double bearing,
      double pitch,
      int duration,
      double paddingLeft,
      double paddingTop,
      double paddingRight,
      double paddingBottom
      );

  /// Set the persistent viewport content inset (in logical pixels). After this
  /// call, ALL subsequent camera operations (moveCamera, animateCamera, etc.)
  /// treat the inset rectangle as the effective viewport — the camera `center`
  /// lat/lng projects to the geometric center of that rectangle, and bearing
  /// pivots around it. Used for navigation to keep the user puck low on screen
  /// while ensuring rotation pivots through the puck.
  @async
  void setContentInset(
      double left,
      double top,
      double right,
      double bottom
      );

  /// Get the meters per pixel at the specified latitude.
  @async
  double getMetersPerPixelAtLatitude(double latitude);

  /// Get the visible region bounds.
  /// Returns [west, south, east, north]
  @async
  List<double> getVisibleRegion();

  /// Convert screen coordinates to longitude/latitude.
  /// Returns [lng, lat]
  @async
  List<double> toLngLat(double x, double y);

  /// Convert longitude/latitude to screen coordinates.
  /// Returns [x, y]
  @async
  List<double> toScreenLocation(double lng, double lat);

  /// Query rendered layers at the specified screen location.
  @async
  List<Map<String, String>> queryLayers(double x, double y);

  /// Query rendered layers within a bounding box (more efficient for hit detection).
  /// [left], [top], [right], [bottom] define the screen-space bounding box.
  /// Returns list of maps (Object? used for platform compatibility).
  @async
  List<Map<Object?, Object?>> queryLayersInRect(double left, double top, double right, double bottom);

  /// Enable/disable location tracking with bearing mode.
  @async
  void trackLocation(bool track, int bearingMode);

  /// Show/hide the user location puck (blue dot).
  @async
  void showUserLocationPuck(bool show);

  @async
  void removeLayer(String id);

  @async
  void removeSource(String id);

  @async
  void updateGeoJsonSource(String id, String data);

  /// Switch the map style in-place without destroying the map.
  /// This avoids the native SIGSEGV that occurs when the map widget is
  /// destroyed while GeoJSON messages are still queued on the Looper.
  @async
  void setStyleUri(String styleUri);

}

@FlutterApi()
abstract class MapLibreFlutterApi {
  /// Get the map options from dart.
  MapOptions getOptions();

  /// Callback for when the style has been loaded.
  void onStyleLoaded();

  /// Callback for when the map is ready and can be used.
  void onMapReady();

  /// Callback when the user clicks on the map.
  void onClick(LngLat point);

  /// Callback when the map idles.
  void onIdle();

  /// Callback when the map camera idles.
  void onCameraIdle();

  /// Callback when the user performs a secondary click on the map
  /// (e.g. by default a click with the right mouse button).
  void onSecondaryClick(LngLat point);

  /// Callback when the user performs a double click on the map.
  void onDoubleClick(LngLat point);

  /// Callback when the user performs a long lasting click on the map.
  void onLongClick(LngLat point);

  /// Callback when the map camera changes.
  void onMoveCamera(MapCamera camera);

  /// Callback when the map camera starts changing.
  void onStartMoveCamera(CameraChangeReason reason);
}

@HostApi()
// ignore: one_member_abstracts
abstract class PermissionManagerHostApi {
  /// Request location permissions.
  @async
  bool requestLocationPermissions({required String explanation});
}

@HostApi()
abstract class OfflineManagerHostApi {
  /// Clear the ambient cache.
  @async
  void clearAmbientCache();

  /// Invalidate the ambient cache.
  @async
  void invalidateAmbientCache();

  /// Reset database.
  @async
  void resetDatabase();

  /// Set maximum ambient cache size.
  @async
  void setMaximumAmbientCacheSize({required int bytes});

  /// Download a map region.
  @async
  void downloadRegion({
    required String mapStyleUrl,
    required LngLatBounds bounds,
    required double minZoom,
    required double maxZoom,
    required double pixelDensity,
    required String metadata,
  });
}

/// The map options define initial values for the MapLibre map.
class MapOptions {
  const MapOptions({
    required this.style,
    required this.zoom,
    required this.center,
    required this.pitch,
    required this.bearing,
    required this.maxBounds,
    required this.minZoom,
    required this.maxZoom,
    required this.minPitch,
    required this.maxPitch,
    required this.gestures,
    required this.androidTextureMode,
    required this.apiKey,
  });

  /// The URL of the used map style.
  final String style;

  /// The MapMetrics maps-scoped API key. Passed to the native SDK so that the
  /// v2 map session can be established. `null` keeps the legacy behaviour
  /// (auth via the JWT embedded in the style URL).
  final String? apiKey;

  /// The initial zoom level of the map.
  final double zoom;

  /// The initial pitch / tilt of the map.
  final double pitch;

  /// The initial bearing of the map.
  final double bearing;

  /// The initial center coordinates of the map.
  final LngLat? center;

  /// The maximum bounding box of the map camera.
  final LngLatBounds? maxBounds;

  /// The minimum zoom level of the map.
  final double minZoom;

  /// The maximum zoom level of the map.
  final double maxZoom;

  /// The minimum pitch / tilt of the map.
  final double minPitch;

  /// The maximum pitch / tilt of the map.
  final double maxPitch;

  /// The map gestures.
  final MapGestures gestures;

  /// Toggle the texture mode on android.
  final bool androidTextureMode;
}

/// Map gestures
class MapGestures {
  /// Create a new [MapGestures] object by setting all gestures.
  const MapGestures({
    required this.rotate,
    required this.pan,
    required this.zoom,
    required this.tilt,
  });

  /// Rotate the map bearing.
  final bool rotate;

  /// Move the center of the map around.
  final bool pan;

  /// Zoom the map in and out.
  final bool zoom;

  /// Tilt (pitch) the map camera.
  final bool tilt;
}

/// A pixel location / location on the device screen.
class Offset {
  const Offset({required this.x, required this.y});

  /// The x coordinate
  final double x;

  /// The y coordinate
  final double y;
}

/// Camera Padding
class Padding {
  const Padding({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  final int top;
  final int bottom;
  final int left;
  final int right;
}

/// The current position of the map camera.
class MapCamera {
  const MapCamera({
    required this.center,
    required this.zoom,
    required this.pitch,
    required this.bearing,
  });

  final LngLat center;
  final double zoom;
  final double pitch;
  final double bearing;
}

/// LatLng bound object
class LngLatBounds {
  const LngLatBounds({
    required this.longitudeWest,
    required this.longitudeEast,
    required this.latitudeSouth,
    required this.latitudeNorth,
  });

  final double longitudeWest;
  final double longitudeEast;
  final double latitudeSouth;
  final double latitudeNorth;
}

/// Model that describes an offline map region.
class OfflineRegion {
  const OfflineRegion({
    required this.id,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.pixelRatio,
    required this.styleUrl,
  });

  final int id;
  final LngLatBounds bounds;
  final double minZoom;
  final double maxZoom;
  final double pixelRatio;
  final String styleUrl;
}

/// Influences the y direction of the tile coordinates.
enum TileScheme {
  /// Slippy map tilenames scheme.
  xyz,

  /// OSGeo spec scheme.
  tms,
}

/// The encoding used by this source. Mapbox Terrain RGB is used by default.
enum RasterDemEncoding {
  /// Terrarium format PNG tiles.
  terrarium,

  /// Mapbox Terrain RGB tiles.
  mapbox,

  /// Decodes tiles using the redFactor, blueFactor, greenFactor, baseShift
  /// parameters.
  custom,
}

/// The reason the camera is changing.
enum CameraChangeReason {
  /// Developer animation.
  developerAnimation,

  /// API animation.
  apiAnimation,

  /// API gesture
  apiGesture,
}

void main() {
  // This function is required for pigeon code generation
}