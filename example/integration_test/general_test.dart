import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapmetrics/mapmetrics.dart';

import 'app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('General', () {
    testWidgets('render map with tlhc_vd', (tester) async {
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();
      expect(tester.allWidgets.any((w) => w is MapLibreMap), isTrue);
    });

    testWidgets('render map with tlhc_hc', (tester) async {
      await tester.pumpWidget(
        App(
          options: MapOptions(
            initCenter: Position(0, 0),
            androidMode: AndroidPlatformViewMode.tlhc_hc,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.allWidgets.any((w) => w is MapLibreMap), isTrue);
    });

    /*testWidgets('render map with hc', (tester) async {
      await tester.pumpWidget(
        App(
          options: MapOptions(
            initCenter: Position(0, 0),
            androidMode: AndroidPlatformViewMode.hc,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.allWidgets.any((w) => w is MapLibreMap), isTrue);
    });

    testWidgets('render map with vd', (tester) async {
      await tester.pumpWidget(
        App(
          options: MapOptions(
            initCenter: Position(0, 0),
            androidMode: AndroidPlatformViewMode.vd,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.allWidgets.any((w) => w is MapLibreMap), isTrue);
    });*/

    testWidgets('update map options', (tester) async {
      final o1 = MapOptions(initCenter: Position(0, 0));
      await tester.pumpWidget(App(options: o1));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(tester.allWidgets.any((w) => w is MapLibreMap), isTrue);

      final o2 = MapOptions(initCenter: Position(0, 0), maxPitch: 0);
      await tester.pumpWidget(App(options: o2));
      await tester.pump();
    });
  });
}
