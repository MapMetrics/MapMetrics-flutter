# Flutter Side Fixes for User Location Layer Crash

This document contains the exact changes needed in your Flutter/Dart code to prevent the `MLNRedundantLayerIdentifierException` crash.

## Problem

The crash occurs when `enableLocation()`, `showUserLocationPuck()`, or `trackLocation()` are called multiple times, causing iOS to try to add the `user-location-layer` repeatedly.

## Solution

Implement proper state management in your Flutter code to prevent duplicate calls to iOS.

---

## 1. MapLibre Controller Wrapper (RECOMMENDED)

Create a safe wrapper around your MapLibre controller to track location state:

### Create: `lib/utils/safe_maplibre_controller.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Safe wrapper around MapLibreMapController that prevents duplicate location calls
class SafeMapLibreController {
  final MapLibreMapController _controller;
  
  bool _isLocationEnabled = false;
  bool _isLocationPuckVisible = false;
  bool _isTracking = false;
  int _currentTrackingMode = 0;
  
  SafeMapLibreController(this._controller);
  
  /// Get the underlying controller for other operations
  MapLibreMapController get controller => _controller;
  
  /// Enable location services (idempotent - safe to call multiple times)
  Future<void> enableLocation({
    int fastestInterval = 1000,
    int maxWaitTime = 5000,
    bool pulseFade = true,
    bool accuracyAnimation = true,
    bool compassAnimation = true,
    bool pulse = true,
  }) async {
    if (_isLocationEnabled) {
      debugPrint('📍 Location already enabled, skipping');
      return;
    }
    
    try {
      await _controller.enableLocation(
        fastestInterval: fastestInterval,
        maxWaitTime: maxWaitTime,
        pulseFade: pulseFade,
        accuracyAnimation: accuracyAnimation,
        compassAnimation: compassAnimation,
        pulse: pulse,
      );
      _isLocationEnabled = true;
      _isLocationPuckVisible = true; // enableLocation also shows the puck
      debugPrint('✅ Location enabled successfully');
    } catch (e) {
      debugPrint('❌ Failed to enable location: $e');
      rethrow;
    }
  }
  
  /// Show/hide the user location puck (idempotent)
  Future<void> showUserLocationPuck(bool show) async {
    if (_isLocationPuckVisible == show) {
      debugPrint('📍 Location puck already ${show ? "visible" : "hidden"}, skipping');
      return;
    }
    
    try {
      await _controller.showUserLocationPuck(show);
      _isLocationPuckVisible = show;
      debugPrint('✅ Location puck ${show ? "shown" : "hidden"}');
    } catch (e) {
      debugPrint('❌ Failed to ${show ? "show" : "hide"} location puck: $e');
      rethrow;
    }
  }
  
  /// Enable/disable location tracking (idempotent)
  /// bearingMode: 0 = follow, 1 = compass, 2 = gps
  Future<void> trackLocation(bool track, {int bearingMode = 0}) async {
    if (_isTracking == track && _currentTrackingMode == bearingMode) {
      debugPrint('📍 Tracking already ${track ? "enabled" : "disabled"} with mode $bearingMode, skipping');
      return;
    }
    
    // Ensure location is enabled before tracking
    if (track && !_isLocationEnabled) {
      debugPrint('📍 Location not enabled, enabling first...');
      await enableLocation();
    }
    
    try {
      await _controller.trackLocation(track, bearingMode: bearingMode);
      _isTracking = track;
      _currentTrackingMode = bearingMode;
      debugPrint('✅ Tracking ${track ? "enabled" : "disabled"} with mode $bearingMode');
    } catch (e) {
      debugPrint('❌ Failed to ${track ? "enable" : "disable"} tracking: $e');
      rethrow;
    }
  }
  
  /// Reset all location state (useful when disposing)
  void resetLocationState() {
    _isLocationEnabled = false;
    _isLocationPuckVisible = false;
    _isTracking = false;
    _currentTrackingMode = 0;
  }
  
  // Getters for state
  bool get isLocationEnabled => _isLocationEnabled;
  bool get isLocationPuckVisible => _isLocationPuckVisible;
  bool get isTracking => _isTracking;
  int get currentTrackingMode => _currentTrackingMode;
}
```

---

## 2. Safe Map Widget Implementation

### Update your map widget to use the safe controller:

```dart
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'safe_maplibre_controller.dart'; // Import the wrapper

class SafeMapWidget extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final bool enableLocationOnLoad;
  final bool enableTrackingOnLoad;
  
  const SafeMapWidget({
    Key? key,
    this.initialCenter = const LatLng(0, 0),
    this.initialZoom = 10,
    this.enableLocationOnLoad = false,
    this.enableTrackingOnLoad = false,
  }) : super(key: key);

  @override
  State<SafeMapWidget> createState() => _SafeMapWidgetState();
}

