// A throwaway entrypoint that exists to answer ONE question: when a Flutter app
// passes MapOptions.apiKey on iOS, does the native SDK open exactly one v2 map
// session against the gateway?
//
// Run it against staging, not production:
//
//   flutter run -t lib/staging_session_main.dart -d <simulator> \
//     --dart-define=MM_API_KEY="$(python3 -c "import json;print(json.load(open(
//       '../../devprog2/gatewayMapAtlas/gateway-mapatlas/staging-creds.json'
//     ))['mapsApiKey'])")"
//
// The key is passed by --dart-define rather than written here, because
// staging-creds.json is gitignored and its contents must not enter the repo.
//
// The gateway ORIGIN is not set here: it comes from MLNTileServerBaseURL in
// example/ios/Runner/Info.plist. MMMapSession needs both halves -- key and
// pinned origin -- before it will create anything, so changing only one of the
// two produces a silent no-op rather than an error.
//
// The style deliberately stays the MapLibre demo style. Session creation is
// EAGER: it fires when the key lands, before any style or tile request. Using a
// gateway-hosted style would conflate "the key reached MLNSettings" with "the
// style loaded", and the style manager 403s on staging anyway because it reads
// production API_KEYS. Tile signing against staging is already covered by
// MMMapViewSessionTests in the native SDK; this checks the Flutter wiring only.
import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

const _apiKey = String.fromEnvironment('MM_API_KEY');

void main() {
  runApp(const _StagingSessionApp());
}

class _StagingSessionApp extends StatelessWidget {
  const _StagingSessionApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        // Fail loudly rather than silently billing nothing. An empty key makes
        // the wiring a no-op, and a no-op would otherwise look exactly like the
        // bug this entrypoint was written to detect.
        body: _apiKey.isEmpty
            ? const Center(
                child: Text(
                  'MM_API_KEY was not passed.\n'
                  'Pass it with --dart-define=MM_API_KEY=...',
                  textAlign: TextAlign.center,
                ),
              )
            : const MapLibreMap(
                options: MapOptions(
                  apiKey: _apiKey,
                  initZoom: 3,
                ),
              ),
      ),
    );
  }
}
