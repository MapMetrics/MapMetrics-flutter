// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// NOW RESOLVES MAPMETRICS-SDK, not upstream MapLibre.
//
// This used to depend on maplibre/maplibre-gl-native-distribution while the
// CocoaPods path (../mapmetrics.podspec) depended on MapMetrics-SDK. The two
// build systems therefore produced DIFFERENT BINARIES from the same source
// tree: `flutter config --enable-swift-package-manager` silently gave you
// upstream MapLibre, with no v2 map sessions, MapLibre branding, and Mapbox
// telemetry present -- and no build error to say so. The only symptom was
// billing: every tile on the v1 path instead of one session per map load.
//
// A separate distribution repo is NOT needed for this. SPM can consume a
// remote binary directly, and the iOS release already publishes exactly the
// artefact it wants: MapLibre.dynamic.xcframework.zip, with the .xcframework
// at the root of the archive.
//
// KEEPING THIS IN STEP WITH THE PODSPEC IS MANUAL. The podspec resolves
// `MapMetrics-SDK ~> 2.0.1` through CocoaPods, so a new patch release reaches
// it automatically; a binaryTarget is pinned to one URL and one checksum and
// does not. On every iOS release, update BOTH the url and the checksum here.
// Get the checksum with:
//
//     swift package compute-checksum MapLibre.dynamic.xcframework.zip
//
// A stale url/checksum pair fails loudly at resolve time, which is the right
// failure -- unlike the silent divergence this replaced.
let mapMetricsSDKVersion = "2.0.1"
let mapMetricsSDKChecksum = "0d64504ad38b54055a6e2294fbc63e13ea646bcfdb88e377ce04e41a7bb382a8"

let package = Package(
  name: "mapmetrics",
  platforms: [
    .iOS("12.0"),
  ],
  products: [
    .library(name: "mapmetrics", targets: ["mapmetrics"]),
  ],
  targets: [
    // The module is still called `MapLibre` because the framework inside the
    // xcframework is still named MapLibre.framework -- which is why every
    // `import MapLibre` in Sources/ keeps working. Renaming the framework is a
    // 3.0.0 change; the pod is already called MapMetrics-SDK.
    .binaryTarget(
      name: "MapLibre",
      url: "https://github.com/MapMetrics/mapmetrics-native-sdk/releases/download/ios-v\(mapMetricsSDKVersion)/MapLibre.dynamic.xcframework.zip",
      checksum: mapMetricsSDKChecksum
    ),
    .target(
      name: "mapmetrics",
      dependencies: [
        .target(name: "MapLibre"),
      ],
      sources: [
        "Sources/maplibre_ios",
      ],
      cSettings: [
        .headerSearchPath("include/mapmetrics"),
      ],
      swiftSettings: [
        .define("SWIFT_PACKAGE"),
      ]
    ),
  ]
)
