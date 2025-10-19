import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart' as xml;

/// Converts MapLibre SDF XML sprite definition to MapLibre sprite JSON format
///
/// Usage: dart run example/lib/tools/convert_sdf_to_sprite.dart
///
/// Reads: example/assets/poi/symbols.sdf
/// Outputs: example/assets/poi/poi-sprite.json
void main() async {
  print('Converting SDF to MapLibre sprite JSON format...');

  // Paths
  final sdfPath = 'assets/poi/symbols.sdf';
  final outputPath = 'assets/poi/poi-sprite.json';

  try {
    // Read SDF file
    final sdfFile = File(sdfPath);
    if (!await sdfFile.exists()) {
      print('Error: SDF file not found at $sdfPath');
      exit(1);
    }

    final sdfContent = await sdfFile.readAsString();
    final sdfDocument = xml.XmlDocument.parse(sdfContent);

    // Parse sprite definitions
    final spriteJson = <String, Map<String, dynamic>>{};
    int iconCount = 0;

    for (final symbolElement in sdfDocument.findAllElements('symbol')) {
      final name = symbolElement.getAttribute('name');

      // Only process icons ending with '-m' (POI icons)
      if (name == null || !name.endsWith('-m')) continue;

      final minX = int.parse(symbolElement.getAttribute('minX') ?? '0');
      final minY = int.parse(symbolElement.getAttribute('minY') ?? '0');
      final maxX = int.parse(symbolElement.getAttribute('maxX') ?? '0');
      final maxY = int.parse(symbolElement.getAttribute('maxY') ?? '0');

      final width = maxX - minX;
      final height = maxY - minY;

      if (width <= 0 || height <= 0) {
        print('Warning: Skipping $name - invalid dimensions');
        continue;
      }

      // MapLibre sprite JSON format
      spriteJson[name] = {
        'x': minX,
        'y': minY,
        'width': width,
        'height': height,
        'pixelRatio': 1,
      };

      iconCount++;
    }

    // Write output JSON
    final outputFile = File(outputPath);
    await outputFile.writeAsString(
      JsonEncoder.withIndent('  ').convert(spriteJson),
    );

    print('✅ Successfully converted $iconCount icons');
    print('📄 Output written to: $outputPath');
    print('');
    print('Next steps:');
    print('1. Copy or rename assets/poi/symbols.png → assets/poi/poi-sprite.png');
    print('2. Update pubspec.yaml to include poi-sprite.json and poi-sprite.png');
    print('3. Modify poi_demo_page.dart to use native sprite loading');

  } catch (e, stack) {
    print('Error converting SDF to sprite JSON: $e');
    print('Stack trace: $stack');
    exit(1);
  }
}