class _SafeMapWidgetState extends State<SafeMapWidget> {
  SafeMapLibreController? _safeController;
  bool _isMapReady = false;
  bool _isStyleLoaded = false;
  
  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialCenter,
        zoom: widget.initialZoom,
      ),
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      trackCameraPosition: true,
      myLocationEnabled: false, // We'll control this manually
      myLocationTrackingMode: MyLocationTrackingMode.None,
    );
  }
  
  void _onMapCreated(MapLibreMapController controller) {
    debugPrint('📍 Map created');
    _safeController = SafeMapLibreController(controller);
    _isMapReady = true;
    
    // Don't enable location here - wait for style to load
  }
  
  Future<void> _onStyleLoaded() async {
    debugPrint('📍 Style loaded');
    _isStyleLoaded = true;
    
    // NOW it's safe to enable location
    if (widget.enableLocationOnLoad && _safeController != null) {
      await _enableLocationSafely();
    }
  }
  
  Future<void> _enableLocationSafely() async {
    if (_safeController == null) {
      debugPrint('⚠️ Controller not ready');
      return;
    }
    
    if (!_isStyleLoaded) {
      debugPrint('⚠️ Style not loaded yet, waiting...');
      return;
    }
    
    try {
      // This is safe to call multiple times
      await _safeController!.enableLocation();
      
      if (widget.enableTrackingOnLoad) {
        await _safeController!.trackLocation(true, bearingMode: 0);
      }
    } catch (e) {
      debugPrint('❌ Error enabling location: $e');
      // Handle error - maybe show a snackbar to user
    }
  }
  
  // Public method to enable location from outside
  Future<void> enableLocation() async {
    return _enableLocationSafely();
  }
  
  // Public method to toggle tracking from outside
  Future<void> toggleTracking() async {
    if (_safeController == null) return;
    
    final newState = !_safeController!.isTracking;
    await _safeController!.trackLocation(newState);
  }
  
  @override
  void reassemble() {
    // Called during hot reload
    super.reassemble();
    // Don't re-enable location here! iOS side will handle it
    debugPrint('📍 Hot reload detected - not re-enabling location');
  }
  
  @override
  void dispose() {
    debugPrint('📍 Disposing map widget');
    _safeController?.resetLocationState();
    _safeController = null;
    super.dispose();
  }
}
```

---

## 3. Example Usage in Your App

### Simple usage:

```dart
class MyMapPage extends StatefulWidget {
  @override
  State<MyMapPage> createState() => _MyMapPageState();
}

class _MyMapPageState extends State<MyMapPage> {
  final GlobalKey<_SafeMapWidgetState> _mapKey = GlobalKey();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Map')),
      body: SafeMapWidget(
        key: _mapKey,
        initialCenter: LatLng(37.7749, -122.4194), // San Francisco
        initialZoom: 12,
        enableLocationOnLoad: true, // Safe - won't duplicate
        enableTrackingOnLoad: false,
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'location',
            child: Icon(Icons.my_location),
            onPressed: () async {
              // Safe to call multiple times
              await _mapKey.currentState?.enableLocation();
            },
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'tracking',
            child: Icon(Icons.navigation),
            onPressed: () async {
              // Safe to call multiple times
              await _mapKey.currentState?.toggleTracking();
            },
          ),
        ],
      ),
    );
  }
}
```

---

## 4. Migration Guide

If you have existing code, here's how to migrate:

### Before (Unsafe):
```dart
class _MyMapState extends State<MyMap> {
  MapLibreMapController? _controller;
  
  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _controller!.enableLocation(); // ❌ Called too early, no safety
  }
  
  void _onStyleLoaded() {
    _controller!.enableLocation(); // ❌ Might be called twice!
  }
}
```

### After (Safe):
```dart
class _MyMapState extends State<MyMap> {
  SafeMapLibreController? _safeController;
  
  void _onMapCreated(MapLibreMapController controller) {
    _safeController = SafeMapLibreController(controller);
    // Don't enable location here
  }
  
  Future<void> _onStyleLoaded() async {
    // ✅ Safe - wrapper prevents duplicates
    await _safeController?.enableLocation();
  }
}
```

---

## 5. Common Patterns

### Pattern 1: Enable location on button press
```dart
ElevatedButton(
  onPressed: () async {
    if (_safeController != null) {
      await _safeController!.enableLocation(); // Safe!
    }
  },
  child: Text('Enable Location'),
)
```

### Pattern 2: Toggle tracking mode
```dart
IconButton(
  icon: Icon(_safeController?.isTracking == true 
    ? Icons.navigation 
    : Icons.navigation_outlined
  ),
  onPressed: () async {
    if (_safeController != null) {
      await _safeController!.trackLocation(
        !_safeController!.isTracking,
        bearingMode: 1, // Compass mode
      );
      setState(() {}); // Update icon
    }
  },
)
```

### Pattern 3: Check permission before enabling
```dart
Future<void> _enableLocationWithPermission() async {
  // Check permission first
  final permission = await Permission.location.request();
  
  if (permission.isGranted) {
    await _safeController?.enableLocation(); // Safe!
  } else {
    // Show error to user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Location permission denied')),
    );
  }
}
```

---

## 6. Testing Checklist

After implementing these changes, test:

- ✅ Enable location via button - no crash
- ✅ Enable location, then press button again - no crash
- ✅ Hot reload while location enabled - no crash
- ✅ Hot restart while location enabled - no crash
- ✅ Navigate away and back - no crash
- ✅ Enable tracking, then disable - no crash
- ✅ Switch tracking modes rapidly - no crash
- ✅ Enable location on style load - no crash

---

## 7. Debug Logging

The safe controller includes debug prints. To see them in your console:

```bash
# iOS (Xcode)
# Look for prints starting with 📍, ✅, or ❌

# Flutter console
flutter run --verbose
```

---

## Summary

The key changes are:

1. ✅ **Wrap controller** with `SafeMapLibreController` for state tracking
2. ✅ **Wait for `onStyleLoadedCallback`** before enabling location
3. ✅ **Use safe methods** that check state before calling iOS
4. ✅ **Handle hot reload** without re-enabling location
5. ✅ **Proper disposal** to clean up state

These changes work together with the iOS fixes already implemented to completely prevent the crash.

---

## Need Help?

If you encounter issues:

1. Check the console logs for 📍, ✅, ❌ prefixed messages
2. Verify you're calling `enableLocation()` only after `onStyleLoadedCallback`
3. Make sure you're using the `SafeMapLibreController` wrapper
4. Ensure your Flutter MapLibre version is up to date

The iOS side is now bulletproof - these Flutter changes just add an extra layer of safety.
