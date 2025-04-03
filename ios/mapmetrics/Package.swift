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
    // Needs to be the same version as in ../maplibre_ios.podspec
    .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", .upToNextMinor(from: "6.11.0")),
  ],
  targets: [
    .target(
      name: "mapmetrics",
      dependencies: [
        .product(name: "MapLibre", package: "maplibre-gl-native-distribution"),
      ],
      cSettings: [
        .headerSearchPath("include/mapmetrics"),
      ]
    ),
  ]
)
