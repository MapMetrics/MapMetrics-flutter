// FINDINGS (measured on staging, iPhone 17 Pro simulator, 2026-08-24)
//
// Measured on the UNIVERSAL (v1-shaped) tile endpoint, which is what every
// shipped style and SDK actually uses. Same app, same 7 tiles, same rendered
// map -- only the source of the API key differs:
//
//   key via MapOptions.apiKey     meter delta 8    7 tiles cached
//   key via Info.plist MLNApiKey  meter delta 1    7 tiles cached
//
// Both render. One costs 8x. With the key at launch the SDK merges its session
// signature onto the tile URL and the tiles are free, because the session was
// already billed at create. Via MapOptions the tiles go out carrying only the
// style's `?token=`, which is valid v1 auth -- so they succeed and bill one
// charge EACH, on top of the session that was also billed.
//
// Confirmed against the endpoint directly:
//   ?token=<JWT>            -> 200, meter +1   (v1: per request)
//   ?token=<JWT> &sig=...   -> 200, meter  0   (v2: rides the session)
//   no credential           -> 401, meter  0
//
// AN EARLIER VERSION OF THIS FILE TESTED /v2/tiles AND CONCLUDED THE MAP WENT
// BLANK. That was an artefact of the wrong path. /v2/tiles 401s without a
// signature, so an unsigned client looks broken there; on the real endpoint an
// unsigned client looks perfectly healthy and just costs more. The bug has no
// visible symptom at all -- which is exactly why the meter, not the screen, is
// the oracle here.
//
// ROOT CAUSE NOT ESTABLISHED. The suspect is ordering: the key is applied in
// MapLibreView's getOptions callback, milliseconds before the first request.
// The MM_DELAY_MS probe below CANNOT test that -- delaying the map widget also
// delays the getOptions callback that sets the key, so both move together and
// the race window never changes. Do not read its result as evidence.
//
// Testing it properly needs the key set from Dart BEFORE any map view exists,
// for which the plugin exposes no API today. That, or having MMMapSession hold
// gateway requests until the session resolves, is the next step.
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

/// The UNIVERSAL (v1-shaped) tile endpoint -- the path every shipped style and
/// SDK actually uses. It accepts either credential format on the same URL:
/// `?token=<JWT>` bills v1 (one charge per request), and a merged `&sig=...`
/// bills v2 (zero, because the session was already charged at create).
///
/// Testing against /v2/tiles instead was misleading: that path 401s without a
/// signature, so an unsigned client looks BROKEN. Here an unsigned client looks
/// FINE and simply costs more -- which is the real-world failure mode, and the
/// reason the meter is the only honest oracle.
const _planet = String.fromEnvironment('MM_PLANET', defaultValue: 'planet20251013');

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
          'tiles': ['$_gateway/$_planet/{z}/{x}/{y}.mvt?token=$_apiKey'],
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
