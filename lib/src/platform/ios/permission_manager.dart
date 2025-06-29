import 'package:flutter/services.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/platform/pigeon.g.dart' as pigeon;

/// Enhanced iOS specific implementation of the [PermissionManager].
class PermissionManagerIos implements PermissionManager {
  /// Create a new [PermissionManagerIos] instance.
  const PermissionManagerIos();

  static final pigeon.PermissionManagerHostApi _hostApi =
  pigeon.PermissionManagerHostApi();

  static const MethodChannel _channel = MethodChannel('mapmetrics');

  // Cache for permission status
  static bool _cachedLocationPermission = false;
  static bool _cachedBackgroundPermission = false;

  @override
  bool get backgroundLocationPermissionGranted {
    return _cachedBackgroundPermission;
  }

  @override
  bool get locationPermissionsGranted {
    // Return cached value - this must be synchronous
    return _cachedLocationPermission;
  }

  @override
  bool get runtimePermissionsRequired {
    // iOS always requires runtime permissions for location
    return true;
  }

  @override
  Future<bool> requestLocationPermissions({required String explanation}) async {
    try {
      print('Dart: Calling requestLocationPermissions with explanation: $explanation');

      // This will check current status and request if needed
      final result = await _hostApi.requestLocationPermissions(explanation: explanation);

      print('Dart: Permission result: $result');

      // Update cache after permission request
      await updatePermissionCache();

      return result;
    } catch (e) {
      print('Error requesting location permissions: $e');
      return false;
    }
  }

  // MARK: - Cache Management Methods

  /// Update cached permission status by checking current iOS status
  static Future<void> updatePermissionCache() async {
    try {
      final locationGranted = await _channel.invokeMethod('getLocationPermissionsGranted') as bool;
      final backgroundGranted = await _channel.invokeMethod('getBackgroundLocationPermissionGranted') as bool;

      _cachedLocationPermission = locationGranted;
      _cachedBackgroundPermission = backgroundGranted;

      print('Cache updated - Location: $locationGranted, Background: $backgroundGranted');
    } catch (e) {
      print('Error updating permission cache: $e');
    }
  }

  /// Get current permission status asynchronously (for real-time checking)
  Future<bool> getLocationPermissionsGrantedAsync() async {
    try {
      final result = await _channel.invokeMethod('getLocationPermissionsGranted') as bool;
      _cachedLocationPermission = result;
      return result;
    } catch (e) {
      print('Error getting location permissions status: $e');
      return false;
    }
  }

  /// Get current background permission status asynchronously
  Future<bool> getBackgroundLocationPermissionGrantedAsync() async {
    try {
      final result = await _channel.invokeMethod('getBackgroundLocationPermissionGranted') as bool;
      _cachedBackgroundPermission = result;
      return result;
    } catch (e) {
      print('Error getting background location permission status: $e');
      return false;
    }
  }

  /// Clear permission cache
  static void clearCache() {
    _cachedLocationPermission = false;
    _cachedBackgroundPermission = false;
  }

  /// Get cached permission values (for debugging)
  static bool get cachedLocationPermission => _cachedLocationPermission;
  static bool get cachedBackgroundPermission => _cachedBackgroundPermission;
}