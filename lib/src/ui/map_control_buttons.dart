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
                  onPressed:
                      () => controller.animateCamera(
                        zoom: controller.getCamera().zoom + 1,
                        nativeDuration: const Duration(milliseconds: 200),
                      ),
                  child: const Icon(Icons.add),
                ),
                FloatingActionButton(
                  heroTag: 'MapLibreZoomOutButton',
                  onPressed:
                      () => controller.animateCamera(
                        zoom: controller.getCamera().zoom - 1,
                        nativeDuration: const Duration(milliseconds: 200),
                      ),
                  child: const Icon(Icons.remove),
                ),
              ],

              if (!kIsWeb && widget.showTrackLocation) ...[
                FloatingActionButton(
                  heroTag: 'MapLibreTrackLocationButton',
                  onPressed: () async => _initializeLocation(controller),
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
    if (!_permissionManager!.locationPermissionsGranted) {
      setState(() => _trackState = _TrackLocationState.gpsNotFixed);
    }

    try {
      await controller.enableLocation();

      setState(() => _trackState = _TrackLocationState.gpsFixed);
      await Future.delayed(const Duration(milliseconds: 500));
      if (trackLocation) await controller.trackLocation();
    } on Exception {
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
