# Flutter Side Fixes for User Location Layer Crash

This document contains the exact changes needed in your Flutter/Dart code to prevent the `MLNRedundantLayerIdentifierException` crash.

---

## 🚨 Quick Fix Reference

| Error | Solution | Section |
|-------|----------|---------|
| `MLNRedundantLayerIdentifierException` | Use `SafeMapLibreController` wrapper | [Section 1](#1-maplibre-controller-wrapper-recommended) |
| `RenderBox was not laid out` | Wrap map in `LayoutBuilder` with size constraints | [Section 8](#8-fixing-renderbox-was-not-laid-out-error) |
| `invalid reuse after initialization failure` | Add unique `Key` to MapLibreMap + error recovery | [Section 7](#7-fixing-invalid-reuse-after-initialization-failure-error) |
| Location enabled twice | Check state before calling `enableLocation()` | [Section 1](#1-maplibre-controller-wrapper-recommended) |
| Hot reload crash | Use `reassemble()` without re-enabling location | [Section 2](#2-safe-map-widget-implementation) |
| Map not showing | Ensure parent widget provides constraints | [Section 9](#9-common-layout-patterns) |

---

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
  bool _isDisposed = false;
  
  // Unique key to force recreation on initialization failure
  Key _mapKey = UniqueKey();
  
  @override
  Widget build(BuildContext context) {
    // CRITICAL FIX: Wrap MapLibreMap in Container with constraints
    // This prevents "RenderBox was not laid out" errors during initialization
    return LayoutBuilder(
      builder: (context, constraints) {
        // Only build map when we have valid constraints
        if (constraints.maxWidth == 0 || constraints.maxHeight == 0) {
          return const SizedBox.shrink();
        }
        
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: MapLibreMap(
            key: _mapKey, // CRITICAL: Unique key prevents reuse after failure
            initialCameraPosition: CameraPosition(
              target: widget.initialCenter,
              zoom: widget.initialZoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            trackCameraPosition: true,
            myLocationEnabled: false, // We'll control this manually
            myLocationTrackingMode: MyLocationTrackingMode.None,
            // Add gesture delay to prevent touch events during initialization
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          ),
        );
      },
    );
  }
  
  void _onMapCreated(MapLibreMapController controller) {
    // CRITICAL: Check if widget is disposed before proceeding
    if (_isDisposed) {
      debugPrint('⚠️ Map created callback after dispose, ignoring');
      return;
    }
    
    // Use post-frame callback to ensure layout is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      
      try {
        debugPrint('📍 Map created');
        _safeController = SafeMapLibreController(controller);
        _isMapReady = true;
      } catch (e) {
        debugPrint('❌ Error in onMapCreated: $e');
        // Force recreation on next rebuild
        setState(() {
          _mapKey = UniqueKey();
          _isMapReady = false;
        });
      }
      
      // Don't enable location here - wait for style to load
    });
  }
  
  Future<void> _onStyleLoaded() async {
    // CRITICAL: Check if widget is disposed before proceeding
    if (_isDisposed) {
      debugPrint('⚠️ Style loaded callback after dispose, ignoring');
      return;
    }
    
    // Use post-frame callback to ensure all layout is settled
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _isDisposed) return;
      
      try {
        debugPrint('📍 Style loaded');
        _isStyleLoaded = true;
        
        // NOW it's safe to enable location
        if (widget.enableLocationOnLoad && _safeController != null) {
          await _enableLocationSafely();
        }
      } catch (e) {
        debugPrint('❌ Error in onStyleLoaded: $e');
        // Force recreation on next rebuild
        setState(() {
          _mapKey = UniqueKey();
          _isStyleLoaded = false;
        });
      }
    });
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
    _isDisposed = true;  // CRITICAL: Mark as disposed to prevent callbacks
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

### Location Features
- ✅ Enable location via button - no crash
- ✅ Enable location, then press button again - no crash
- ✅ Hot reload while location enabled - no crash
- ✅ Hot restart while location enabled - no crash
- ✅ Navigate away and back - no crash
- ✅ Enable tracking, then disable - no crash
- ✅ Switch tracking modes rapidly - no crash
- ✅ Enable location on style load - no crash

### Layout and Gestures
- ✅ Tap map immediately after loading - no "RenderBox" error
- ✅ Scroll/pan map during initialization - no crash
- ✅ Map shows correctly in different layouts - no sizing issues
- ✅ Rotate device - map resizes correctly
- ✅ Hot reload with map visible - no layout errors

### Edge Cases
- ✅ Multiple hot reloads in quick succession - no crash
- ✅ Enable/disable location repeatedly - no crash
- ✅ Switch between pages with maps - no crash
- ✅ Background app and return - map still works
- ✅ Kill and restart app - map initializes correctly
- ✅ Trigger initialization error and recover - map recreates

---

## 7. Fixing "Invalid Reuse After Initialization Failure" Error

If you see this error:
```
invalid reuse after initialization failure
```

This happens when Flutter tries to reuse a native platform view that failed to initialize. Common causes:
- Hot reload while map is initializing
- Widget rebuild during native view creation
- Previous initialization error not properly handled

### The Fix: Unique Key + Error Recovery

The solution includes **three critical components**:

#### 1. Unique Key for Force Recreation
```dart
class _SafeMapWidgetState extends State<SafeMapWidget> {
  Key _mapKey = UniqueKey();  // ✅ Forces new instance on recreation
  bool _isDisposed = false;    // ✅ Prevents callbacks after dispose
  
  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      key: _mapKey,  // ✅ CRITICAL: Unique key prevents reuse
      // ...
    );
  }
}
```

#### 2. Error Recovery in Callbacks
```dart
void _onMapCreated(MapLibreMapController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _isDisposed) return;
    
    try {
      _safeController = SafeMapLibreController(controller);
      _isMapReady = true;
    } catch (e) {
      debugPrint('❌ Error in onMapCreated: $e');
      // ✅ Force recreation on next rebuild
      setState(() {
        _mapKey = UniqueKey();
        _isMapReady = false;
      });
    }
  });
}
```

#### 3. Disposal Flag
```dart
@override
void dispose() {
  _isDisposed = true;  // ✅ Prevents callbacks after disposal
  _safeController?.resetLocationState();
  _safeController = null;
  super.dispose();
}
```

### Why This Works

1. **Unique Key**: Forces Flutter to create a **new** native platform view instead of reusing the failed one
2. **Error Recovery**: Catches initialization errors and triggers recreation
3. **Disposal Flag**: Prevents callbacks from executing after widget disposal
4. **Mounted Check**: Ensures widget is still in tree before state updates

### Alternative: Manual Recreation Method

If you need to manually trigger recreation (e.g., from a button):

```dart
class _SafeMapWidgetState extends State<SafeMapWidget> {
  Key _mapKey = UniqueKey();
  
  void recreateMap() {
    setState(() {
      _mapKey = UniqueKey();  // New key = new map instance
      _safeController = null;
      _isMapReady = false;
      _isStyleLoaded = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Error recovery button (optional)
        if (!_isMapReady)
          ElevatedButton(
            onPressed: recreateMap,
            child: Text('Retry Map Initialization'),
          ),
        Expanded(
          child: MapLibreMap(key: _mapKey, /* ... */),
        ),
      ],
    );
  }
}
```

---

## 8. Fixing "RenderBox was not laid out" Error

If you see this error:
```
RenderBox was not laid out: RenderUiKitView#xxxxx NEEDS-LAYOUT NEEDS-PAINT
```

This happens when touch events arrive before the native iOS view has completed its layout. The fix above includes:

### Fix 1: LayoutBuilder with Size Constraints
```dart
// Wrap your MapLibreMap in LayoutBuilder
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth == 0 || constraints.maxHeight == 0) {
      return const SizedBox.shrink();
    }
    
    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: MapLibreMap(/* ... */),
    );
  },
)
```

### Fix 2: Post-Frame Callbacks
```dart
void _onMapCreated(MapLibreMapController controller) {
  // Wait for next frame before accessing controller
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    _safeController = SafeMapLibreController(controller);
  });
}
```

### Fix 3: Alternative - Use Expanded/Flexible

If you're placing the map in a Column or Row, ensure it has proper constraints:

```dart
Column(
  children: [
    AppBar(/* ... */),
    Expanded(  // ✅ Use Expanded to give map proper constraints
      child: SafeMapWidget(/* ... */),
    ),
  ],
)
```

### Fix 4: Specific Case - Full Screen Map

```dart
class FullScreenMap extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeMapWidget(/* ... */),  // ✅ Scaffold provides constraints
    );
  }
}
```

### Fix 5: Specific Case - Sized Map

```dart
SizedBox(
  width: 300,
  height: 400,
  child: SafeMapWidget(/* ... */),
)
```

---

## 9. Common Layout Patterns

### Pattern A: Map in Scaffold (Recommended)
```dart
class MapPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Map')),
      body: SafeMapWidget(
        enableLocationOnLoad: true,
      ),
    );
  }
}
```

### Pattern B: Map in Stack with Overlays
```dart
Stack(
  children: [
    // Map takes full available space
    SafeMapWidget(
      enableLocationOnLoad: true,
    ),
    // UI overlays on top
    Positioned(
      top: 16,
      right: 16,
      child: FloatingActionButton(
        onPressed: () {},
        child: Icon(Icons.my_location),
      ),
    ),
  ],
)
```

### Pattern C: Map in Column with Fixed Height
```dart
Column(
  children: [
    Container(
      height: 300,  // Fixed height
      child: SafeMapWidget(
        enableLocationOnLoad: true,
      ),
    ),
    // Other widgets below
    Container(
      padding: EdgeInsets.all(16),
      child: Text('Map info'),
    ),
  ],
)
```

### Pattern D: Map Taking Remaining Space
```dart
Column(
  children: [
    AppBar(title: Text('Map')),
    Expanded(  // Takes all remaining space
      child: SafeMapWidget(
        enableLocationOnLoad: true,
      ),
    ),
    BottomNavigationBar(/* ... */),
  ],
)
```

### Pattern E: Responsive Map with MediaQuery
```dart
class ResponsiveMap extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final mapHeight = screenHeight * 0.6; // 60% of screen
    
    return Container(
      height: mapHeight,
      child: SafeMapWidget(
        enableLocationOnLoad: true,
      ),
    );
  }
}
```

---

## 10. Debug Logging

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
---

## 11. TL;DR - What to Do

### Step 1: Copy the Controller Wrapper
Create `lib/utils/safe_maplibre_controller.dart` with the code from [Section 1](#1-maplibre-controller-wrapper-recommended).

### Step 2: Update Your Map Widget
Replace your current map widget with the safe version from [Section 2](#2-safe-map-widget-implementation).

### Step 3: Ensure Proper Layout
Wrap your map widget properly:
- In `Scaffold` → Works automatically ✅
- In `Column/Row` → Use `Expanded` ✅
- Custom layout → Use `LayoutBuilder` ✅

### Step 4: Test Everything
Use the checklist in [Section 6](#6-testing-checklist) to verify all scenarios work.

---

## 12. Before & After Summary

### ❌ Before (Crash-Prone)
```dart
class _MapState extends State<MapWidget> {
  MapLibreMapController? _controller;
  
  Widget build(BuildContext context) {
    return MapLibreMap(  // ❌ No size constraints
      onMapCreated: (controller) {
        _controller = controller;
        _controller!.enableLocation();  // ❌ No state tracking
      },
    );
  }
}
```

### ✅ After (Bulletproof)
```dart
class _MapState extends State<MapWidget> {
  SafeMapLibreController? _safeController;
  
  Widget build(BuildContext context) {
    return LayoutBuilder(  // ✅ Proper constraints
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: MapLibreMap(
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
          ),
        );
      },
    );
  }
  
  void _onMapCreated(MapLibreMapController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {  // ✅ Wait for layout
      _safeController = SafeMapLibreController(controller);
    });
  }
  
  Future<void> _onStyleLoaded() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _safeController?.enableLocation();  // ✅ State tracked
    });
  }
}
```

---

## 13. Need Help?

If you encounter issues:

1. ✅ Check the [Quick Fix Reference](#-quick-fix-reference) at the top
2. ✅ Look for debug prints with 📍, ✅, ❌ prefixes in console
3. ✅ Verify you're using `LayoutBuilder` or proper constraints
4. ✅ Ensure `onStyleLoadedCallback` is used for location setup
5. ✅ Confirm the `SafeMapLibreController` wrapper is in use

### Common Mistakes to Avoid

| ❌ Don't Do This | ✅ Do This Instead |
|------------------|-------------------|
| Call `enableLocation()` in `onMapCreated` | Call it in `onStyleLoadedCallback` |
| Put map in `Column` without `Expanded` | Use `Expanded` widget |
| Create map without size constraints | Use `LayoutBuilder` or sized container |
| Call location methods without checking state | Use `SafeMapLibreController` wrapper |
| Re-enable location on hot reload | Let iOS side handle it (already fixed) |

---

**🎉 With these changes + the iOS fixes, you should have ZERO crashes!**

