import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    this.autoInitializeLocation = false,
    this.gpsFixedSvgIcon,
    this.gpsNotFixedSvgIcon,
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

  /// Whether to automatically initialize location when the map loads.
  /// When true, location services will be enabled and tracking started automatically.
  final bool autoInitializeLocation;

  /// Optional custom SVG icon path for GPS fixed state.
  /// If provided, this SVG will be used instead of Icons.gps_fixed.
  final String? gpsFixedSvgIcon;

  /// Optional custom SVG icon path for GPS not fixed state.
  /// If provided, this SVG will be used instead of Icons.gps_not_fixed.
  final String? gpsNotFixedSvgIcon;

  @override
  State<MapControlButtons> createState() => _MapControlButtonsState();
}

class _MapControlButtonsState extends State<MapControlButtons> {
  late final PermissionManager? _permissionManager;
  _TrackLocationState _trackState = _TrackLocationState.gpsNotFixed;
  late bool _trackLocationButtonInitialized = false;
  bool _autoLocationInitialized = false;

  // Track current zoom level manually since getCamera().zoom returns 0.0
  double _currentZoom = 10.0; // Default zoom level

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && widget.showTrackLocation) {
      _permissionManager = PermissionManager();
    }
  }

  /// Auto-initialize location services when the widget is built
  void _handleAutoLocationInitialization(MapController controller) {
    if (widget.autoInitializeLocation && !_autoLocationInitialized) {
      _autoLocationInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _initializeLocation(controller, trackLocation: true);
          
          // Set appropriate zoom level for location viewing
          await controller.animateCamera(
            zoom: 15,
            nativeDuration: const Duration(milliseconds: 1500),
          );
          
          print('MapControlButtons: Auto location initialization completed');
        } catch (e) {
          print('MapControlButtons: Error in auto location initialization: $e');
        }
      });
    }
  }

  /// Build the GPS icon widget based on current state and available custom icons
  Widget _buildGpsIcon() {
    final isFixed = _trackState == _TrackLocationState.gpsFixed;
    final svgIcon = isFixed ? widget.gpsFixedSvgIcon : widget.gpsNotFixedSvgIcon;
    
    if (svgIcon != null) {
      return SvgPicture.asset(
        svgIcon,
      );
    }
    
    // Fallback to default Material icons
    return Icon(
      isFixed ? Icons.gps_fixed : Icons.gps_not_fixed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = MapController.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    // Handle auto location initialization first
    _handleAutoLocationInitialization(controller);

    if (!kIsWeb && widget.showTrackLocation) {
      if (!_trackLocationButtonInitialized && !widget.autoInitializeLocation) {
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
                    print('MapControlButtons: Zoom in button pressed');
                    _currentZoom += 1.0;
                    print(
                      'MapControlButtons: Current zoom: ${_currentZoom - 1}, new zoom: $_currentZoom',
                    );
                    controller.animateCamera(
                      zoom: _currentZoom,
                      nativeDuration: const Duration(milliseconds: 200),
                    );
                  },
                  child: const Icon(Icons.add),
                ),
                FloatingActionButton(
                  heroTag: 'MapLibreZoomOutButton',
                  onPressed: () {
                    print('MapControlButtons: Zoom out button pressed');
                    _currentZoom = (_currentZoom - 1.0).clamp(
                      0.0,
                      22.0,
                    ); // Clamp to valid zoom range
                    print(
                      'MapControlButtons: Current zoom: ${_currentZoom + 1}, new zoom: $_currentZoom',
                    );
                    controller.animateCamera(
                      zoom: _currentZoom,
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
                    
                    if (widget.autoInitializeLocation) {
                      // If auto-initialization is enabled, just center on current location
                      try {
                        print('MapControlButtons: Centering on user location');
                        
                        // First ensure location is enabled (should already be from auto-init)
                        await controller.enableLocation();
                        
                        // Enable location tracking to center on user
                        await controller.trackLocation(trackLocation: true);
                        
                        // Give a small delay to let location get fixed, then animate
                        await Future.delayed(const Duration(milliseconds: 500));
                        
                        await controller.animateCamera(
                          zoom: 15,
                          nativeDuration: const Duration(milliseconds: 1000),
                        );
                        
                        // Update state to show GPS is fixed
                        if (mounted) {
                          setState(() => _trackState = _TrackLocationState.gpsFixed);
                        }
                        
                        // Call the callback if provided
                        if (widget.onCurrentLocation != null && controller.camera != null) {
                          widget.onCurrentLocation!(controller.camera!.center);
                        }
                      } catch (e) {
                        print('MapControlButtons: Error centering on location: $e');
                        if (mounted) {
                          setState(() => _trackState = _TrackLocationState.gpsNotFixed);
                        }
                      }
                    } else {
                      // Original initialization logic for manual mode
                      await _initializeLocation(controller);

                      try {
                        print('MapControlButtons: Starting location tracking');
                        await controller.trackLocation();

                        // Set a reasonable zoom level for user location
                        await controller.animateCamera(
                          zoom: 15,
                          nativeDuration: const Duration(milliseconds: 1000),
                        );
                      } catch (e) {
                        print(
                          'MapControlButtons: Error with location tracking: $e',
                        );
                      }
                    }
                  },
                  child: _trackState == _TrackLocationState.loading
                      ? const SizedBox.square(
                          dimension: kDefaultFontSize,
                          child: CircularProgressIndicator(),
                        )
                      : _buildGpsIcon(),
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
