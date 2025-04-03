import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:mapmetrics/src/map_state.dart';
import 'package:mapmetrics/src/offline/offline_manager.dart';
import 'package:mapmetrics/src/permission_manager.dart';
import 'package:mapmetrics/src/platform/web/map_state.dart';
import 'package:mapmetrics/src/platform_interface.dart';

/// A web implementation of the MapLibrePlatform of the MapLibre plugin.
final class PlatformImpl extends PlatformInterface {
  /// This static method registers [PlatformImpl] when running on web.
  static void registerWith(Registrar registrar) =>
      PlatformInterface.instance = PlatformImpl();

  @override
  MapLibreMapState createWidgetState() => MapLibreMapStateWeb();

  @override
  Future<OfflineManager> createOfflineManager() =>
      throw Exception('The OfflineManager can not be used on web.');

  @override
  PermissionManager createPermissionManager() {
    throw Exception('The PermissionManager can not be used on web.');
  }
}
