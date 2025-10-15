import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Represents metadata for a single sprite in the sprite sheet
class SpriteMetadata {
  const SpriteMetadata({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String name;
  final int x;
  final int y;
  final int width;
  final int height;

  bool get isValid => width > 0 && height > 0;
}

/// Service to load and process sprite sheets
/// Based on the JavaScript POIRenderer sprite processing logic
class SpriteSheetLoader {
  /// Load sprite sheet image from URL
  static Future<ui.Image> loadSpriteSheet(String url) async {
    try {
      debugPrint('Loading sprite sheet from: $url');
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception('Failed to load sprite sheet: ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      debugPrint('Sprite sheet loaded: ${frame.image.width}x${frame.image.height}');
      return frame.image;
    } catch (e) {
      debugPrint('Error loading sprite sheet: $e');
      rethrow;
    }
  }

  /// Load sprite sheet image from local asset
  static Future<ui.Image> loadSpriteSheetFromAsset(String assetPath) async {
    try {
      debugPrint('Loading sprite sheet from asset: $assetPath');
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      debugPrint('Sprite sheet loaded: ${frame.image.width}x${frame.image.height}');
      return frame.image;
    } catch (e) {
      debugPrint('Error loading sprite sheet from asset: $e');
      rethrow;
    }
  }

  /// Load and parse SDF (Sprite Definition File) in XML format
  /// This matches the JavaScript loadSDF() function
  static Future<Map<String, SpriteMetadata>> loadSDF(String url) async {
    try {
      debugPrint('Loading SDF from: $url');
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception('Failed to load SDF: ${response.statusCode}');
      }

      final xmlString = response.body;
      return parseSDF(xmlString);
    } catch (e) {
      debugPrint('Error loading SDF: $e');
      rethrow;
    }
  }

  /// Load and parse SDF from local asset
  static Future<Map<String, SpriteMetadata>> loadSDFFromAsset(String assetPath) async {
    try {
      debugPrint('Loading SDF from asset: $assetPath');
      final xmlString = await rootBundle.loadString(assetPath);
      return parseSDF(xmlString);
    } catch (e) {
      debugPrint('Error loading SDF from asset: $e');
      rethrow;
    }
  }

  /// Parse SDF XML to extract sprite metadata
  /// Format: <symbol name="icon-name" minX="0" minY="0" maxX="32" maxY="32"/>
  static Map<String, SpriteMetadata> parseSDF(String xmlString) {
    final document = XmlDocument.parse(xmlString);
    final symbols = document.findAllElements('symbol');

    final metadata = <String, SpriteMetadata>{};

    for (final symbol in symbols) {
      final name = symbol.getAttribute('name');
      final minX = symbol.getAttribute('minX');
      final minY = symbol.getAttribute('minY');
      final maxX = symbol.getAttribute('maxX');
      final maxY = symbol.getAttribute('maxY');

      if (name != null && minX != null && minY != null && maxX != null && maxY != null) {
        final x = int.tryParse(minX) ?? 0;
        final y = int.tryParse(minY) ?? 0;
        final width = (int.tryParse(maxX) ?? 0) - x;
        final height = (int.tryParse(maxY) ?? 0) - y;

        metadata[name] = SpriteMetadata(
          name: name,
          x: x,
          y: y,
          width: width,
          height: height,
        );
      }
    }

    debugPrint('Parsed ${metadata.length} sprites from SDF');
    return metadata;
  }

  /// Extract a single sprite from the sprite sheet
  /// This matches the JavaScript processSpriteSheet() canvas extraction logic
  /// JavaScript typically encodes sprites as PNG blobs via canvas.toBlob()
  /// We match this by encoding as PNG, which MapLibre's addImage accepts
  static Future<Uint8List> extractSprite(
    ui.Image spriteSheet,
    SpriteMetadata sprite,
  ) async {
    // Create a picture recorder to draw the sprite
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
    );

    // Extract the sprite region from the sheet
    final srcRect = ui.Rect.fromLTWH(
      sprite.x.toDouble(),
      sprite.y.toDouble(),
      sprite.width.toDouble(),
      sprite.height.toDouble(),
    );

    final dstRect = ui.Rect.fromLTWH(
      0,
      0,
      sprite.width.toDouble(),
      sprite.height.toDouble(),
    );

    canvas.drawImageRect(spriteSheet, srcRect, dstRect, ui.Paint());

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(sprite.width, sprite.height);

    // Convert to PNG bytes to match JavaScript's canvas.toBlob('image/png')
    // MapLibre addImage accepts PNG-encoded image data
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Process entire sprite sheet and extract all sprites
  /// Returns a map of sprite name to image bytes
  /// This matches the JavaScript processSpriteSheet() function
  static Future<Map<String, Uint8List>> processSpriteSheet({
    required ui.Image spriteSheet,
    required Map<String, SpriteMetadata> metadata,
    required List<String> skipPatterns,
    required Function(int count, int total) onProgress,
  }) async {
    final sprites = <String, Uint8List>{};
    int processed = 0;
    final total = metadata.length;

    debugPrint('Processing $total sprites...');

    for (final entry in metadata.entries) {
      final name = entry.key;
      final sprite = entry.value;

      // Skip unwanted sprites (matches JavaScript skip logic)
      bool shouldSkip = false;
      for (final pattern in skipPatterns) {
        if (name.startsWith(pattern)) {
          shouldSkip = true;
          break;
        }
      }

      if (shouldSkip) {
        debugPrint('Skipping sprite: $name');
        continue;
      }

      // Skip invalid sprites
      if (!sprite.isValid) {
        debugPrint('Skipping invalid sprite: $name (${sprite.width}x${sprite.height})');
        continue;
      }

      try {
        // Extract sprite
        final bytes = await extractSprite(spriteSheet, sprite);
        sprites[name] = bytes;

        // Also add without -m suffix for easier matching (matches JavaScript)
        if (name.endsWith('-m')) {
          final simpleName = name.substring(0, name.length - 2);
          sprites[simpleName] = bytes;
        }

        processed++;
        onProgress(processed, total);
      } catch (e) {
        debugPrint('Error extracting sprite $name: $e');
      }
    }

    debugPrint('Extracted $processed sprites from sheet');
    return sprites;
  }

  /// Load sprite sheet JSON metadata (alternative to SDF XML)
  /// Format: {"icon-name": {"x": 0, "y": 0, "width": 32, "height": 32}}
  static Future<Map<String, SpriteMetadata>> loadSpriteJson(String url) async {
    try {
      debugPrint('Loading sprite JSON from: $url');
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception('Failed to load sprite JSON: ${response.statusCode}');
      }

      // Note: In a real implementation, you would parse the JSON here
      // The format varies, so this is a placeholder
      // Example: {"restaurant-m": {"x": 0, "y": 0, "width": 32, "height": 32, "pixelRatio": 1}}

      debugPrint('Sprite JSON loaded successfully');
      return {};
    } catch (e) {
      debugPrint('Error loading sprite JSON: $e');
      rethrow;
    }
  }
}
