## 2.0.0

**Breaking: the default map style changed.** `MapOptions.initStyle` used to
default to `https://demotiles.maplibre.org/style.json`. Every app that never
set a style was rendering MapLibre's tiles, from MapLibre's servers, with
MapLibre's branding. It now defaults to the MapMetrics demo style, which is
**rate-limited, capped at zoom 12 and watermarked**.

This is the reason for the major version bump rather than a minor one: on a
`^1.0.6` constraint the change would have arrived automatically and put a
watermark on live maps. Set `initStyle` to your own style and pass `apiKey`
before upgrading. Get a key at https://mapatlas.eu .

**Breaking: iOS now builds against MapMetrics-SDK, not upstream MapLibre.**
CocoaPods and Swift Package Manager previously resolved different binaries
from the same source tree — SPM silently gave you upstream MapLibre with no
v2 map sessions, MapLibre branding and Mapbox telemetry, with no build error
to say so. Both paths now resolve MapMetrics-SDK 2.0.1.

### Billing

* iOS and Android open a **v2 map session**: one charge per map load instead
  of one per tile. On a cold start that is the difference between 1 and 8+.
* The SDK now waits for an in-flight session create before sending gateway
  requests. Without this the opening style-and-tile wave went out unsigned and
  fell back to per-tile billing, with no visible symptom — the map rendered
  correctly and the cost was silent.
* iOS example: `Podfile.lock` was pinned to MapMetrics-SDK 2.0.0, below the
  documented floor, which billed per tile. Now 2.0.1.

### Android

* mapmetrics-native-sdk 2.0.2 → **2.0.3**. The default artefact is now the
  OpenGL ES build rather than Vulkan. Vulkan renders correctly on real
  hardware but fails on emulators, and its manifest declared
  `uses-feature android.hardware.vulkan.version required="true"`, which merges
  into your app and makes Google Play **hide it from every device without
  Vulkan**. That declaration is gone from the default artefact. Apps wanting
  Vulkan can depend on `mapmetrics-native-sdk-vulkan` directly.

### Security

* Removed three non-expiring production API keys from the package and its
  example, including one granting the full routing surface (directions,
  map_matching, optimize, matrix, isochrone). One of them shipped inside every
  published archive up to 1.0.6. **If you vendored or copied those keys, stop
  using them — they are being revoked.**
* Examples now use the credential-free demo style, so there is no key in the
  example app to copy by accident.

## 1.0.6
* Thread-safe image handling improvements for iOS and Android
* Style controller thread safety enhancements
* MapViewDelegate thread safety improvements

## 1.0.3
* Add native sprite loading for iOS via Pigeon channel
* Add addImages() and addSprite() methods for iOS
* Fix duplicate onStyleLoaded callback issue on iOS
* Improve icon loading performance on both platforms

## 1.0.0
* Fix iOS compilation errors (NSNumber extensions, CGPoint struct)
* Add type safety improvements for FFI stubs
* Implement missing MapController methods for web platform
* Update Flutter constraint to remove upper bound (>=3.29.0)
* Add navigation route support (setNavigationRoute, clearNavigationRoute)
* Add location dragging support (setLocationDraggable)
* Fix type casting issues across all platforms
* Improve offline manager type safety

## 0.1.0
* MM waterMark Logo Added


0.0.9 release
Markers Fixed


0.0.8 release
bugs fixed



0.0.7 release
bugs fixed


0.0.6 release
zoombuttons are optional now,auto load to user current location


0.0.5
0.0.5 release
bugs fixed for IOS


0.0.4
0.0.4 release
bugs fixed for IOS

0.0.3
0.0.3 release
bugs fixed for android
Add docs

0.0.2
0.0.2 release
bugs fixed for android
Add docs

0.0.1
Initial release
Implement map for android ios and web