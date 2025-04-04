import 'dart:io';

import 'package:mapmetrics/src/map_state.dart';
import 'package:mapmetrics/src/offline/offline_manager.dart';
import 'package:mapmetrics/src/permission_manager.dart';
import 'package:mapmetrics/src/platform/android/map_state.dart';
import 'package:mapmetrics/src/platform/android/offline_manager.dart';
import 'package:mapmetrics/src/platform/android/permission_manager.dart';
import 'package:mapmetrics/src/platform/ios/map_state.dart';
import 'package:mapmetrics/src/platform/ios/offline_manager.dart';
import 'package:mapmetrics/src/platform/ios/permission_manager.dart';
import 'package:mapmetrics/src/platform_interface.dart';

/// An implementation of [PlatformInterface] that uses method channels and ffi.
final class PlatformImpl extends PlatformInterface {
  @override
  MapLibreMapState createWidgetState() {
    if (Platform.isAndroid) return MapLibreMapStateAndroid();
    if (Platform.isIOS) return MapLibreMapStateIos();
    throw UnimplementedError('Unsupported platform');
  }

  @override
  Future<OfflineManager> createOfflineManager() async {
    if (Platform.isAndroid) return OfflineManagerAndroid.createInstance();
    if (Platform.isIOS) return OfflineManagerIos.createInstance();
    throw UnimplementedError('Unsupported platform');
  }

  @override
  PermissionManager createPermissionManager() {
    if (Platform.isAndroid) return PermissionManagerAndroid();
    if (Platform.isIOS) return const PermissionManagerIos();
    throw UnimplementedError('Unsupported platform');
  }
}
