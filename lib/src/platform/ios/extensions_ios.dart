import 'package:objective_c/objective_c.dart' as objc;


import 'dart:ffi' as ffi;
import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/platform/maplibre_ffi.dart';

extension BoolExt on bool {
  objc.NSNumber toNSNumber() => objc.NSNumber.numberWithBool_(this ? 1 : 0);
}

extension IntExt on int {
  objc.NSNumber toNSNumber() => objc.NSNumber.numberWithInt_(this);
}

extension StringExt on String {
  /// Convert to a [NSURL].
  objc.NSURL? toNSURL() => objc.NSURL.URLWithString_(toNSString());

  /// Convert to a [NSData].
  objc.NSData? toNSDataUTF8() =>
      toNSString().dataUsingEncoding_(4); // nsUTF8StringEncoding = 4
}

extension PositionExtensions on Position {
  CLLocationCoordinate2D toCLLocationCoordinate2D() {
    final coord = ffi.Struct.create<CLLocationCoordinate2D>();
    coord.latitude = lat;
    coord.longitude = lng;
    return coord;
  }
}

extension CLLocationCoordinate2DExtensions on CLLocationCoordinate2D {
  Position toPosition() {
    return Position(longitude, latitude);
  }
}

extension OffsetExtensions on Offset {
  CGPoint toCGPoint() {
    final point = ffi.Struct.create<CGPoint>();
    point.x = dx;
    point.y = dy;
    return point;
  }
}

extension CGPointExtensions on CGPoint {
  Offset toOffset() {
    return Offset(x, y);
  }
}

extension LngLatBoundsExtensions on LngLatBounds {
  MLNCoordinateBounds toMLNCoordinateBounds() {
    final sw = ffi.Struct.create<CLLocationCoordinate2D>()
      ..longitude = longitudeWest
      ..latitude = latitudeSouth;
    final ne = ffi.Struct.create<CLLocationCoordinate2D>()
      ..longitude = longitudeEast
      ..latitude = latitudeNorth;
    final bounds = ffi.Struct.create<MLNCoordinateBounds>()
      ..sw = sw
      ..ne = ne;
    return bounds;
  }
}