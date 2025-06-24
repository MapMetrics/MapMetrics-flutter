import 'dart:convert';
import 'dart:ffi';

import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/platform/maplibre_ffi.dart';

/// Internal extensions on [LngLatBounds].
extension LngLatBoundsExt on LngLatBounds {
  /// Convert a [LngLatBounds] to a [MLNCoordinateBounds].
  MLNCoordinateBounds toMLNCoordinateBounds() {
    final bounds = Struct.create<MLNCoordinateBounds>();
    bounds.sw =
        Struct.create<CLLocationCoordinate2D>()
          ..longitude = longitudeWest
          ..latitude = latitudeSouth;
    bounds.ne =
        Struct.create<CLLocationCoordinate2D>()
          ..longitude = longitudeEast
          ..latitude = latitudeNorth;
    return bounds;
  }
}

/// Internal extensions on [MLNCoordinateBounds].
extension MLNCoordinateBoundsExt on MLNCoordinateBounds {
  /// Convert a [MLNCoordinateBounds] to a [LngLatBounds].
  LngLatBounds toLngLatBounds() => LngLatBounds(
    longitudeWest: sw.longitude,
    longitudeEast: ne.longitude,
    latitudeSouth: sw.latitude,
    latitudeNorth: ne.latitude,
  );
}

/// Internal extensions on [String].
extension StringExt on String {
  /// Convert a dashed separated name to camel case.
  String dashedToCamelCase() =>
      split('-').indexed.map((entry) {
        final index = entry.$1;
        final word = entry.$2;
        // Keep the first word in lowercase
        if (index == 0) return word;
        return word[0].toUpperCase() + word.substring(1);
      }).join();
}

/// UTF8 Encoding
const nsUTF8StringEncoding = 4;
