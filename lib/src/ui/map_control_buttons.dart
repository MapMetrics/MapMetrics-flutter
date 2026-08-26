import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Display a zoom-in and zoom-out button to the [MapLibreMap] by using it in
/// [MapLibreMap.children].
///
/// This widget is purposefully kept simple. If you need to change the design
/// or behavior of the zoom buttons a lot, prefer to copy this class into your
/// app and adjust it according to your needs.
///
/// {@category UI}
@immutable
class MapControlButtons extends StatefulWidget {
  /// Display a zoom-in and zoom-out button to the [MapLibreMap] by using it in
  /// [MapLibreMap.children].
  const MapControlButtons({
    super.key,
    this.padding = const EdgeInsets.symmetric(vertical: 50, horizontal: 12),
    this.alignment = Alignment.bottomRight,
    this.showTrackLocation = false,
    this.showZoomInOutButton = false,
    this.onCurrentLocation, // Made this optional
    this.requestPermissionsExplanation =
        'We need your location to show it on the map.',
  });

  /// The padding.
  final EdgeInsets padding;

  /// The alignment of the buttons.
  final Alignment alignment;

  /// Whether to show the track location button.
  ///
  /// This button is currently not available on web.
  final bool showTrackLocation;
  final void Function(Position)? onCurrentLocation;

  /// The explanation to show when requesting location permissions.
  final String requestPermissionsExplanation;

  final bool showZoomInOutButton;

  @override
  State<MapControlButtons> createState() => _MapControlButtonsState();
}

class _MapControlButtonsState extends State<MapControlButtons> {
  late final PermissionManager? _permissionManager;
  _TrackLocationState _trackState = _TrackLocationState.gpsNotFixed;
  late bool _trackLocationButtonInitialized = false;

