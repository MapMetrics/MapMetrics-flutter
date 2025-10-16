# iOS NSNumber Extension Method Resolution Issue

## Problem Summary
POI vector tile icons disappear on iOS after zoom level 16 because zoom level options cannot be passed to `MLNVectorTileSource` during initialization. The issue stems from Dart's inability to resolve the `NSNumber.numberWithInt_()` extension method from the `objective_c` package.

## Root Cause Analysis

### The NSNumberCreation Extension
In the `objective_c` package (v6.0.0), the `numberWithInt_()` method is defined as a static extension method on the `NSNumber` class:

**File**: `/Users/jimvanderheiden/.pub-cache/hosted/pub.dev/objective_c-6.0.0/lib/src/objective_c_bindings_generated.dart`

```dart
/// NSNumberCreation
extension NSNumberCreation on NSNumber {
  /// numberWithInt:
  static NSNumber numberWithInt_(int value) {
    final _ret =
        _objc_msgSend_14hvw5k(_class_NSNumber, _sel_numberWithInt_, value);
    return NSNumber.castFromPointer(_ret, retain: true, release: true);
  }
  // ... other factory methods
}
```

This extension is properly exported from the main `objective_c.dart` file:

```dart
export 'src/objective_c_bindings_generated.dart'
    show
        NSNumber,
        NSNumberCreation,
        // ... other exports
```

### Why It Fails

Despite proper exports and imports, Dart's analyzer cannot resolve the extension method when called:

```dart
// This fails with: "The method 'numberWithInt_' isn't defined for the type 'NSNumber'"
final minZoomValue = NSNumber.numberWithInt_(source.minZoom ?? 0);
```

**Attempted Solutions (all failed)**:
1. ❌ Hiding NSNumber from maplibre_ffi import: `import '...maplibre_ffi.dart' hide NSNumber;`
2. ❌ Explicit NSNumberCreation import: `import 'package:objective_c/src/objective_c_bindings_generated.dart' show NSNumberCreation;`
3. ❌ Prefixing objective_c imports: `import 'package:objective_c/objective_c.dart' as objc;`
4. ❌ Dual imports (prefixed and unprefixed)
5. ❌ Using objc_internal namespace

### Key Observations

1. **No Direct NSNumber Export from maplibre_ffi.dart**: The maplibre_ffi.dart file imports objective_c with `as objc` prefix, so all its NSNumber references are `objc.NSNumber`. There's no shadowing at the import level.

2. **Extension is Properly Exported**: Both `NSNumber` class and `NSNumberCreation` extension are exported from `objective_c.dart`.

3. **Analyzer Can't Resolve**: Despite the extension being in scope, Dart's static analyzer fails to resolve the static extension method.

##hypothesis
This appears to be a limitation or bug in Dart's extension method resolution, possibly related to:
- Static methods on extensions
- Extension methods across package boundaries
- Interaction between FFI-generated code and extension methods

## Impact

**Symptoms**:
- POI vector tile icons disappear when zooming beyond the server's `maxZoom` level (typically 16)
- Icons reappear when zooming back within the server's zoom range
- This only affects iOS; Android properly configures zoom levels

**Technical Reason**:
Without passing `MLNTileSourceOptionMinimumZoomLevel` and `MLNTileSourceOptionMaximumZoomLevel` in the options dictionary, the iOS MapLibre SDK does not enable tile overzooming (displaying lower zoom level tiles at higher zoom levels).

## Workarounds

### Current State (What's Implemented)
The code now uses an empty `NSDictionary` for options and logs a warning:

```dart
// style_controller.dart:201-215
debugPrint('⚠️ iOS: VectorSource zoom options not set - overzooming beyond z${source.maxZoom} may not work');
vectorSource.initWithIdentifier_tileURLTemplates_options_(
  source.id.toNSString(),
  ffiUrls,
  NSDictionary.new1(),  // Empty options - no zoom levels set
);
```

### Solution 1: Server-Side (Temporary)
Increase the tile server's `maxZoom` to 18+ so vector tiles are available at higher zoom levels.

**Pros**: Simple, no code changes needed
**Cons**: Requires server configuration, larger tile sizes

### Solution 2: Pigeon Method Channel (Recommended)
Create a native Swift method to construct the options NSDictionary:

**Dart side** (`pigeon.dart`):
```dart
@HostApi()
abstract class MapLibreHostApi {
  // ... existing methods

  Map<String, Object> createVectorSourceOptions(int minZoom, int maxZoom);
}
```

**Swift side** (to be implemented):
```swift
func createVectorSourceOptions(minZoom: Int64, maxZoom: Int64) throws -> [String: Any] {
  return [
    MLNTileSourceOption.minimumZoomLevel.rawValue: NSNumber(value: minZoom),
    MLNTileSourceOption.maximumZoomLevel.rawValue: NSNumber(value: maxZoom)
  ]
}
```

**Pros**: Clean API, native Swift handles NSNumber creation
**Cons**: Requires Pigeon regeneration and Swift implementation

### Solution 3: Direct objc_msgSend (Advanced)
Call the underlying Objective-C runtime method directly:

```dart
// Requires importing internal FFI methods
import 'dart:ffi' as ffi;
import 'package:objective_c/src/internal.dart' as objc_internal;

final minZoomPtr = objc_internal.objc_msgSend(
  objc_internal.getNSClass('NSNumber'),
  objc_internal.registerName('numberWithInt:'),
  ffi.Pointer.fromAddress(source.minZoom ?? 0),
);
```

**Pros**: No Pigeon changes needed
**Cons**: Extremely fragile, bypasses type safety, uses internal APIs

## Files Modified

### lib/src/platform/ios/style_controller.dart
- **Lines 201-215**: Documented NSNumberCreation extension limitation
- **Behavior**: Uses empty options dictionary, logs warning about zoom limitation

### lib/src/platform/ios/map_state.dart
- **Lines 12-15**: Standard objective_c imports (NSNumberCreation import attempt removed)
- **No changes needed**: Imports are correct, issue is with extension resolution

## Reproduction

1. Configure vector tile source with `maxZoom: 16`
2. Add POI symbol layer using the vector source
3. Zoom to level 17+ on iOS
4. **Expected**: Icons remain visible (tiles overzoom)
5. **Actual**: Icons disappear (no overzooming)

## References

- iOS MapLibre SDK MLNTileSourceOption documentation
- objective_c package v6.0.0: NSNumberCreation extension
- Flutter issue tracker: (search for "extension method resolution")
- Dart language spec: Extension methods (static methods on extensions)

## Next Steps

Implement Solution 2 (Pigeon method channel) as it provides the cleanest and most maintainable solution. This requires:
1. Add method to pigeon.dart
2. Regenerate Pigeon bindings: `dart run pigeon --input pigeon.dart`
3. Implement Swift method in ios/mapmetrics/Sources/maplibre_ios/MapLibreHostApi.swift
4. Update style_controller.dart to call the new method
5. Test POI visibility at zoom levels 17+
