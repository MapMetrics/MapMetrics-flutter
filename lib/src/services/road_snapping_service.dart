import 'dart:math' as math;
import 'package:mapmetrics/mapmetrics.dart';

/// Service for snapping GPS locations to the nearest road or navigation route
class RoadSnappingService {
  RoadSnappingService({
    this.snapDistance = 5.0, // meters - precise snapping within 5 meters
    this.preferRoute = true,
    this.smoothingFactor = 0.75, // balanced for smooth response
  });

  final double snapDistance;
  final bool preferRoute;
  final double smoothingFactor;

  Position? _lastSnappedPosition;
  double? _lastBearing;
  List<Position>? _currentRoute;
  int _currentRouteSegmentIndex = 0;

  /// Set the current navigation route for route-aware snapping
  void setNavigationRoute(List<Position> routePoints) {
    _currentRoute = routePoints;
    _currentRouteSegmentIndex = 0;
  }

  /// Clear the navigation route
  void clearNavigationRoute() {
    _currentRoute = null;
    _currentRouteSegmentIndex = 0;
  }

  /// Snap a GPS position to the nearest road or route
  SnappedLocation snapToRoad(Position gpsPosition, {double? gpsBearing}) {
    // If we have an active route and prefer route snapping
    if (_currentRoute != null && preferRoute) {
      return _snapToRoute(gpsPosition, gpsBearing);
    }

    // Otherwise, snap to nearest road (simplified for now)
    return _snapToNearestRoad(gpsPosition, gpsBearing);
  }

  /// Snap to the active navigation route
  SnappedLocation _snapToRoute(Position gpsPosition, double? gpsBearing) {
    if (_currentRoute == null || _currentRoute!.isEmpty) {
      return SnappedLocation(
        position: gpsPosition,
        bearing: gpsBearing ?? 0,
        confidence: 0.0,
        isSnapped: false,
      );
    }

    // Find the closest point on the route
    double minDistance = double.infinity;
    Position? closestPoint;
    double? segmentBearing;
    int closestSegmentIndex = _currentRouteSegmentIndex;

    // Search nearby segments (optimize by not searching entire route)
    // Search a bit behind and further ahead based on typical movement
    final searchStart = math.max(0, _currentRouteSegmentIndex - 2);
    final searchEnd = math.min(_currentRoute!.length - 1, _currentRouteSegmentIndex + 10);

    for (int i = searchStart; i < searchEnd && i < _currentRoute!.length - 1; i++) {
      final start = _currentRoute![i];
      final end = _currentRoute![i + 1];

      final result = _closestPointOnSegment(gpsPosition, start, end);

      if (result.distance < minDistance) {
        minDistance = result.distance;
        closestPoint = result.point;
        segmentBearing = result.bearing;
        closestSegmentIndex = i;
      }
    }

    // Update current segment index for next iteration
    _currentRouteSegmentIndex = closestSegmentIndex;

    // Only snap if within snap distance
    if (closestPoint != null && minDistance <= snapDistance) {
      // Smooth the position to avoid jumps
      final snappedPos = _smoothPosition(closestPoint, _lastSnappedPosition);
      _lastSnappedPosition = snappedPos;

      // Smooth the bearing
      final snappedBearing = _smoothBearing(segmentBearing ?? 0, _lastBearing);
      _lastBearing = snappedBearing;

      return SnappedLocation(
        position: snappedPos,
        bearing: snappedBearing,
        confidence: 1.0 - (minDistance / snapDistance),
        isSnapped: true,
        distanceAlongRoute: _calculateDistanceAlongRoute(closestSegmentIndex),
      );
    }

    // Too far from route, return original position
    return SnappedLocation(
      position: gpsPosition,
      bearing: gpsBearing ?? _lastBearing ?? 0,
      confidence: 0.0,
      isSnapped: false,
    );
  }

