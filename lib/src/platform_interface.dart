import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/map_state.dart';
import 'package:mapmetrics/src/platform/platform_native.dart' as native;
// Conditional import for web platform
import 'package:mapmetrics/src/platform/platform_web_stub.dart'
    as web
    if (dart.library.html) 'package:mapmetrics/src/platform/platform_web.dart';

/// https://pub.dev/packages/plugin_platform_interface#a-note-about-base
abstract base class PlatformInterface {
  /// Constructs a MapLibrePlatform.
  const PlatformInterface();

  /// The default instance of [PlatformInterface] to use.
  ///
  /// Defaults to [PlatformImpl].
  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PlatformInterface] when
  /// they register themselves.
  static PlatformInterface get instance {
    // Use the web implementation if we're on web
    if (_isWeb) {
      print('PlatformInterface: Using web implementation');
      return _webInstance;
    }
    // Use the native implementation for mobile platforms
    print('PlatformInterface: Using native implementation');
    return _nativeInstance;
  }

  static final PlatformInterface _nativeInstance = native.PlatformImpl();
  static final PlatformInterface _webInstance = web.PlatformImpl();

  static bool get _isWeb {
    try {
      final result = identical(0, 0.0);
      print('PlatformInterface: _isWeb check result = $result');
      return result;
    } catch (e) {
      print('PlatformInterface: _isWeb check exception = $e');
      return false;
    }
  }

  /// Return a platform specific [State<MapLibreMap>] object.
  MapLibreMapState createWidgetState();

  /// Return a platform specific [OfflineManager] object.
  Future<OfflineManager> createOfflineManager();

  /// Return a platform specific [PermissionManager] object.
  PermissionManager createPermissionManager();
}
