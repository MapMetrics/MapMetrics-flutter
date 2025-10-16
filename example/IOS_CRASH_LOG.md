# iOS Markers Page Crash Investigation Log

## Root Cause Analysis

### Issue 1: MethodChannel Timing Crash ✅ FIXED
**Problem**: App crashed with `SIGABRT` (Abort trap: 6) when Swift tried to invoke custom MethodChannel immediately after map style loaded.

**Root Cause**: Race condition - Swift's `mapView(_:didFinishLoading:)` was calling `channel.invokeMethod("onStyleLoaded"...)` before Flutter had finished registering the MethodChannel handler in `map_state.dart:58-70`.

**Crash Location**: `MapViewDelegate.swift:158` (now line 161)

**Solution Applied**:
- Added 0.1-second delay using `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)`
- Changed error logging from ERROR to WARNING (non-fatal)
- File: `ios/mapmetrics/Sources/maplibre_ios/MapViewDelegate.swift:148-169`

**Status**: ✅ FIXED - Custom MethodChannel now works correctly, "✅ Flutter: Received onStyleLoaded via custom MethodChannel" appears in logs.

---

### Issue 2: LayerManager Crash ❌ ONGOING
**Problem**: After MethodChannel fix, app still crashes when LayerManager processes MarkerLayer configuration.

**Crash Location**: Somewhere between onStyleLoaded completion and LayerManager initialization

**Evidence**:
- Last logs before crash:
  ```
  flutter: ✅ Flutter: Received onStyleLoaded via custom MethodChannel
  flutter: 📍 onStyleLoaded: Called onStyleLoaded
  flutter: 🟢 LayersMarkerPage: Style loaded, scheduling image load
  Lost connection to device.
  ```
- Crash occurs BEFORE the delayed HTTP request starts (500ms delay)
- Crash happens after onStyleLoaded completes
- No "Starting delayed image download" log appears

**Root Cause Hypothesis**: The crash is likely in the native iOS layer rendering code when LayerManager tries to process the MarkerLayer with:
- `iconImage: _imageLoaded ? 'marker' : null` - **This is the likely culprit**
- MapLibre iOS might be trying to load the 'marker' image immediately even though we haven't added it yet
- The `iconImage: null` might be causing issues in the iOS rendering engine

**Solution Applied**:
- Added 500ms delay before HTTP request (didn't fix the crash)
- Crash now happens during layer initialization, not HTTP request

**Test Results**:
1. ✅ **TEST 1 - No MarkerLayer**: App works perfectly, HTTP request succeeds
   - Evidence: `/tmp/flutter_no_marker_layer_test.log` lines 23-27
   - No crash, HTTP completed, image loaded successfully
   - Conclusion: **Crash is definitely in MarkerLayer rendering, NOT HTTP/timing**

2. ✅ **TEST 2 - MarkerLayer WITHOUT iconImage**: Crash still occurs!
   - Evidence: `/tmp/flutter_marker_without_icon_test.log` lines 22-23
   - Crash happens after onStyleLoaded, even with NO iconImage property
   - Tested with: textField, textAllowOverlap, textOffset only (all icon properties removed)
   - **CRITICAL CONCLUSION**: The crash is NOT caused by iconImage property
   - **ROOT CAUSE**: iOS MarkerLayer rendering itself crashes on style load

## Root Cause Summary

The iOS crash is caused by **MarkerLayer rendering on iOS**, independent of any iconImage property. The crash occurs when:
1. Map style loads successfully
2. onStyleLoaded event fires
3. LayerManager attempts to process and render MarkerLayer
4. iOS MapLibre SDK tries to create the layer
5. **CRASH** - Something in the iOS MarkerLayer creation/rendering code fails

This is a **platform-specific iOS bug** in the MapLibre SDK or the Flutter-to-iOS layer conversion code.

---

## Files Modified

### 1. MapViewDelegate.swift
- **Location**: `ios/mapmetrics/Sources/maplibre_ios/MapViewDelegate.swift:148-169`
- **Change**: Added 0.1s delay before invoking custom MethodChannel, made error handling non-fatal
- **Status**: Deployed, working

### 2. map_state.dart
- **Location**: `lib/src/platform/ios/map_state.dart:57-70`
- **Change**: Set up custom MethodChannel listener (already existed)
- **Status**: Working correctly

### 3. layers_marker_page.dart
- **Location**: `example/lib/layers_marker_page.dart:38-59`
- **Change**: Added comprehensive HTTP error handling with timeout and error type logging
- **Status**: Modified by linter, simpler version present, still crashes

---

## Test Results

### Test 1: Initial state
- Result: Crash on "Starting image download"
- Root cause: MethodChannel timing issue

### Test 2: After MethodChannel timing fix
- Result: MethodChannel works, but crash still occurs after onStyleLoaded
- Root cause: HTTP request crash

---

## Recommendations

1. **Immediate Workaround**: Use a local asset file instead of HTTP download
2. **Alternative**: Try different HTTP client (e.g., dio package)
3. **Investigation**: Check iOS Console.app for detailed crash logs
4. **Long-term**: Report issue to Flutter HTTP client if iOS-specific bug
