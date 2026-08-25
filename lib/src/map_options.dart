import 'package:flutter/widgets.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/inherited_model.dart';

/// The [MapOptions] class is used to set default values for the [MapLibreMap]
/// widget.
///
/// {@category Basic}
@immutable
class MapOptions {
  /// Default constructor for the [MapOptions].
  const MapOptions({
    // Defaults to OUR demo style, not MapLibre's demotiles server.
    //
    // This used to be https://demotiles.maplibre.org/style.json, which meant
    // every consumer who did not pass a style rendered MapLibre's tiles, from
    // MapLibre's infrastructure, with MapLibre's branding -- traffic we do not
    // serve, cannot meter, and should not be sending to a third party.
    //
    // The replacement needs no credential: it is rate-limited, capped at zoom
    // 12 and watermarked. That makes it correct as a DEFAULT specifically --
    // a default must work with no configuration at all, which is why a real
    // style behind an API key cannot go here.
    //
    // It is deliberately not good enough to ship. Pass your own style (and an
    // apiKey) for anything real; get one at https://mapatlas.eu .
    this.initStyle = 'https://gateway.mapmetrics-atlas.net/demo/style.json',
    this.initZoom = 0,
    this.initCenter,
    @Deprecated('Renamed to initPitch') double? pitch,
    double initPitch = 0,
    this.initBearing = 0,
    this.minZoom = 0,
    this.maxZoom = 22,
    this.minPitch = 0,
    this.maxPitch = 60,
    this.maxBounds,
    this.gestures = const MapGestures.all(),
    this.androidTextureMode = true,
    this.androidMode = AndroidPlatformViewMode.tlhc_vd,
    this.apiKey,
  }) : initPitch = pitch ?? initPitch;

  /// Find the [MapOptions] of the closest [MapLibreMap] in the widget tree.
  /// Returns null if called outside of the [MapLibreMap.children].
  static MapOptions? maybeOf(BuildContext context) =>
      MapLibreInheritedModel.maybeMapControllerOf(context)?.options;

  /// Find the [MapOptions] of the closest [MapLibreMap] in the widget tree.
  /// Throws an [StateError] if called outside of the [MapLibreMap.children].
  static MapOptions of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError('Unable to find an instance of MapOptions'));

  /// The style URL that should get used.
  ///
  /// If not set, the MapMetrics demo style is used
  /// (https://gateway.mapmetrics-atlas.net/demo/style.json): no credential
  /// required, but rate-limited, capped at zoom 12 and watermarked. It exists
  /// so a map renders with zero configuration, not so it can be shipped.
  ///
  /// For anything real, pass your own style and set [apiKey]. Get a key at
  /// https://mapatlas.eu .
  final String initStyle;

  /// The initial zoom level.
  final double initZoom;

  /// The initial pitch level. Minimum is 0 and maximum is 85 on web and 60 on
  /// other platforms.
  final double initPitch;

  /// The initial bearing of the map. Defaults to 0 (north on top).
  /// 360 is exactly one loop.
  final double initBearing;

  /// The initial center on the map.
  final Position? initCenter;

  /// The minimum zoom level. Allowed values are 0-24. Defaults to 0.
  final double minZoom;

  /// The maximum zoom level. Allowed values are 0-24. Defaults to 22.
  final double maxZoom;

  /// The minimum camera pitch / tilt. Allowed values on web are 0-85. Allowed
  /// values on other platforms are 0-60, bigger values will get ignored.
  ///
  /// Defaults to 0.
  final double minPitch;

  /// The maximum camera pitch / tilt. Allowed values on web are 0-85. Allowed
  /// values on other platforms are 0-60, bigger values will get ignored.
  final double maxPitch;

  /// The maximum bounding box of the map camera. No constraints are in place
  /// if set to `null`.
  final LngLatBounds? maxBounds;

  /// Enable and disable some or all map gestures.
  final MapGestures gestures;

  /// The platform view type used on android.
  ///
  /// https://docs.flutter.dev/platform-integration/android/platform-views
  final AndroidPlatformViewMode androidMode;

  /// The MapMetrics maps-scoped API key.
  ///
  /// Required on Android AND iOS for the v2 map session to be established.
  /// Without it the native SDK holds no key, no session is created, and every
  /// tile silently falls back to v1 billing -- which charges per request on a
  /// cold load rather than once per session.
  ///
  /// On iOS this is applied to `MLNSettings.apiKey`, which the SDK watches. A
  /// session also needs the gateway origin, pinned via the `MLNTileServerBaseURL`
  /// key in the app's Info.plist; the key alone is not enough.
  ///
  /// Unused on web, where auth comes from the JWT embedded in the style URL.
  final String? apiKey;

  /// Toggle the texture mode on Android.
  ///
  /// textureMode comes at a significant performance penalty.
  /// https://maplibre.org/maplibre-native/android/api/-map-libre%20-native%20-android/org.maplibre.android.maps/-map-libre-map-options/texture-mode.html
  final bool androidTextureMode;
}
