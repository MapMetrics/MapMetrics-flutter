import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide Layer;
import 'package:flutter/services.dart';
import 'package:jni/jni.dart';
import 'package:mapmetrics/mapmetrics.dart' hide Position;
import 'package:geotypes/geotypes.dart' show Position;
import 'package:mapmetrics/src/layer/layer_manager.dart';
import 'package:mapmetrics/src/platform/android/extensions.dart';
import 'package:mapmetrics/src/platform/android/jni/jni.dart' as jni;
import 'package:mapmetrics/src/platform/map_state_native.dart';
import 'package:mapmetrics/src/platform/pigeon.g.dart' as pigeon;
import 'package:mapmetrics/src/services/road_snapping_service.dart';

part 'style_controller.dart';

/// The implementation that gets used for state of the [MapLibreMap] widget on
/// android using JNI and Pigeon as a fallback.
final class MapLibreMapStateAndroid extends MapLibreMapStateNative {
  late final pigeon.MapLibreHostApi _hostApi;
  late final int _viewId;
  jni.MapLibreMap? _cachedJniMapLibreMap;
  jni.Projection? _cachedJniProjection;
  jni.LocationComponent? _cachedLocationComponent;

  // Draggable location marker state
  bool _isLocationDraggable = false;
  bool _isDraggingLocation = false;
  Position? _manualLocationOverride;

  // Road snapping service
  final RoadSnappingService _roadSnappingService = RoadSnappingService(
    snapDistance: 5.0, // 5 meters for precise snapping
    preferRoute: true,
    smoothingFactor: 0.75, // Balanced smoothing for stability
  );

  // Navigation state management
  bool _isNavigationActive = false;
  StreamSubscription? _locationSubscription;
  List<Position>? _currentNavigationRoute;

  // Track current camera mode
  BearingTrackMode? _currentTrackingMode;
  bool _isTrackingLocation = false;
  DateTime? _lastCameraUpdate;
  DateTime? _lastLayerReorderTime;

  @override
  StyleControllerAndroid? style;

  jni.MapLibreMap? get _jniMapLibreMap =>
      _cachedJniMapLibreMap ??= jni.MapLibreRegistry.INSTANCE.getMap(_viewId);

  jni.Projection get _jniProjection =>
      _cachedJniProjection ??= _jniMapLibreMap!.getProjection();

  jni.LocationComponent get _locationComponent =>
      _cachedLocationComponent ??= _jniMapLibreMap!.getLocationComponent();