  /// The zoom the buttons should step from.
  ///
  /// This used to be a private field seeded at 10.0 and incremented on every
  /// press, on the premise -- recorded in a comment here -- that
  /// getCamera().zoom returns 0.0. It does not: getCamera() returns the base
  /// class camera, which is kept current by the onMoveCamera callback and so
  /// already reflects pinch gestures. The manual counter meant a pinch moved
  /// the map without moving the counter, and the next button press animated
  /// back to whatever the counter believed -- so the buttons and the gesture
  /// fought each other.
  ///
  /// getCamera() does report 0.0 in one case: before the first camera event,
  /// when it falls back to a zero camera. Zooming from that would jump to the
  /// world view, so fall back to the configured initial zoom instead.
  double _stepFromZoom(MapController controller) {
    final zoom = controller.getCamera().zoom;
    if (zoom == 0 && controller.options.initZoom != 0) {
      return controller.options.initZoom;
    }
    return zoom;
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && widget.showTrackLocation) {
      _permissionManager = PermissionManager();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = MapController.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    if (!kIsWeb && widget.showTrackLocation) {
      if (!_trackLocationButtonInitialized) {
        _trackLocationButtonInitialized = true;
        if (Platform.isIOS) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            // await Future.delayed(const Duration(milliseconds: 500));
            await _initializeLocation(controller);
          });
        } else if (_permissionManager?.locationPermissionsGranted ?? false) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            // await Future.delayed(const Duration(milliseconds: 500));
            await _initializeLocation(controller);
          });
        }
      }
    }

    // Use a SafeArea to ensure the widget is completely visible on devices
    // with rounded edges like iOS.
    return SafeArea(
      child: Container(
        alignment: widget.alignment,
        padding: widget.padding,
        child: PointerInterceptor(
          child: Column(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showZoomInOutButton) ...[
                FloatingActionButton(
                  heroTag: 'MapLibreZoomInButton',
                  onPressed: () {
                    // Clamped to the map's own limits, not a hardcoded range:
                    // zoom-in previously had no upper clamp at all, so it could
                    // animate past maxZoom and stall against the native cap.
                    final zoom = (_stepFromZoom(controller) + 1.0).clamp(
                      controller.options.minZoom,
                      controller.options.maxZoom,
                    );
                    controller.animateCamera(
                      zoom: zoom,
                      nativeDuration: const Duration(milliseconds: 200),
                    );
                  },
                  child: const Icon(Icons.add),
                ),
                FloatingActionButton(
                  heroTag: 'MapLibreZoomOutButton',
                  onPressed: () {
                    // Was clamped to a hardcoded 0..22, which ignored a map
                    // configured with a narrower range.
                    final zoom = (_stepFromZoom(controller) - 1.0).clamp(
                      controller.options.minZoom,
                      controller.options.maxZoom,
                    );
                    controller.animateCamera(
                      zoom: zoom,
                      nativeDuration: const Duration(milliseconds: 200),
                    );
                  },
                  child: const Icon(Icons.remove),
                ),
              ],

              if (!kIsWeb && widget.showTrackLocation) ...[
                FloatingActionButton(
                  heroTag: 'MapLibreTrackLocationButton',
                  onPressed: () async {
                    print('MapControlButtons: Location button pressed');
                    await _initializeLocation(controller);

                    // After enabling location, animate to user's location
                    // For now, we'll use a simple approach - just enable tracking
                    // which will automatically center on the user's location
                    try {
                      print('MapControlButtons: Starting location tracking');
                      await controller.trackLocation(trackLocation: true);

                      // Set a reasonable zoom level for user location
                      await controller.animateCamera(
                        zoom: 15.0,
                        nativeDuration: const Duration(milliseconds: 1000),
                      );
                    } catch (e) {
                      print(
                        'MapControlButtons: Error with location tracking: $e',
                      );
                    }
                  },
                  child:
                      _trackState == _TrackLocationState.loading
                          ? const SizedBox.square(
                            dimension: kDefaultFontSize,
                            child: CircularProgressIndicator(),
                          )
                          : Icon(
                            _trackState == _TrackLocationState.gpsFixed
                                ? Icons.gps_fixed
                                : Icons.gps_not_fixed,
                          ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initializeLocation(
    MapController controller, {
    bool trackLocation = true,
  }) async {
    // Permission manager not available on iOS
    if (Platform.isIOS) {
      await _enableLocationServices(controller, trackLocation: trackLocation);
      return;
    }
    try {
      if (!_permissionManager!.locationPermissionsGranted) {
        setState(() => _trackState = _TrackLocationState.loading);

        await _permissionManager.requestLocationPermissions(
          explanation: widget.requestPermissionsExplanation,
        );
      }
    } finally {
      await _enableLocationServices(controller, trackLocation: trackLocation);
    }
  }

  Future<void> _enableLocationServices(
    MapController controller, {
    bool trackLocation = true,
  }) async {
    // Handle iOS case where permission manager is null
    if (Platform.isIOS) {
      try {
        print('MapControlButtons: Enabling location services on iOS');
        await controller.enableLocation();
        setState(() => _trackState = _TrackLocationState.gpsFixed);

        await Future.delayed(const Duration(milliseconds: 500));
        if (widget.onCurrentLocation != null && controller.camera != null) {
          widget.onCurrentLocation!(controller.camera!.center);
        }

        if (trackLocation) {
          print('MapControlButtons: Starting location tracking on iOS');
          await controller.trackLocation();
        }
      } on Exception catch (e) {
        print('MapControlButtons: Error enabling location on iOS: $e');
        setState(() => _trackState = _TrackLocationState.gpsNotFixed);
      }
      return;
    }

    // Android case
    if (!_permissionManager!.locationPermissionsGranted) {
      setState(() => _trackState = _TrackLocationState.gpsNotFixed);
    }

    try {
      await controller.enableLocation();

      setState(() => _trackState = _TrackLocationState.gpsFixed);
      await Future.delayed(const Duration(milliseconds: 500));
      if (widget.onCurrentLocation != null && controller.camera != null) {
        widget.onCurrentLocation!(controller.camera!.center);
      }

      if (trackLocation) await controller.trackLocation();
    } on Exception catch (e) {
      print('MapControlButtons: Error enabling location on Android: $e');
      setState(() => _trackState = _TrackLocationState.gpsNotFixed);
    }
  }
}

/// Location tracking state.
enum _TrackLocationState {
  /// Whether the permission is currently being fetched.
  loading,

  /// The permission is granted.
  gpsFixed,

  /// The permission is denied.
  gpsNotFixed,
}
