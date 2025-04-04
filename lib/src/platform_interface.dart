import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/map_state.dart';
import 'package:mapmetrics/src/platform/platform_web.dart'
    if (dart.library.io) 'package:mapmetrics/src/platform/platform_native.dart';

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
  static PlatformInterface instance = PlatformImpl();

  /// Return a platform specific [State<MapLibreMap>] object.
  MapLibreMapState createWidgetState();

  /// Return a platform specific [OfflineManager] object.
  Future<OfflineManager> createOfflineManager();

  /// Return a platform specific [PermissionManager] object.
  PermissionManager createPermissionManager();
}