  /// Snap to the nearest road (simplified implementation)
  SnappedLocation _snapToNearestRoad(Position gpsPosition, double? gpsBearing) {
    // TODO: Query map for actual road features
    // For now, just smooth the position

    final smoothedPos = _smoothPosition(gpsPosition, _lastSnappedPosition);
    _lastSnappedPosition = smoothedPos;

    final bearing = gpsBearing ?? _lastBearing ?? 0;
    _lastBearing = bearing;

    return SnappedLocation(
      position: smoothedPos,
      bearing: bearing,
      confidence: 0.5,
      isSnapped: false,
    );
  }

  /// Find the closest point on a line segment to a given point
  _SegmentResult _closestPointOnSegment(Position point, Position start, Position end) {
    // Convert to projected coordinates for accurate distance calculation
    final dx = end.lng - start.lng;
    final dy = end.lat - start.lat;

    if (dx == 0 && dy == 0) {
      // Start and end are the same point
      return _SegmentResult(
        point: start,
        distance: _calculateDistance(point, start),
        bearing: 0,
      );
    }

    // Calculate projection factor (0 to 1 means on segment)
    final t = math.max(0, math.min(1,
      ((point.lng - start.lng) * dx + (point.lat - start.lat) * dy) /
      (dx * dx + dy * dy)
    ));

    // Calculate the closest point
    final closestPoint = Position(
      start.lng + t * dx,
      start.lat + t * dy,
    );

    // Calculate bearing along segment
    final bearing = _calculateBearing(start, end);

    return _SegmentResult(
      point: closestPoint,
      distance: _calculateDistance(point, closestPoint),
      bearing: bearing,
    );
  }

  /// Calculate distance between two positions in meters
  double _calculateDistance(Position p1, Position p2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians((p2.lat - p1.lat).toDouble());
    final dLon = _toRadians((p2.lng - p1.lng).toDouble());

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(p1.lat.toDouble())) *
        math.cos(_toRadians(p2.lat.toDouble())) *
        math.sin(dLon / 2) * math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Calculate bearing between two positions
  double _calculateBearing(Position start, Position end) {
    final dLon = _toRadians((end.lng - start.lng).toDouble());
    final lat1 = _toRadians(start.lat.toDouble());
    final lat2 = _toRadians(end.lat.toDouble());

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360;
  }

  /// Smooth position transitions
  Position _smoothPosition(Position newPos, Position? lastPos) {
    if (lastPos == null) return newPos;

    // If smoothing factor is close to 1, just return the new position immediately
    if (smoothingFactor >= 0.95) return newPos;

    return Position(
      lastPos.lng + (newPos.lng - lastPos.lng) * smoothingFactor,
      lastPos.lat + (newPos.lat - lastPos.lat) * smoothingFactor,
    );
  }

  /// Smooth bearing transitions
  double _smoothBearing(double newBearing, double? lastBearing) {
    if (lastBearing == null) return newBearing;

    // Handle bearing wrap-around
    var diff = newBearing - lastBearing;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    return (lastBearing + diff * smoothingFactor) % 360;
  }

  /// Calculate distance along route to current position
  double _calculateDistanceAlongRoute(int segmentIndex) {
    if (_currentRoute == null || _currentRoute!.isEmpty) return 0;

    double distance = 0;
    for (int i = 0; i < segmentIndex && i < _currentRoute!.length - 1; i++) {
      distance += _calculateDistance(_currentRoute![i], _currentRoute![i + 1]);
    }
    return distance;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;
  double _toDegrees(double radians) => radians * 180 / math.pi;
}

/// Result of snapping a location to a road
class SnappedLocation {
  final Position position;
  final double bearing;
  final double confidence;
  final bool isSnapped;
  final double? distanceAlongRoute;

  SnappedLocation({
    required this.position,
    required this.bearing,
    required this.confidence,
    required this.isSnapped,
    this.distanceAlongRoute,
  });
}

/// Internal result for segment calculations
class _SegmentResult {
  final Position point;
  final double distance;
  final double bearing;

  _SegmentResult({
    required this.point,
    required this.distance,
    required this.bearing,
  });
}