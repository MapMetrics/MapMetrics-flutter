/// Style URLs used by the example app.
///
/// The protomaps and maptiler keys below are UPSTREAM's demo keys, inherited
/// from the MapLibre Flutter plugin this was forked from, and they get rotated
/// occasionally. Use your own for your project.
///
/// NO MAPMETRICS CREDENTIAL BELONGS IN THIS FILE. It previously held a
/// `token` constant -- a MapMetrics JWT for one account, scoped maps+search,
/// with NO `exp` claim, so it never expired -- and a `testMap` URL built from
/// it. Nothing referenced either one, but this file ships inside the published
/// package, so the credential went out in every release on pub.dev and sits in
/// git history. It has been removed; the account's token needs revoking
/// server-side, which is the only thing that actually closes it.
///
/// Pass a MapMetrics API key through `MapOptions.apiKey` instead. That is what
/// opens a v2 map session, and it never has to be committed.
abstract class MapStyles {
  /// The MapMetrics demo style. No credential, and none needed.
  ///
  /// This is what the example pages use by default, and what
  /// `MapOptions.initStyle` falls back to. It is rate-limited, capped at zoom
  /// 12 and watermarked -- deliberately fine for "does my setup work" and
  /// deliberately useless as a product.
  ///
  /// NOT SUITABLE FOR OFFLINE DOWNLOADS. A region download asks for thousands
  /// of tiles as fast as it can; the per-IP burst limit throttles that, and
  /// anything above zoom 12 does not exist. See offline_page.dart, which
  /// stays on a third-party style for exactly this reason.
  ///
  /// For real work, get a key at https://mapatlas.eu and pass it via
  /// `MapOptions.apiKey` with your own style.
  static const demo = 'https://gateway.mapmetrics-atlas.net/demo/style.json';

  static const protomapsLight =
      'https://api.protomaps.com/styles/v2/light.json?key=$_protomapsKey';
  static const protomapsDark =
      'https://api.protomaps.com/styles/v2/dark.json?key=$_protomapsKey';
  static const maptilerStreets =
      'https://api.maptiler.com/maps/streets-v2/style.json?key=$_maptilerKey';

  static const _maptilerKey = 'OPCgnZ51sHETbEQ4wnkd';
  static const _protomapsKey = 'a6f9aebb3965458c';
}
