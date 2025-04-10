import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_example/map_styles.dart';
import 'package:mapmetrics/mapmetrics.dart';

import 'app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('MapOptions', () {
    testWidgets('get from map', (tester) async {
      final options = MapOptions(
        minZoom: 1,
        maxZoom: 2,
        initZoom: 1,
        initCenter: Position(1, 2),
        initStyle: MapStyles.protomapsLight,
      );
      final completer = Completer<MapController>();
      await tester.pumpWidget(
        App(options: options, onMapCreated: completer.complete),
      );
      await tester.pumpAndSettle();
      final ctrl = await completer.future;
      final options2 = ctrl.options;
      expect(options2, equals(options));
      expect(options2.hashCode, equals(options.hashCode));
    });
  });
}
