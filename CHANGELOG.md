## 2.0.1

* **`filter`, `minZoom` and `maxZoom` now work on fill, line and background
  layers.** They were declared on the base class but never forwarded by those
  constructors, so `FillStyleLayer(filter: ...)` did not compile — and even if
  it had, no platform applied them: only the circle and symbol code paths
  packed them for the native side. Fill, line and background now forward the
  fields, both platforms apply them, and a background layer correctly ignores
  `filter` because it has no source to filter.

  This was written for 2.0.0 and listed in its changelog, but the upload
  completed before the code landed. 2.0.0 ships without it; this is the
  version that has it.

  Still not covered: `FillExtrusionStyleLayer` and `HeatmapStyleLayer` on iOS,
  whose native handlers ignore every argument and report success. Exposing the
  properties there would have been a lie.

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

### Fixed — rendering

Everything below shipped after the 2.0.0 version bump was first cut. Most of
it is the difference between a layer drawing and a layer drawing nothing, and
in every case the old behaviour failed silently.

* **The high-level `layers:` API rendered nothing on iOS.** Three faults at
  once: the source was a bare `GeometryCollection` (valid GeoJSON, but not a
  feature, so a style layer has nothing to draw), `Feature.toJson` emitted
  `"id": null` which MapLibre's parser rejects outright, and the source and
  layer calls were fired without awaiting, so the layer regularly landed
  first and failed with `Source not found`. Every widget in that API —
  `CircleLayer`, `MarkerLayer`, `PolygonLayer`, `PolylineLayer` — was affected.
* **Clustered GeoJSON did not render on iOS.** A dynamic `UIColor` cannot be
  used as an `NSExpression` constant, the cluster-count layer had no font
  stack, and `addCircleLayer` silently discarded app-supplied layers on a
  clustered source.
* **`MarkerLayer` drew zero features on iOS.** Its default font stack had two
  entries; MapLibre requests a multi-font stack as one comma-joined glyph
  path, and that path 404s. Exactly one entry now.
* **`getCamera().zoom` returned altitude in metres on iOS** — values in the
  millions. The zoom buttons stepped from that number, so they desynced from
  pinch gestures. Both now read the real zoom level.
* **iOS dropped most symbol layout properties.** `text-font`,
  `symbol-sort-key`, `symbol-z-order`, `symbol-placement`, the
  `text-allow-overlap` family, `text-offset`/`icon-offset` and others were
  discarded by a hand-written whitelist that had no entry for them. Unknown
  properties are now logged instead of vanishing.
* **Raster sources and raster layers are implemented on iOS.** They existed in
  the Dart API and did nothing.
* **Android parsed `text-font` as an expression.** A font stack is data, not
  an expression, so symbol layers using one rendered no labels.
* **Android discarded every raster layer property** — the `setProperties`
  call was commented out.

### Examples

* Each example now points its camera at its own content, uses its own
  geometry, and carries the icons it needs. Several were rendering correctly
  into empty ocean.
* New POI demo: vector tiles through the gateway, category-ranked icons and
  category badge circles.
* README written.

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