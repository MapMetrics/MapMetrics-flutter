# MapMetrics for Flutter

Vector maps for Flutter on Android, iOS and web, backed by the MapMetrics
Atlas gateway. Wraps the MapMetrics native SDKs, which are a fork of MapLibre
Native with v2 map-session billing.

> This file was empty until 2026-08-26, including in every release published
> to pub.dev up to 1.0.6.

## Quick start

Add the dependency, then show a map. **This works with no API key**:

```dart
import 'package:mapmetrics/mapmetrics.dart';

MapLibreMap(
  options: MapOptions(
    initCenter: Position(4.89, 52.37),
    initZoom: 12,
  ),
)
```

With no `initStyle`, you get the **demo style** — no credential required. It
is rate-limited, capped at zoom 12 and watermarked, which makes it right for
"does my setup work" and wrong for anything you ship.

## Using your own style and key

```dart
MapOptions(
  apiKey: const String.fromEnvironment('MAPMETRICS_API_KEY'),
  initStyle: 'https://gateway.mapmetrics-atlas.net/styles/'
      '?fileName=YOUR_ACCOUNT_ID/mapstyle.json&token=YOUR_API_KEY',
)
```

Get a key at https://mapatlas.eu. **Pass it via `--dart-define`, never commit
it** — keys in this repository's own examples leaked into published archives
more than once, which is why the examples now use the keyless demo style.

`apiKey` is what opens a v2 map session: one charge per map load rather than
one per tile. Without it every tile bills separately, with no visible symptom
— the map renders correctly either way.

## Where the style is configured

Changing the style is a one-line edit in one of these places, depending on
what you want to affect:

| Scope | File | What to change |
|---|---|---|
| **Every consumer** who sets no style | `lib/src/map_options.dart:27` | the `initStyle` default (also update the doc comment at `:58`) |
| **All example pages** | `example/lib/map_styles.dart:32` | `MapStyles.demo` |
| One example page | that page's `initStyle:` | — |

29 of the 34 example pages set no style at all, so they follow the default;
`kiosk_page`, `styled_map_page` and `poi_demo_page` set one explicitly, and
`offline_page` deliberately uses a third-party style because bulk region
downloads are exactly what the demo endpoint's rate limit and zoom cap exist
to refuse.

For the native apps the equivalent constants are
`MAPMETRICS_DEMO_STYLE` (`platform/ios/app-swift/Sources/Styles.swift`) and
`MAPMETRICS_DEMO` (`…/testapp/styles/TestStyles.kt`) in the
mapmetrics-native-sdk repository.

## Platform support

| Platform | Status |
|---|---|
| Android | Supported — `org.mapmetrics.android-sdk:mapmetrics-native-sdk` |
| iOS | Supported — `MapMetrics-SDK` via CocoaPods or SPM |
| Web | **Declared but does not compile.** `flutter build web` fails with 537 errors in `lib/src/platform/maplibre_ffi.dart`: `dart:ffi` structs use `external` fields, which the web compiler rejects. Pre-existing; do not rely on web until it is fixed. |

Android requires `minSdk 24`. That floor comes from the native SDK's own AAR
and is declared per module, so every artefact carries it — picking a different
renderer artefact does not lower it.

## Renderers (Android)

The default artefact is the **OpenGL ES** build. Vulkan renders correctly on
real hardware but fails on emulators, which have no Vulkan driver behind
gfxstream, and the Vulkan artefact declares
`uses-feature android.hardware.vulkan.version required="true"` — which merges
into your app and makes Google Play hide it from every device without Vulkan.

To opt into Vulkan, depend on `mapmetrics-native-sdk-vulkan` directly.

## Running the example

```bash
cd example
flutter run                       # demo style, no key needed
```

To exercise session billing against staging, see
`example/lib/staging_session_main.dart`, which documents the `--dart-define`
flags and requires a staging key.
