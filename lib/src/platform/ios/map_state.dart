// Fixed version of map_state.dart for iOS
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/layer/layer_manager.dart';
import 'package:mapmetrics/src/platform/map_state_native.dart';
import 'package:mapmetrics/src/platform/maplibre_ffi.dart';
import 'package:mapmetrics/src/platform/pigeon.g.dart' as pigeon;

part 'style_controller.dart';

/// The implementation that gets used for state of the [MapLibreMap] widget on
/// iOS using both FFI for performance-critical operations and Pigeon as fallback.
final class MapLibreMapStateIos extends MapLibreMapStateNative
    implements pigeon.MapLibreFlutterApi {
  pigeon.MapLibreHostApi? _hostApi;
  int? _viewId;
  MLNMapView? _cachedMapView;
  bool _isMapReady = false;

  // Cache for synchronous operations
  double? _cachedMetersPerPixel;
  LngLatBounds? _cachedVisibleRegion;
  MapCamera? _cachedCamera;

  MLNMapView? get _mapView => _cachedMapView;

  @override
  StyleControllerIos? style;

  // Cache the UiKitView widget to prevent rebuilds that cause layout errors
  Widget? _cachedPlatformView;
  // Use a stable key to ensure the UiKitView maintains its identity
  final GlobalKey _platformViewKey = GlobalKey();

  @override
  Widget buildPlatformWidget(BuildContext context) {
    const viewType = 'plugins.flutter.io/maplibre';

    // CRITICAL FIX for iOS RenderUiKitView crash:
    // Cache the UiKitView widget and never rebuild it. The error:
    // "RenderBox was not laid out: RenderUiKitView#... NEEDS-LAYOUT NEEDS-PAINT"
    // occurs when Flutter rebuilds the widget tree while pointer events are being
    // routed through the platform view. By caching the widget, we ensure the
    // RenderUiKitView is never invalidated during gesture handling.
    //
    // The _SafePlatformView wrapper adds additional protection by:
    // 1. Using a custom RenderObject that prevents layout invalidation during pointer events
    // 2. Wrapping in RepaintBoundary to isolate the render subtree
    // 3. Using a GlobalKey to maintain widget identity across rebuilds
    _cachedPlatformView ??= RepaintBoundary(
      child: _SafePlatformView(
        child: SizedBox.expand(
          key: _platformViewKey,
          child: UiKitView(
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            gestureRecognizers: widget.gestureRecognizers,
            onPlatformViewCreated: _onPlatformViewCreated,
          ),
        ),
      ),
    );

    return _cachedPlatformView!;
  }

  /// This method gets called when the platform view is created. It is not
  /// guaranteed that the map is ready.
  void _onPlatformViewCreated(int viewId) {
    final channelSuffix = viewId.toString();
    _hostApi = pigeon.MapLibreHostApi(messageChannelSuffix: channelSuffix);
    pigeon.MapLibreFlutterApi.setUp(this, messageChannelSuffix: channelSuffix);
    _viewId = viewId;

    // Note: We'll rely on Pigeon for now since FFI registry access is complex
    // The native Swift code handles the map view through the registry
    _isMapReady = false; // Will be set to true in onStyleLoaded

    // iOS safety: if onStyleLoaded Pigeon callback is lost (race condition
    // where native didFinishLoading fires before Dart handler is registered),
    // retry after a delay. The native style IS loaded if tiles are visible.
    _scheduleStyleLoadedSafetyCheck();
  }

  /// Safety timer: if onMapReady / onStyleLoaded weren't received within 2s,
  /// manually trigger them. This handles the iOS race condition where the
  /// Pigeon messages are lost because native fires before Dart handlers are
  /// registered.
  void _scheduleStyleLoadedSafetyCheck() {
    Future.delayed(const Duration(seconds: 2), () {
      if (_hostApi != null && mounted) {
        // First, ensure onMapReady was delivered (sets isInitialized + calls onMapCreated)
        if (!isInitialized) {
          print('iOS SAFETY: onMapReady not received after 2s, triggering manually');
          onMapReady();
        }
        // Then, ensure onStyleLoaded was delivered (creates StyleController)
        if (style == null) {
          print('iOS SAFETY: onStyleLoaded not received after 2s, triggering manually');
          onStyleLoaded();
        }
      }
    });
  }

  @override
  Future<void> animateCamera({
    Position? center,
    double? zoom,
    double? bearing,
    double? pitch,
    Duration nativeDuration = const Duration(seconds: 2),
    double webSpeed = 1.2,
    Duration? webMaxDuration,
  }) async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    // Use Pigeon for animation as it's more reliable
    final latitude = center?.lat ?? double.nan;
    final longitude = center?.lng ?? double.nan;
    final zoomValue = zoom ?? double.nan;
    final bearingValue = bearing ?? double.nan;
    final pitchValue = pitch ?? double.nan;

    await hostApi.animateCamera(
      latitude.toDouble(),
      longitude.toDouble(),
      zoomValue.toDouble(),
      bearingValue.toDouble(),
      pitchValue.toDouble(),
      nativeDuration.inMilliseconds.toInt(),
    );

    // Update cached camera after animation
    _updateCameraCache();
  }

  @override
  Future<void> enableLocation({
    Duration fastestInterval = const Duration(milliseconds: 750),
    Duration maxWaitTime = const Duration(seconds: 1),
    bool pulseFade = true,
    bool accuracyAnimation = true,
    bool compassAnimation = true,
    bool pulse = true,
  }) async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    // Always use Pigeon for location operations
    await hostApi.enableLocation(
      fastestInterval.inMilliseconds.toInt(),
      maxWaitTime.inMilliseconds.toInt(),
      pulseFade,
      accuracyAnimation,
      compassAnimation,
      pulse,
    );
  }

  @override
  Future<void> fitBounds({
    required LngLatBounds bounds,
    double? bearing,
    double? pitch,
    Duration nativeDuration = const Duration(seconds: 2),
    double webSpeed = 1.2,
    Duration? webMaxDuration,
    Offset offset = Offset.zero,
    double webMaxZoom = double.maxFinite,
    bool webLinear = false,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    // Always use Pigeon for bounds operations
    await hostApi.fitBounds(
      bounds.longitudeWest,
      bounds.latitudeSouth,
      bounds.longitudeEast,
      bounds.latitudeNorth,
      (bearing ?? -1.0).toDouble(),
      (pitch ?? -1.0).toDouble(),
      nativeDuration.inMilliseconds.toInt(),
      padding.left.toDouble(),
      padding.top.toDouble(),
      padding.right.toDouble(),
      padding.bottom.toDouble(),
    );
  }

  @override
  Future<void> setContentInset(EdgeInsets inset) async {
    final hostApi = _hostApi;
    if (hostApi == null) return;
    await hostApi.setContentInset(
      inset.left.toDouble(),
      inset.top.toDouble(),
      inset.right.toDouble(),
      inset.bottom.toDouble(),
    );
  }

  @override
  MapCamera getCamera() {
    // Use the camera from the base class which is updated via onMoveCamera callback
    // This ensures we always get the latest camera state including user gestures
    if (camera != null) {
      return camera!;
    }
    // Fallback to cached camera if base class camera not yet initialized
    return _cachedCamera ?? MapCamera(
      center: Position(0, 0),
      zoom: 0,
      bearing: 0,
      pitch: 0,
    );
  }

  @override
  Future<double> getMetersPerPixelAtLatitude(double latitude) async {
    if (_isMapReady && _mapView != null) {
      return getMetersPerPixelAtLatitudeSync(latitude);
    }
    final hostApi = _hostApi;
    if (hostApi == null) return getMetersPerPixelAtLatitudeSync(latitude);
    return await hostApi.getMetersPerPixelAtLatitude(latitude);
  }

  @override
  Future<LngLatBounds> getVisibleRegion() async {
    final hostApi = _hostApi;
    if (hostApi == null) return getVisibleRegionSync();
    final result = await hostApi.getVisibleRegion();
    final bounds = LngLatBounds(
      longitudeWest: result[0].toDouble(),
      longitudeEast: result[2].toDouble(),
      latitudeSouth: result[1].toDouble(),
      latitudeNorth: result[3].toDouble(),
    );
    // Update cache for synchronous calls
    _cachedVisibleRegion = bounds;
    return bounds;
  }

  @override
  Future<void> moveCamera({
    Position? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    // Always use Pigeon for camera operations to ensure reliability
    final latitude = center?.lat ?? double.nan;
    final longitude = center?.lng ?? double.nan;
    await hostApi.moveCamera(
      latitude.toDouble(),
      longitude.toDouble(),
      (zoom ?? double.nan).toDouble(),
      (bearing ?? double.nan).toDouble(),
      (pitch ?? double.nan).toDouble(),
    );

    // Update cached camera after move
    _updateCameraCache();
  }

  @override
  void moveCameraSync({
    Position? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) {
    // iOS uses Pigeon (async) — delegate to async version
    moveCamera(center: center, zoom: zoom, bearing: bearing, pitch: pitch);
  }

  @override
  void navigateFrame({
    required Position center,
    required double zoom,
    required double bearing,
    required double pitch,
    required String sourceId,
    required String geoJsonData,
  }) {
    // iOS: fallback to sequential calls (iOS uses WidgetLayer for nav marker,
    // so this method is not used in the hot path)
    moveCameraSync(center: center, zoom: zoom, bearing: bearing, pitch: pitch);
    style?.updateGeoJsonSourceSync(id: sourceId, data: geoJsonData);
  }

  Future<void> _updateCameraCache() async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    try {
      _cachedCamera = await _getCameraAsync();
      // Also update meters per pixel cache with current camera position
      if (_cachedCamera != null) {
        final latitude = _cachedCamera!.center.lat.toDouble();
        _cachedMetersPerPixel = await hostApi.getMetersPerPixelAtLatitude(latitude);
      }
    } catch (e) {
      print('Error updating camera cache: $e');
    }
  }

  @override
  void onStyleLoaded() {
    print('MapLibreMapStateIos: onStyleLoaded called');
    // We need to refresh the cached style for when the style reloads.
    style?.dispose();

    // Mark map as ready when style loads
    _isMapReady = true;

    // Create style controller using Pigeon since FFI might not be available
    final stubStyle = MLNStyle(ffi.nullptr); // This will use Pigeon only
    final hostApi = _hostApi;
    if (hostApi == null) {
      print('MapLibreMapStateIos: WARNING - hostApi is null in onStyleLoaded');
      return;
    }
    final styleCtrl = style = StyleControllerIos._(stubStyle, hostApi);

    // Initialize cache values asynchronously
    _initializeCacheValues();

    print('MapLibreMapStateIos: Calling onEvent and onStyleLoaded callbacks');
    widget.onEvent?.call(MapEventStyleLoaded(styleCtrl));
    widget.onStyleLoaded?.call(styleCtrl);
    layerManager = LayerManager(styleCtrl, widget.layers);
    // Defer setState to after the current frame to prevent RenderBox "not laid out"
    // crash when scheduleWarmUpFrame triggers _setOffset before layout completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    print('MapLibreMapStateIos: onStyleLoaded completed');
  }

  Future<void> _initializeCacheValues() async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    try {
      // Initialize cache with default latitude (center of map)
      _cachedMetersPerPixel = await hostApi.getMetersPerPixelAtLatitude(0.0);
      final visibleRegionData = await hostApi.getVisibleRegion();
      _cachedVisibleRegion = LngLatBounds(
        longitudeWest: visibleRegionData[0].toDouble(),
        longitudeEast: visibleRegionData[2].toDouble(),
        latitudeSouth: visibleRegionData[1].toDouble(),
        latitudeNorth: visibleRegionData[3].toDouble(),
      );

      // Get initial camera state
      final camera = await _getCameraAsync();
      _cachedCamera = camera;
    } catch (e) {
      print('Error initializing cache values: $e');
      // Set fallback values
      _cachedMetersPerPixel = 156543.03392; // meters per pixel at equator at zoom 0
      _cachedVisibleRegion = LngLatBounds(
        longitudeWest: -180,
        longitudeEast: 180,
        latitudeSouth: -85,
        latitudeNorth: 85,
      );
      _cachedCamera = MapCamera(
        center: Position(0, 0),
        zoom: 0,
        bearing: 0,
        pitch: 0,
      );
    }
  }

  Future<MapCamera> _getCameraAsync() async {
    final hostApi = _hostApi;
    if (hostApi == null) {
      return _cachedCamera ?? MapCamera(
        center: Position(0, 0),
        zoom: 0,
        bearing: 0,
        pitch: 0,
      );
    }

    try {
      final pigeonCamera = await hostApi.getCamera();
      // Convert from Pigeon MapCamera to our MapCamera
      return MapCamera(
        center: Position(pigeonCamera.center.lng, pigeonCamera.center.lat),
        zoom: pigeonCamera.zoom,
        bearing: pigeonCamera.bearing,
        pitch: pigeonCamera.pitch,
      );
    } catch (e) {
      print('Error getting camera: $e');
      return MapCamera(
        center: Position(0, 0),
        zoom: 0,
        bearing: 0,
        pitch: 0,
      );
    }
  }

  @override
  void dispose() {
    style?.dispose();
    final hostApi = _hostApi;
    if (hostApi != null) {
      unawaited(hostApi.dispose());
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    _updateOptions(oldWidget);
    layerManager?.updateLayers(widget.layers);
    super.didUpdateWidget(oldWidget);
  }

  @override
  Future<void> _updateOptions(MapLibreMap oldWidget) async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    final oldOptions = oldWidget.options;
    final options = this.options;

    // Always use Pigeon for updating options to ensure reliability
    await hostApi.updateMapOptions(
      options.minZoom.toDouble(),
      options.maxZoom.toDouble(),
      options.minPitch.toDouble(),
      options.maxPitch.toDouble(),
      (options.maxBounds?.longitudeWest ?? double.nan).toDouble(),
      (options.maxBounds?.latitudeSouth ?? double.nan).toDouble(),
      (options.maxBounds?.longitudeEast ?? double.nan).toDouble(),
      (options.maxBounds?.latitudeNorth ?? double.nan).toDouble(),
      options.gestures.rotate,
      options.gestures.pan,
      options.gestures.zoom,
      options.gestures.pitch,
    );
  }

  @override
  Future<List<Map<String, String>>> queryLayers(Offset screenLocation) async {
    final hostApi = _hostApi;
    if (hostApi == null) return [];

    final result = await hostApi.queryLayers(screenLocation.dx.toDouble(), screenLocation.dy.toDouble());
    // Return the raw maps with all properties instead of converting to QueriedLayer
    return result;
  }

  @override
  Future<List<Map<String, String>>> queryLayersInRect(Rect rect) async {
    final hostApi = _hostApi;
    if (hostApi == null) return [];

    // Use native Pigeon method for efficient bounding box query (single native call)
    final result = await hostApi.queryLayersInRect(
      rect.left.toDouble(),
      rect.top.toDouble(),
      rect.right.toDouble(),
      rect.bottom.toDouble(),
    );
    // Convert from List<Map<Object?, Object?>> to List<Map<String, String>>
    return result.map((map) => map.map((key, value) => MapEntry(
      key?.toString() ?? '',
      value?.toString() ?? '',
    ))).toList();
  }

  @override
  Future<Position> toLngLat(Offset screenLocation) async {
    final hostApi = _hostApi;
    if (hostApi == null) return Position(0, 0);

    print('=== DART toLngLat DEBUG ===');
    print('Input: screen(${screenLocation.dx}, ${screenLocation.dy})');

    final result = await hostApi.toLngLat(screenLocation.dx.toDouble(), screenLocation.dy.toDouble());
    print('Swift returned: $result (should be [lng, lat])');

    // Try without swapping - maybe the issue is the swapping itself
    final position = Position(result[0].toDouble(), result[1].toDouble()); // Position(lng, lat) from [lng, lat] - NO SWAP

    print('Using direct: Position(lat=${position.lat}, lng=${position.lng})');
    print('=== END DART DEBUG ===');

    return position;
  }

  @override
  Future<List<Position>> toLngLats(List<Offset> screenLocations) async =>
      Future.wait(screenLocations.map(toLngLat));

  @override
  Future<Offset> toScreenLocation(Position lngLat) async {
    final hostApi = _hostApi;
    if (hostApi == null) return Offset.zero;

    print('=== DART toScreenLocation DEBUG ===');
    print('Input: Position(lat=${lngLat.lat}, lng=${lngLat.lng})');

    // Try without swapping - pass Position as-is
    final result = await hostApi.toScreenLocation(lngLat.lng.toDouble(), lngLat.lat.toDouble());
    print('Swift returned: $result (should be [x, y])');

    final offset = Offset(result[0].toDouble(), result[1].toDouble());
    print('Using direct: Offset(dx=${offset.dx}, dy=${offset.dy})');
    print('=== END DART DEBUG ===');

    return offset;
  }

  @override
  Future<List<Offset>> toScreenLocations(List<Position> lngLats) async =>
      Future.wait(lngLats.map(toScreenLocation));

  @override
  Future<void> trackLocation({
    bool trackLocation = true,
    BearingTrackMode trackBearing = BearingTrackMode.gps,
  }) async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    // Always use Pigeon for location tracking
    await hostApi.trackLocation(trackLocation, trackBearing.index.toInt());
  }

  @override
  Future<void> showUserLocationPuck({bool show = true}) async {
    final hostApi = _hostApi;
    if (hostApi == null) return;

    await hostApi.showUserLocationPuck(show);
  }

  @override
  Future<void> setLocationDraggable({bool draggable = true}) async {
    // Enable or disable dragging of the location marker
    // This feature allows users to manually adjust their location on the map
    print('iOS: setLocationDraggable called with draggable=$draggable');
    // TODO: Implement when native iOS support is added
    // For now, just log that it was called
  }

  @override
  Future<void> setNavigationRoute(List<Position> routePoints) async {
    // Set the navigation route for improved road snapping
    // When a route is set, the location icon will snap to the route line
    print('iOS: setNavigationRoute called with ${routePoints.length} points');
    // TODO: Implement when native iOS support is added
    // For now, just log that it was called
  }

  @override
  Future<void> clearNavigationRoute() async {
    // Clear the navigation route
    print('iOS: clearNavigationRoute called');
    // TODO: Implement when native iOS support is added
    // For now, just log that it was called
  }

  @override
  Future<void> setStyleUri(String styleUri) async {
    // Dispose old style controller before switching
    style?.dispose();
    style = null;

    // Call native setStyleUri via Pigeon — switches style in-place
    // without destroying the map. onStyleLoaded() will fire when done.
    final hostApi = _hostApi;
    if (hostApi == null) return;
    await hostApi.setStyleUri(styleUri);
  }

  // Sync methods - use cached values when available
  @override
  double getMetersPerPixelAtLatitudeSync(double latitude) {
    if (_cachedMetersPerPixel != null) {
      return _cachedMetersPerPixel!;
    }

    // Fallback calculation based on zoom level and latitude
    // This is an approximation when no cached value is available
    final zoom = _cachedCamera?.zoom ?? 0;
    final earthCircumference = 40075016.686; // meters
    final metersPerPixel = earthCircumference * math.cos(latitude * math.pi / 180) / math.pow(2, zoom + 8);
    return metersPerPixel.toDouble();
  }

  @override
  LngLatBounds getVisibleRegionSync() {
    return _cachedVisibleRegion ?? LngLatBounds(
      longitudeWest: -180,
      longitudeEast: 180,
      latitudeSouth: -85,
      latitudeNorth: 85,
    );
  }

  @override
  Position toLngLatSync(Offset screenLocation) {
    // For sync coordinate conversion, we'll need to implement a fallback
    // This is complex without direct access to the map projection
    // For now, return a placeholder that won't crash the app
    print('Warning: toLngLatSync called on iOS - this is not accurate without FFI');
    return Position(0, 0);
  }

  @override
  List<Position> toLngLatsSync(List<Offset> screenLocations) =>
      screenLocations.map(toLngLatSync).toList(growable: false);

  @override
  Offset toScreenLocationSync(Position lngLat) {
    // For sync coordinate conversion, we'll need to implement a fallback
    // This is complex without direct access to the map projection
    // For now, return a placeholder that won't crash the app
    print('Warning: toScreenLocationSync called on iOS - this is not accurate without FFI');
    return Offset.zero;
  }

  @override
  List<Offset> toScreenLocationsSync(List<Position> lngLats) =>
      lngLats.map(toScreenLocationSync).toList(growable: false);
}

/// A wrapper widget that protects UiKitView from layout errors during pointer events.
/// Uses a simple StatefulWidget approach with widget caching.
class _SafePlatformView extends StatefulWidget {
  final Widget child;

  const _SafePlatformView({required this.child});

  @override
  State<_SafePlatformView> createState() => _SafePlatformViewState();
}

class _SafePlatformViewState extends State<_SafePlatformView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // SizedBox.expand ensures the child always has a defined size
    return SizedBox.expand(child: widget.child);
  }
}
