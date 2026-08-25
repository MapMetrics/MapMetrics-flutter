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
  static const protomapsLight =
      'https://api.protomaps.com/styles/v2/light.json?key=$_protomapsKey';
  static const protomapsDark =
      'https://api.protomaps.com/styles/v2/dark.json?key=$_protomapsKey';
  static const maptilerStreets =
      'https://api.maptiler.com/maps/streets-v2/style.json?key=$_maptilerKey';

  static const _maptilerKey = 'OPCgnZ51sHETbEQ4wnkd';
  static const _protomapsKey = 'a6f9aebb3965458c';
}
