// Create this file: lib/src/platform/ios/map_view_registry.dart

import 'package:mapmetrics/src/platform/maplibre_ffi.dart';

class MLNMapViewRegistry {
  static final Map<int, MLNMapView> _mapViews = {};

  static void registerMapView(int viewId, MLNMapView mapView) {
    _mapViews[viewId] = mapView;
  }

  static MLNMapView? getMapView(int viewId) {
    return _mapViews[viewId];
  }

  static void unregisterMapView(int viewId) {
    _mapViews.remove(viewId);
  }

  static void clear() {
    _mapViews.clear();
  }
}