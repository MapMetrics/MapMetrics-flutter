// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "mapmetrics",
  platforms: [
    .iOS("12.0"),
  ],
  products: [
    .library(name: "mapmetrics", targets: ["mapmetrics"]),
  ],
  dependencies: [
    // WARNING: this NO LONGER matches ../mapmetrics.podspec, and the mismatch
    // is not cosmetic.
    //
    // The CocoaPods path depends on `MapMetrics-SDK` -- our own map core, with
    // v2 HMAC map sessions, gateway pinning, MapMetrics branding, and Mapbox
    // telemetry removed. This SPM path still resolves UPSTREAM MapLibre, which
    // has none of it. An app built with Swift Package Manager therefore gets a
    // map that renders but never opens a billed session and carries MapLibre
    // branding -- with no build error to say so.
    //
    // It cannot be fixed here. SPM resolves binary targets from a distribution
    // repo (the way maplibre-gl-native-distribution serves upstream), and we
    // publish no such repo for MapMetrics-SDK 2.0.0. Closing this gap means
    // creating one and publishing a Package.swift that vends our xcframework.
    //
    // Until then, iOS builds must go through CocoaPods. Do not enable
    // `flutter config --enable-swift-package-manager` for this plugin.
    .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", .upToNextMinor(from: "6.11.0")),
  ],
  targets: [
    .target(
      name: "mapmetrics",
      dependencies: [
        .product(name: "MapLibre", package: "maplibre-gl-native-distribution"),
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
