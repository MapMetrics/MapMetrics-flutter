# iOS Crash Investigation Log

## Issue Summary
iOS app crashes when MarkerLayer is rendered with text markers on the markers page.

---

## Issue 1: MethodChannel Timing Crash ✅ FIXED

**Status**: RESOLVED  
**Fix Location**: `ios/mapmetrics/Sources/maplibre_ios/MapViewDelegate.swift`

**Root Cause**:  
MethodChannel was called before Flutter engine was ready, causing EXC_BAD_ACCESS crash.

**Solution**:  
Added custom MethodChannel specifically for onStyleLoaded callback to ensure Flutter engine is ready:
```swift
private func notifyStyleLoaded() {
    // Use custom MethodChannel for onStyleLoaded to avoid timing issues
    let flutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
        name: "maplibre_custom",
        binaryMessenger: flutterViewController.binaryMessenger
    )
    
    channel.invokeMethod("onStyleLoaded", arguments: nil)
    debugPrint("✅ Swift: Successfully invoked onStyleLoaded via custom MethodChannel")
}
```

**Test Result**: ✅ Markers page loads without crash, custom MethodChannel successfully delivers onStyleLoaded event

---

## Issue 2: MarkerLayer Color Property Crash ❌ ONGOING

**Status**: IN PROGRESS  
**Affected Files**:
- `lib/src/layer/marker_layer.dart`
- `lib/src/platform/ios/extensions.dart`

### Investigation Timeline

#### Test 1: Minimal MarkerLayer (No icon)
**Result**: CRASH  
**Configuration**:
```dart
MarkerLayer(
  points: _points,
  textField: 'Marker',
  textAllowOverlap: true,
  textOffset: const [0, 1],
)
```
**Finding**: Crash occurs even without iconImage, proving icon is not the cause.

#### Test 2: Property-by-Property Debug Logging
**Method**: Added logging to `extensions.dart` `_applyExpression()` to identify crash point.

**Result**: Crash identified at `text-color` property application  
**Log Evidence**:
```
flutter: ✅ iOS: Successfully applied property "icon-opacity"
flutter: ✅ iOS: Successfully applied property "icon-halo-width"
flutter: ✅ iOS: Successfully applied property "icon-halo-blur"
flutter: ✅ iOS: Successfully applied property "text-opacity"
flutter: 📍 iOS: Applying property "text-color"...
Lost connection to device.
```

#### Test 3: Try-Catch Protection
**Attempt**: Wrapped color property setters in try-catch blocks in `extensions.dart`.

**Result**: FAILED - Try-catch cannot prevent iOS FFI crashes  
**Reason**: FFI crashes occur at native Objective-C level, below Dart runtime.

#### Test 4: Hex Color Format Fix (6-char to 8-char)
**Hypothesis**: iOS parseNSExpression requires 8-character hex colors with alpha channel (#RRGGBBAA), but code was generating 6-character format (#RRGGBB) using `toHexString(alpha: false)`.

**Implementation**:
- Changed all `toHexString(alpha: false)` calls to `toHexString()` in `marker_layer.dart`
- Added conditional logic to skip `icon-color` and `icon-halo-color` when `iconImage == null` (SDF icons requirement)

**File**: `lib/src/layer/marker_layer.dart` lines 195-196, 200-201
```dart
// iOS FFI FIX: Only include icon colors when image exists (SDF requirement)
if (iconImage != null) 'icon-color': iconColor.toHexString(),
if (iconImage != null) 'icon-halo-color': iconHaloColor.toHexString(),
// iOS FFI FIX: Always use alpha channel for iOS color parsing
'text-color': textColor.toHexString(),
'text-halo-color': textHaloColor.toHexString(),
```

**Result**: STILL CRASHES  
**Test Log**: `/tmp/flutter_COMPLETE_fix_test.log` - Crash occurs immediately after `onStyleLoaded`, before any property logging appears.

### Current Analysis

**New Finding**: Crash happens BEFORE property application logging starts, which means it's occurring during:
1. `ffiStyleLayer.setProperties(layer.paint)` call in `style_controller.dart` line 108, OR
2. Inside `setProperty()` method's color parsing logic in `extensions.dart` lines 170-180

**Critical Code Path** (`extensions.dart`):
```dart
// Line 170-180: Color properties go through parseNSExpression
if (key.contains('color')) {
    try {
        // Create a JSON literal expression: "literal", "#RRGGBB" or "#RRGGBBAA"
        final colorExpression = '["literal", "$value"]';
        expression = parseNSExpression(key, colorExpression);  // <-- CRASH HERE
    } catch (error) {
        // This catch won't work for FFI crashes
        debugPrint('⚠️ iOS: Color parsing failed for "$key": $error');
    }
}
```

**Root Cause Theory**: `parseNSExpression()` is a Swift/Objective-C FFI call that creates an MGLColor object from the hex string. Even with 8-character hex colors (#RRGGBBAA), this parsing might be failing or creating an invalid NSExpression that crashes when applied to the MLNSymbolStyleLayer.

### Next Steps

**Option A**: Skip ALL color properties for MarkerLayer on iOS
- Modify `marker_layer.dart` to detect iOS platform and omit color properties entirely
- Markers will render with default colors (black text, no icon colors)
- Clean solution but loses color customization

**Option B**: Use Pigeon method channel to set colors in Swift
- Similar to VectorSource zoom fix, create Swift method to set color properties
- Swift can safely handle MGLColor creation and error handling
- More complex but preserves full functionality

**Option C**: Debug parseNSExpression implementation
- Investigate what hex color format iOS MapLibre SDK actually expects
- May need to check MapLibre iOS source code for proper color string format
- Could be format like "rgb(0,0,0)" instead of "#000000FF"

---

## Test Evidence Files

1. `/tmp/flutter_no_marker_layer_test.log` - App works perfectly without MarkerLayer
2. `/tmp/flutter_marker_without_icon_test.log` - MarkerLayer crashes even without iconImage
3. `/tmp/flutter_property_debug.log` - Identified crash at icon-color property
4. `/tmp/flutter_icon_color_fix_test.log` - Still crashed after skipping icon-color
5. `/tmp/flutter_FINAL_marker_fix.log` - Crash at text-color property
6. `/tmp/flutter_COMPLETE_fix_test.log` - Still crashes with alpha channel included
