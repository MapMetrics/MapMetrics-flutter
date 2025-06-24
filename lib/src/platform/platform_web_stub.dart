import 'package:mapmetrics/src/map_state.dart';
import 'package:mapmetrics/src/offline/offline_manager.dart';
import 'package:mapmetrics/src/permission_manager.dart';
import 'package:mapmetrics/src/platform_interface.dart';

/// A stub web implementation that throws unsupported errors for mobile platforms.
final class PlatformImpl extends PlatformInterface {
  @override
  MapLibreMapState createWidgetState() {
    throw UnimplementedError('Web platform is not supported on this platform');
  }

  @override
  Future<OfflineManager> createOfflineManager() {
    throw UnimplementedError('Web platform is not supported on this platform');
  }

  @override
  PermissionManager createPermissionManager() {
    throw UnimplementedError('Web platform is not supported on this platform');
  }
}
