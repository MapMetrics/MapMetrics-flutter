// FINDINGS (measured on staging, iPhone 17 Pro simulator, 2026-08-24)
//
// Tile signing through Flutter iOS WORKS -- but only when the API key is
// present at app LAUNCH, via Info.plist's MLNApiKey:
//
//   key in Info.plist MLNApiKey : 8x200, 0x401, 7 tiles cached, meter delta 1
//   key via MapOptions.apiKey   : 1x200 (the session create), 18x401,
//                                 0 tiles cached, meter delta 1
//
// The 200s are genuinely v2-signed, not key-in-URL auth: the gateway answers
// 401 to /v2/tiles for `?key=<apiKey>` and `?token=<apiKey>` alike, so only a
// valid session signature can produce a 200. Meter delta stays 1 while 7 tiles
// are served, which is the v2 property -- tiles ride the session instead of
// billing per request.
//
// So MapOptions.apiKey opens and bills a session, and then every request goes
// out unsigned and 401s. The map is blank. This is very likely the long-
// standing "Flutter renders blank" bug.
//
// ROOT CAUSE NOT ESTABLISHED. The obvious suspect is ordering -- the key is
// applied inside MapLibreView's getOptions callback, milliseconds before the
// first style/tile request -- but that is NOT yet proven. The MM_DELAY_MS
// probe below was written to test it and CANNOT: delaying the map widget also
// delays the getOptions callback that sets the key, so both move together and
// the race window is unchanged. A valid test needs the key set from Dart
// BEFORE any map view is constructed, which the plugin currently offers no
// API for. Do not read the MM_DELAY_MS=4000 result as evidence either way.
//
// A throwaway entrypoint that exists to answer two questions about iOS Flutter:
//
//   1. Does passing MapOptions.apiKey open exactly one v2 map session?
//   2. Are the tile requests that follow SIGNED with that session?
//
// Run it against staging, never production:
//
//   KEY=$(python3 -c "import json;print(json.load(open(
//     '.../gateway-mapatlas/staging-creds.json'))['mapsApiKey'])")
//   flutter run -t lib/staging_session_main.dart -d <simulator> \
//     --dart-define=MM_API_KEY="$KEY"
//
// The key arrives by --dart-define and is never written to the repo;
// staging-creds.json is gitignored and must stay out of tracked files.
//
// The gateway ORIGIN is not set here -- it comes from MLNTileServerBaseURL in
// example/ios/Runner/Info.plist. MMMapSession needs BOTH halves, key and pinned
// origin, before it creates anything, so changing only one produces a silent
// no-op rather than an error.
//
// WHY THE STYLE IS WRITTEN TO A LOCAL FILE. Question 2 needs real tile traffic
// aimed at the gateway, which means a style whose tiles[] points at staging.
// The gateway cannot serve that style itself: the style manager reads
// PRODUCTION API_KEYS, so /v2/styles answers 403 on staging. Hosting it over
// local HTTP would need an ATS exemption in the app. Writing it to a temp file
// and loading it by file:// URL avoids both, and keeps the request under test
// (the tile) as the only thing crossing the network.
//
// This also exercises the harder path on purpose. Because the style is NOT
// served by the gateway, the gateway's first sight of this client is the
// opening tile -- exactly the case the eager-create logic exists to handle.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

const _apiKey = String.fromEnvironment('MM_API_KEY');
const _gateway = String.fromEnvironment(
  'MM_GATEWAY',
  defaultValue: 'https://gateway-mapatlas-staging.jim9710.workers.dev',
);

/// Centre on tile z12/2094/1362 -- the same tile the native SDK's staging
/// tests use, so a 404 here means the tile is missing rather than the
/// signature being wrong.
const _lat = 51.5;
const _lng = 4.04;

/// A minimal vector style. MapLibre only fetches tiles for sources referenced
/// by a visible layer, so the fill layer is load-bearing: without it the
/// source is inert and no tile request is ever made.
String _styleJson() => jsonEncode({
      'version': 8,
      'name': 'staging-signing-probe',
      'sources': {
        'staging': {
          'type': 'vector',
          'tiles': ['$_gateway/v2/tiles/{z}/{x}/{y}.mvt'],
          'minzoom': 0,
          'maxzoom': 14,
        },
      },
      'layers': [
        {
          'id': 'bg',
          'type': 'background',
          'paint': {'background-color': '#e8e8e8'},
        },
        {
          'id': 'probe',
          'type': 'fill',
          'source': 'staging',
          'source-layer': 'landuse',
          'paint': {'fill-color': '#9ecb8f'},
        },
      ],
    });

Future<String> _writeStyle() async {
  final dir = await Directory.systemTemp.createTemp('mm_style');
  final f = File('${dir.path}/style.json');
  await f.writeAsString(_styleJson());
  return f.uri.toString(); // file:///...
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final styleUri = await _writeStyle();
  runApp(_StagingSessionApp(styleUri: styleUri));
}

class _StagingSessionApp extends StatelessWidget {
  const _StagingSessionApp({required this.styleUri});

  final String styleUri;

  @override
  Widget build(BuildContext context) {
    // Fail loudly rather than silently billing nothing. An empty key makes the
    // wiring a no-op, and a no-op looks exactly like the bug under test.
    if (_apiKey.isEmpty) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'MM_API_KEY was not passed.\n'
              'Pass it with --dart-define=MM_API_KEY=...',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return MaterialApp(
      home: Scaffold(
        // RACE PROBE: hold the map back so the session create can finish first.
        body: _delayed(MapLibreMap(
          options: MapOptions(
            apiKey: _apiKey,
            initStyle: styleUri,
            initCenter: Position(_lng, _lat),
            initZoom: 12,
          ),
        )),
      ),
    );
  }

  /// Renders `child` only after MM_DELAY_MS, so the eager session create has
  /// time to land before the first style/tile request goes out.
  Widget _delayed(Widget child) {
    const ms = int.fromEnvironment('MM_DELAY_MS', defaultValue: 0);
    if (ms == 0) return child;
    return FutureBuilder<void>(
      future: Future<void>.delayed(const Duration(milliseconds: ms)),
      builder: (c, snap) => snap.connectionState == ConnectionState.done
          ? child
          : const Center(child: Text('waiting for session...')),
    );
  }
}
