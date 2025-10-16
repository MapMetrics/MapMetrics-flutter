// Fixed version of map_state.dart for iOS
import 'dart:async';
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
  late final pigeon.MapLibreHostApi _hostApi;
  late final int _viewId;
  MLNMapView? _cachedMapView;
  bool _isMapReady = false;

  // Cache for synchronous operations
  double? _cachedMetersPerPixel;
  LngLatBounds? _cachedVisibleRegion;
  MapCamera? _cachedCamera;

  MLNMapView? get _mapView => _cachedMapView;

  @override
  StyleControllerIos? style;

  @override
  Widget buildPlatformWidget(BuildContext context) {
    const viewType = 'plugins.flutter.io/maplibre';
    return UiKitView(
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      gestureRecognizers: widget.gestureRecognizers,
      onPlatformViewCreated: _onPlatformViewCreated,
    );
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
    // Use Pigeon for animation as it's more reliable
    final latitude = center?.lat ?? double.nan;
    final longitude = center?.lng ?? double.nan;
    final zoomValue = zoom ?? double.nan;
    final bearingValue = bearing ?? double.nan;
    final pitchValue = pitch ?? double.nan;

    await _hostApi.animateCamera(
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
    // Always use Pigeon for location operations
    await _hostApi.enableLocation(
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
    // Always use Pigeon for bounds operations
    await _hostApi.fitBounds(
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
  MapCamera getCamera() {
    // Return cached camera if available, otherwise return a default
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
    return await _hostApi.getMetersPerPixelAtLatitude(latitude);
  }

  @override
  Future<LngLatBounds> getVisibleRegion() async {
    final result = await _hostApi.getVisibleRegion();
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
    // Always use Pigeon for camera operations to ensure reliability
    final latitude = center?.lat ?? double.nan;
    final longitude = center?.lng ?? double.nan;
    await _hostApi.moveCamera(
      latitude.toDouble(),
      longitude.toDouble(),
      (zoom ?? double.nan).toDouble(),
      (bearing ?? double.nan).toDouble(),
      (pitch ?? double.nan).toDouble(),
    );

    // Update cached camera after move
    _updateCameraCache();
  }

  Future<void> _updateCameraCache() async {
    try {
      _cachedCamera = await _getCameraAsync();
      // Also update meters per pixel cache with current camera position
      if (_cachedCamera != null) {
        final latitude = _cachedCamera!.center.lat.toDouble();
        _cachedMetersPerPixel = await _hostApi.getMetersPerPixelAtLatitude(latitude);
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
    final styleCtrl = style = StyleControllerIos._(stubStyle, _hostApi);

    // Initialize cache values asynchronously
    _initializeCacheValues();

    print('MapLibreMapStateIos: Calling onEvent and onStyleLoaded callbacks');
    widget.onEvent?.call(MapEventStyleLoaded(styleCtrl));
    widget.onStyleLoaded?.call(styleCtrl);
    layerManager = LayerManager(styleCtrl, widget.layers);
    setState(() {});
    print('MapLibreMapStateIos: onStyleLoaded completed');
  }

  Future<void> _initializeCacheValues() async {
    try {
      // Initialize cache with default latitude (center of map)
      _cachedMetersPerPixel = await _hostApi.getMetersPerPixelAtLatitude(0.0);
      final visibleRegionData = await _hostApi.getVisibleRegion();
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
    try {
      final pigeonCamera = await _hostApi.getCamera();
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
    unawaited(_hostApi.dispose());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    _updateOptions(oldWidget);
    layerManager?.updateLayers(widget.layers);
    super.didUpdateWidget(oldWidget);
  }

  @override
  @override
  Future<void> _updateOptions(MapLibreMap oldWidget) async {
    final oldOptions = oldWidget.options;
    final options = this.options;

    // Always use Pigeon for updating options to ensure reliability
    await _hostApi.updateMapOptions(
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
  Future<List<QueriedLayer>> queryLayers(Offset screenLocation) async {
    final result = await _hostApi.queryLayers(screenLocation.dx.toDouble(), screenLocation.dy.toDouble());
    return result.map((layerData) => QueriedLayer(
      layerId: layerData['layerId'] as String,
      sourceId: layerData['sourceId'] as String,
      sourceLayer: layerData['sourceLayer'] as String?,
    )).toList();
  }

  @override
  Future<Position> toLngLat(Offset screenLocation) async {
    print('=== DART toLngLat DEBUG ===');
    print('Input: screen(${screenLocation.dx}, ${screenLocation.dy})');

    final result = await _hostApi.toLngLat(screenLocation.dx.toDouble(), screenLocation.dy.toDouble());
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
    print('=== DART toScreenLocation DEBUG ===');
    print('Input: Position(lat=${lngLat.lat}, lng=${lngLat.lng})');

    // Try without swapping - pass Position as-is
    final result = await _hostApi.toScreenLocation(lngLat.lng.toDouble(), lngLat.lat.toDouble());
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
    // Always use Pigeon for location tracking
    await _hostApi.trackLocation(trackLocation, trackBearing.index.toInt());
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