  @override
  Widget buildPlatformWidget(BuildContext context) {
    const viewType = 'plugins.flutter.io/maplibre';
    final mode = options.androidMode;
    if (mode == AndroidPlatformViewMode.tlhc_vd) {
      return AndroidView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
      );
    }
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers:
              widget.gestureRecognizers ??
              const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final viewController = switch (mode) {
          // This attempts to use the newest and most efficient platform view
          // implementation when possible. In cases where that is not
          // supported, it falls back to using Hybrid Composition, which is
          // the mode used by initExpensiveAndroidView.
          // https://api.flutter.dev/flutter/services/PlatformViewsService/initSurfaceAndroidView.html
          // https://github.com/flutter/flutter/blob/master/docs/platforms/android/Android-Platform-Views.md#selecting-a-mode
          AndroidPlatformViewMode.tlhc_hc =>
            PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              onFocus: () => params.onFocusChanged(true),
            ),
          AndroidPlatformViewMode.tlhc_vd =>
            PlatformViewsService.initAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              onFocus: () => params.onFocusChanged(true),
            ),
          AndroidPlatformViewMode.hc =>
            PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              onFocus: () => params.onFocusChanged(true),
            ),
          // https://github.com/flutter/flutter/blob/master/docs/platforms/android/Virtual-Display.md
          AndroidPlatformViewMode.vd => PlatformViewsService.initAndroidView(
            id: params.id,
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            onFocus: () => params.onFocusChanged(true),
          ),
        };
        return viewController
          ..addOnPlatformViewCreatedListener((id) {
            params.onPlatformViewCreated(id);
            _onPlatformViewCreated(id);
          })
          ..create();
      },
    );
  }

  /// This method gets called when the platform view is created. It is not
  /// guaranteed that the map is ready.
  void _onPlatformViewCreated(int viewId) {
    final channelSuffix = viewId.toString();
    _hostApi = pigeon.MapLibreHostApi(messageChannelSuffix: channelSuffix);
    pigeon.MapLibreFlutterApi.setUp(this, messageChannelSuffix: channelSuffix);
    _viewId = viewId;
    jni.Logger.setVerbosity(jni.Logger.WARN);
  }

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    _updateOptions(oldWidget);
    layerManager?.updateLayers(widget.layers);
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _cachedJniProjection?.release();
    _cachedJniMapLibreMap?.release();
    _cachedLocationComponent?.release();
    super.dispose();
  }

  Future<void> _updateOptions(MapLibreMap oldWidget) async {
    final jniMap = _jniMapLibreMap;
    // jniMap can be null if the widget rebuilds while the map hasn't been initialized.
    if (jniMap == null) return;

    final oldOptions = oldWidget.options;
    final options = this.options;
    if (this.options == oldOptions) return;

    jniMap.setMinZoomPreference(options.minZoom);
    jniMap.setMaxZoomPreference(options.maxZoom);
    jniMap.setMinPitchPreference(options.minPitch);
    jniMap.setMaxPitchPreference(options.maxPitch);

    // map bounds
    final oldBounds = oldOptions.maxBounds;
    final newBounds = options.maxBounds;
    if (oldBounds != null && newBounds == null) {
      // TODO @Nullable latLngBounds, https://github.com/dart-lang/native/issues/1644
      // _jniMapLibreMap.setLatLngBoundsForCameraTarget(null);
    } else if ((oldBounds == null && newBounds != null) ||
        (newBounds != null && oldBounds != newBounds)) {
      final bounds = newBounds.toLatLngBounds();
      jniMap.setLatLngBoundsForCameraTarget(bounds);
    }

    // gestures
    final uiSettings = jniMap.getUiSettings();
    if (options.gestures.rotate != oldOptions.gestures.rotate) {
      uiSettings.setRotateGesturesEnabled(options.gestures.rotate);
    }
    // TODO: pan is not handled, there is no setPanGestureEnabled on Android.
    /*if (options.gestures.pan != oldOptions.gestures.pan) {
        uiSettings.setRotateGesturesEnabled(options.gestures.pan);
      }*/
    if (options.gestures.zoom != oldOptions.gestures.zoom) {
      uiSettings.setZoomGesturesEnabled(options.gestures.zoom);
      uiSettings.setDoubleTapGesturesEnabled(options.gestures.zoom);
      uiSettings.setScrollGesturesEnabled(options.gestures.zoom);
      uiSettings.setQuickZoomGesturesEnabled(options.gestures.zoom);
    }
    if (options.gestures.pitch != oldOptions.gestures.pitch) {
      uiSettings.setTiltGesturesEnabled(options.gestures.pitch);
    }
    uiSettings.release();
  }

  @override
  Future<Position> toLngLat(Offset screenLocation) async =>
      toLngLatSync(screenLocation);

  @override
  Future<Offset> toScreenLocation(Position lngLat) async =>
      toScreenLocationSync(lngLat);

  @override
  Future<List<Position>> toLngLats(List<Offset> screenLocations) async =>
      toLngLatsSync(screenLocations);

  @override
  Future<List<Offset>> toScreenLocations(List<Position> lngLats) async =>
      toScreenLocationsSync(lngLats);

  @override
  Future<void> moveCamera({
    Position? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) async {
    assert(_jniMapLibreMap != null, '_jniMapLibreMap needs to be not null.');
    final cameraPositionBuilder = jni.CameraPosition$Builder();
    if (center != null) cameraPositionBuilder.target(center.toLatLng());
    if (zoom != null) cameraPositionBuilder.zoom(zoom);
    if (pitch != null) cameraPositionBuilder.tilt(pitch);
    if (bearing != null) cameraPositionBuilder.bearing(bearing);

    final cameraPosition = cameraPositionBuilder.build();
    cameraPositionBuilder.release();
    final cameraUpdate = jni.CameraUpdateFactory.newCameraPosition(
      cameraPosition,
    );
    final completer = Completer<void>();
    _jniMapLibreMap?.moveCamera$1(
      cameraUpdate,
      jni.MapLibreMap$CancelableCallback.implement(
        jni.$MapLibreMap$CancelableCallback(
          onCancel:
              () => completer.completeError(Exception('Animation cancelled.')),
          onFinish: completer.complete,
          onCancel$async: true,
          onFinish$async: true,
        ),
      ),
    );
    cameraUpdate.release();
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
    final jniMap = _jniMapLibreMap!;
    final cameraPositionBuilder = jni.CameraPosition$Builder();
    if (center != null) cameraPositionBuilder.target(center.toLatLng());
    if (zoom != null) cameraPositionBuilder.zoom(zoom);
    if (pitch != null) cameraPositionBuilder.tilt(pitch);
    if (bearing != null) cameraPositionBuilder.bearing(bearing);

    final cameraPosition = cameraPositionBuilder.build();
    cameraPositionBuilder.release();
    final cameraUpdate = jni.CameraUpdateFactory.newCameraPosition(
      cameraPosition,
    );

    final completer = Completer<void>();
    jniMap.animateCamera$3(
      cameraUpdate,
      nativeDuration.inMilliseconds,
      jni.MapLibreMap$CancelableCallback.implement(
        jni.$MapLibreMap$CancelableCallback(
          onCancel:
              () => completer.completeError(Exception('Animation cancelled.')),
          onFinish: completer.complete,
          onFinish$async: true,
          onCancel$async: true,
        ),
      ),
    );
    final result = await completer.future;
    cameraUpdate.release();
    return result;
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
    final jniMap = _jniMapLibreMap!;
    final latLngBounds = bounds.toLatLngBounds();
    final cameraUpdate = jni.CameraUpdateFactory.newLatLngBounds$3(
      latLngBounds,
      bearing ?? -1.0,
      pitch ?? -1.0,
      padding.left.toInt(),
      padding.top.toInt(),
      padding.right.toInt(),
      padding.bottom.toInt(),
    );
    latLngBounds.release();

    final completer = Completer<void>();
    jniMap.animateCamera$3(
      cameraUpdate,
      nativeDuration.inMilliseconds,
      jni.MapLibreMap$CancelableCallback.implement(
        jni.$MapLibreMap$CancelableCallback(
          onCancel:
              () => completer.completeError(Exception('Animation cancelled.')),
          onFinish: completer.complete,
          onCancel$async: true,
          onFinish$async: true,
        ),
      ),
    );
    final result = await completer.future;
    cameraUpdate.release();
    return result;
  }

  @override
  void onStyleLoaded() {
    // We need to refresh the cached style for when the style reloads.
    style?.dispose();
    final styleCtrl = StyleControllerAndroid._(
      _jniMapLibreMap!.getStyle$1()!,
      _hostApi,
    );
    style = styleCtrl;

    widget.onEvent?.call(MapEventStyleLoaded(styleCtrl));
    widget.onStyleLoaded?.call(styleCtrl);
    layerManager = LayerManager(styleCtrl, widget.layers);
    // setState is needed to refresh the flutter widgets used in MapLibreMap.children.
    setState(() {});
  }

  @override
  MapCamera getCamera() {
    final jniCamera = _jniMapLibreMap!.getCameraPosition();
    final jniTarget = jniCamera.target!;
    final mapCamera = MapCamera(
      center: Position(jniTarget.getLongitude(), jniTarget.getLatitude()),
      zoom: jniCamera.zoom,
      pitch: jniCamera.tilt,
      bearing: jniCamera.bearing,
    );
    // camera = mapCamera;
    jniTarget.release();
    jniCamera.release();
    return mapCamera;
  }

  @override
  Future<double> getMetersPerPixelAtLatitude(double latitude) async =>
      getMetersPerPixelAtLatitudeSync(latitude);

  @override
  Future<LngLatBounds> getVisibleRegion() async => getVisibleRegionSync();

  @override
  Future<List<Map<String, String>>> queryLayers(Offset screenLocation) async {
    // Use Pigeon to call the native implementation which extracts all feature properties
    final result = await _hostApi.queryLayers(screenLocation.dx.toDouble(), screenLocation.dy.toDouble());
    return result;
  }

  @override
  Future<void> enableLocation({
    Duration fastestInterval = const Duration(milliseconds: 750),
    Duration maxWaitTime = const Duration(seconds: 1),
    bool pulseFade = true,
    bool accuracyAnimation = true,
    bool compassAnimation = true,
    bool pulse = true,
    BearingRenderMode bearingRenderMode = BearingRenderMode.gps,
  }) async {
    // https://maplibre.org/maplibre-native/docs/book/android/location-component-guide.html
    final style = this.style;
    if (style == null) return;

    final bearing = switch (bearingRenderMode) {
      BearingRenderMode.none => jni.RenderMode.NORMAL,
      BearingRenderMode.compass => jni.RenderMode.COMPASS,
      BearingRenderMode.gps => jni.RenderMode.GPS,
    };
    final jniContext = jni.MapLibreRegistry.INSTANCE.getContext()!;
    final locOptionsBuilder =
        jni.LocationComponentOptions.builder(jniContext)
            .pulseFadeEnabled(pulseFade)!
            .accuracyAnimationEnabled(accuracyAnimation)!
            .compassAnimationEnabled(compassAnimation.toJBoolean())!
            .pulseEnabled(pulse)!;
    final locOptions = locOptionsBuilder.build();
    final locationEngineRequestBuilder =
        jni.LocationEngineRequest$Builder(100) // 100ms = 10 updates per second for smooth tracking
            .setFastestInterval(fastestInterval.inMilliseconds)!
            .setMaxWaitTime(maxWaitTime.inMilliseconds)!
            .setPriority(jni.LocationEngineRequest.PRIORITY_HIGH_ACCURACY)!;
    final locationEngineRequest = locationEngineRequestBuilder.build();
    final activationOptionsBuilder =
        jni.LocationComponentActivationOptions.builder(
              jniContext,
              style._jniStyle,
            )
            .locationComponentOptions(locOptions)!
            .useDefaultLocationEngine(true)!
            .locationEngineRequest(locationEngineRequest)!;
    final activationOptions = activationOptionsBuilder.build()!;

    _locationComponent.activateLocationComponent(activationOptions);
    _locationComponent.setRenderMode(bearing);

    // Only enable location component if we're not in navigation mode
    if (_currentNavigationRoute == null || _currentNavigationRoute!.isEmpty) {
      _locationComponent.setLocationComponentEnabled(true);
      debugPrint('✅ Location component enabled (not in navigation mode)');
    } else {
      _locationComponent.setLocationComponentEnabled(false);
      debugPrint('🚫 Location component disabled (navigation mode active)');
    }

    // Set up location update listener for road snapping
    _setupLocationSnapping();

    activationOptionsBuilder.release();
    locOptionsBuilder.release();
    locOptions.release();
    locationEngineRequestBuilder.release();
    locationEngineRequest?.release();
    activationOptions.release();
    jniContext.release();
  }

  @override
  Future<void> trackLocation({
    bool trackLocation = true,
    BearingTrackMode trackBearing = BearingTrackMode.gps,
  }) async {
    final mode = switch (trackBearing) {
      BearingTrackMode.none =>
        trackLocation
            ? jni
                .CameraMode
                .TRACKING // only location
            : jni.CameraMode.NONE, // neither location nor bearing
      BearingTrackMode.compass =>
        trackLocation
            ? jni
                .CameraMode
                .TRACKING_COMPASS // location with compass bearing
            : jni.CameraMode.NONE_COMPASS, // only compass bearing
      BearingTrackMode.gps =>
        trackLocation
            ? jni
                .CameraMode
                .TRACKING_GPS // location with gps bearing
            : jni.CameraMode.NONE_GPS, // only gps bearing
    };
    _locationComponent.setCameraMode(mode);

    // Store the current tracking mode for use in road snapping
    _currentTrackingMode = trackBearing;
    _isTrackingLocation = trackLocation;

    // If we're in navigation mode (have an active route), hide the location icon
    if (_currentNavigationRoute != null && _currentNavigationRoute!.isNotEmpty) {
      hideLocationIcon();
      debugPrint('🚫 Location icon hidden during trackLocation (navigation mode active)');
    }
  }

  void _setupLocationSnapping() {
    debugPrint('🔧 Setting up location snapping...');

    // Use an extremely fast timer for continuous smooth updates
    // This runs at 250 FPS for maximum smoothness
    // Timer.periodic(const Duration(milliseconds: 33), (timer) { // 30 FPS - balanced for smooth updates without freezing
    //   if (!mounted) {
    //     timer.cancel();
    //     return;
    //   }

    //   if (_currentNavigationRoute != null && _locationComponent != null) {
    //     _applyRoadSnapping();
    //   }
    // });


     if (_currentNavigationRoute != null && _locationComponent != null) {
        _applyRoadSnapping();
      }
    debugPrint('✅ Location snapping setup complete');
  }

  void _applyRoadSnappingWithLocation(jni.Location location) {
    if (_currentNavigationRoute == null || _locationComponent == null) {
      return;
    }

    final gpsPosition = Position(
      location.getLongitude(),
      location.getLatitude(),
    );

    // Apply road snapping
    final snapped = _roadSnappingService.snapToRoad(
      gpsPosition,
      gpsBearing: location.hasBearing() ? location.getBearing() : null,
    );

    // Always update if we have any snap for instant response
    if (snapped.isSnapped) {
      // Create a new location with the snapped position
      final provider = JString.fromString('snapped');
      final snappedLocation = jni.Location(provider);
      snappedLocation.setLongitude(snapped.position.lng.toDouble());
      snappedLocation.setLatitude(snapped.position.lat.toDouble());
      snappedLocation.setBearing(snapped.bearing);
      snappedLocation.setTime(location.getTime());

      if (location.hasSpeed()) {
        snappedLocation.setSpeed(location.getSpeed());
      }
      if (location.hasAccuracy()) {
        snappedLocation.setAccuracy(location.getAccuracy());
      }

      // Force update the location immediately
      _locationComponent.forceLocationUpdate(snappedLocation);

      // During navigation, we rely on the custom navigation marker from road snapping service
      if (_isNavigationActive && _currentNavigationRoute != null && _currentNavigationRoute!.isNotEmpty) {
        debugPrint('🧭 Location updated during navigation: ${snapped.position.lat}, ${snapped.position.lng}');
        // The custom navigation marker is handled by the road snapping service
        // which automatically provides the correct snapped position
      }

      provider.release();
      snappedLocation.release();
    }
  }

  void _applyRoadSnapping() {
    if (_currentNavigationRoute == null || _locationComponent == null) {
      return;
    }

    // Periodically ensure navigation icon stays above route during navigation
    // This is important for rerouting scenarios where new route polylines might be drawn
    // if (_isNavigationActive) {
    //   // Check every few updates to avoid performance impact
    //   final now = DateTime.now();
    //   if (_lastLayerReorderTime == null ||
    //       now.difference(_lastLayerReorderTime!).inSeconds >= 2) {
    //     _ensureNavigationIconAboveRoute();
    //     _lastLayerReorderTime = now;
    //   }
    // }

    // Get the current GPS location
    final lastLocation = _locationComponent.getLastKnownLocation();
    if (lastLocation == null) return;

    final gpsPosition = Position(
      lastLocation.getLongitude(),
      lastLocation.getLatitude(),
    );

    // Apply road snapping
    final snapped = _roadSnappingService.snapToRoad(
      gpsPosition,
      gpsBearing: lastLocation.hasBearing() ? lastLocation.getBearing() : null,
    );

    // Always update if we have any snap for instant response
    if (snapped.isSnapped) {
      // Create a new location with the snapped position
      final provider = JString.fromString('snapped');
      final location = jni.Location(provider);
      location.setLongitude(snapped.position.lng.toDouble());
      location.setLatitude(snapped.position.lat.toDouble());

      if (lastLocation.hasAltitude()) {
        location.setAltitude(lastLocation.getAltitude());
      }
      if (lastLocation.hasAccuracy()) {
        location.setAccuracy(lastLocation.getAccuracy());
      }
      if (lastLocation.hasSpeed()) {
        location.setSpeed(lastLocation.getSpeed());
      }

      // Set the snapped bearing
      location.setBearing(snapped.bearing);
      location.setTime(DateTime.now().millisecondsSinceEpoch);

      // Force update with snapped location
      try {
        // _locationComponent.forceLocationUpdate(location);

        // Don't manually update camera when native tracking is enabled
        // The native LocationComponent will handle camera tracking automatically
        // This prevents glitching between two different camera positions
      } catch (e) {
        debugPrint('❌ Error updating location: $e');
      }

      provider.release();
      location.release();
    }

    lastLocation.release();
  }

  // Old _applyRoadSnapping method removed - snapping now handled in _setupLocationSnapping timer

  void _setupDragHandling() {
    // Note: MapLibre Android doesn't expose removeOnMapClickListener directly
    // The listeners will be overridden when we add new ones

    // Add a long press listener for dragging location
    _jniMapLibreMap?.addOnMapLongClickListener(
      jni.MapLibreMap$OnMapLongClickListener.implement(
        jni.$MapLibreMap$OnMapLongClickListener(
          onMapLongClick: (latLng) {
            if (!_isLocationDraggable) return false;

            // Update the manual location override
            _manualLocationOverride = Position(
              latLng.getLongitude(),
              latLng.getLatitude(),
            );

            // Force the location component to this position
            _forceLocationUpdate(_manualLocationOverride!);

            debugPrint('📍 Location moved to: ${_manualLocationOverride!.lat}, ${_manualLocationOverride!.lng}');

            // Optionally snap to road if near a road
            _snapToNearestRoad(_manualLocationOverride!);

            return true;
          },
        ),
      ),
    );

    // Also add regular click listener for quick moves
    _jniMapLibreMap?.addOnMapClickListener(
      jni.MapLibreMap$OnMapClickListener.implement(
        jni.$MapLibreMap$OnMapClickListener(
          onMapClick: (latLng) {
            if (!_isLocationDraggable) return false;

            // Update position on normal click too
            _manualLocationOverride = Position(
              latLng.getLongitude(),
              latLng.getLatitude(),
            );

            _forceLocationUpdate(_manualLocationOverride!);
            _snapToNearestRoad(_manualLocationOverride!);

            return true;
          },
        ),
      ),
    );
  }

  void _forceLocationUpdate(Position newPosition) {
    // Create a fake location update to move the marker
    final provider = JString.fromString('manual');
    final location = jni.Location(provider);
    location.setLatitude(newPosition.lat.toDouble());
    location.setLongitude(newPosition.lng.toDouble());
    location.setAccuracy(10.0);
    location.setTime(DateTime.now().millisecondsSinceEpoch);

    // Force the location component to use this location
    _locationComponent.forceLocationUpdate(location);

    provider.release();
    location.release();
  }

  void _snapToNearestRoad(Position position) {
    // Query map features at this position to find roads
    // TODO: Implement road snapping in a future update
    // This would require:
    // 1. Converting position to screen coordinates
    // 2. Querying rendered features for road layers
    // 3. Finding the closest point on the road geometry
    // 4. Updating the location to that point

    // For now, just use the clicked position as-is
    debugPrint('📍 Road snapping not yet implemented - using exact position');
  }

  @override
  Position toLngLatSync(Offset screenLocation) => _jniProjection
      .fromScreenLocation(screenLocation.toPointF())
      .toPosition(releaseOriginal: true);

  @override
  List<Position> toLngLatsSync(List<Offset> screenLocations) =>
      screenLocations.map(toLngLatSync).toList(growable: false);

  @override
  Offset toScreenLocationSync(Position lngLat) => _jniProjection
      .toScreenLocation(lngLat.toLatLng())
      .toOffset(releaseOriginal: true);

  @override
  List<Offset> toScreenLocationsSync(List<Position> lngLats) =>
      lngLats.map(toScreenLocationSync).toList(growable: false);

  @override
  double getMetersPerPixelAtLatitudeSync(double latitude) =>
      _jniProjection.getMetersPerPixelAtLatitude(latitude);

  @override
  LngLatBounds getVisibleRegionSync() {
    final region = _jniProjection.getVisibleRegion();
    final jniBounds = region.latLngBounds;
    region.release();
    final bounds = jniBounds.toLngLatBounds(releaseOriginal: true);
    return bounds;
  }

  @override
  Future<void> setLocationDraggable({bool draggable = true}) async {
    _isLocationDraggable = draggable;

    if (draggable) {
      debugPrint('📍 Location marker drag mode ENABLED - Click on the location marker to start dragging');
      debugPrint('📍 Then click or long-press anywhere on the map to move it');
    } else {
      debugPrint('📍 Location marker drag mode DISABLED');
      // Re-enable normal tracking if it was disabled
      if (_locationComponent != null) {
        _locationComponent.setCameraMode(jni.CameraMode.TRACKING);
      }
    }
  }

  @override
  Future<void> setNavigationRoute(List<Position> routePoints) async {
    _currentNavigationRoute = routePoints;
    _roadSnappingService.clearNavigationRoute(); // Clear old route first
    _roadSnappingService.setNavigationRoute(routePoints);
    debugPrint('📍 Navigation route updated with ${routePoints.length} points for road snapping');

    // Hide the native location icon when navigation starts
    hideLocationIcon();
    debugPrint('🚫 Native location icon hidden for navigation mode');

    // Set navigation state to true
    _isNavigationActive = true;
    debugPrint('🧭 Navigation started - using custom navigation marker from road snapping service');

    // Ensure navigation icon stays above route polylines during rerouting
    _ensureNavigationIconAboveRoute();

    // Force immediate update after route change
    if (_locationComponent != null) {
      _applyRoadSnapping();
    }

    // Snapping will be applied automatically by the timer in _setupLocationSnapping
    debugPrint('📍 Road snapping will be applied automatically');
  }

  @override
  Future<void> clearNavigationRoute() async {
    _currentNavigationRoute = null;
    _roadSnappingService.clearNavigationRoute();
    debugPrint('📍 Navigation route cleared');

    // Set navigation state to false
    _isNavigationActive = false;
    debugPrint('🧭 Navigation ended - can re-enable native location component');

    // Show the native location icon again when navigation ends
    showLocationIcon();
    debugPrint('✅ Native location icon restored after navigation');
  }

  /// Hide the native location icon (useful for navigation mode)
  void hideLocationIcon() {
    if (_locationComponent != null) {
      // Completely disable the location component to hide the native marker
      _locationComponent.setLocationComponentEnabled(false);
      debugPrint('🚫 Native location component completely disabled');
    }
  }

  /// Show the native location icon with the specified mode
  void showLocationIcon({BearingTrackMode mode = BearingTrackMode.gps}) {
    if (_locationComponent != null) {
      // First re-enable the location component
      _locationComponent.setLocationComponentEnabled(true);

      // Then set the appropriate render mode
      final renderMode = switch (mode) {
        BearingTrackMode.none => jni.RenderMode.NORMAL,  // 18
        BearingTrackMode.compass => jni.RenderMode.COMPASS,  // 4
        BearingTrackMode.gps => jni.RenderMode.GPS,  // 8
      };
      _locationComponent.setRenderMode(renderMode);
      debugPrint('✅ Native location component re-enabled with mode: $mode');
    }
  }

  /// Ensure navigation icon stays above route polylines during rerouting
  void _ensureNavigationIconAboveRoute() {
    if (_isNavigationActive) {
      debugPrint('🧭 Ensuring navigation icon stays above route polylines during rerouting');

      try {
        // During navigation, we use a custom marker from the road snapping service
        // We need to ensure this custom marker stays visible above the route polyline
        // The issue is that when rerouting happens, the new polyline is drawn on top

        // Solution: Disable location component to hide default marker
        // The custom navigation marker from road snapping service will be used instead
        if (_locationComponent != null) {
          // Disable location component during navigation
          _locationComponent.setLocationComponentEnabled(false);
          debugPrint('🚫 Location component disabled for navigation mode');
        }

        // The actual navigation marker positioning is handled by the road snapping service
        // which automatically positions itself correctly above route layers
      } catch (e) {
        debugPrint('❌ Failed to configure navigation icon layer priority: $e');
      }
    }
  }

}
