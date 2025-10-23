import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mapmetrics/mapmetrics.dart';

@immutable
class PoiDemoPage extends StatefulWidget {
  const PoiDemoPage({super.key});

  static const String route = '/poi-demo';

  @override
  State<PoiDemoPage> createState() => _PoiDemoPageState();
}

class _PoiDemoPageState extends State<PoiDemoPage> {
  late final MapController _mapController;
  late final StyleController _styleController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('POI Demo')),
      body: MapLibreMap(
        options: MapOptions(
          initCenter: Position(4.89, 52.37), // Amsterdam
          initZoom: 14,
          initStyle: 'https://gateway.mapmetrics-atlas.net/styles/?fileName=dd508822-9502-4ab5-bfe2-5e6ed5809c2d/portal.json&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJkZDUwODgyMi05NTAyLTRhYjUtYmZlMi01ZTZlZDU4MDljMmQiLCJzY29wZSI6WyJtYXBzIiwiYXV0b2NvbXBsZXRlIiwiZ2VvY29kZSIsImRpcmVjdGlvbnMiLCJtYXBfbWF0Y2hpbmciLCJvcHRpbWl6ZSIsIm1hdHJpeCIsImlzb2Nocm9uZSJdLCJpYXQiOjE3NjExNDQ1OTl9.MbfXeBtRpzzaLgcdTE0xzMa-OEemCWNWprEbs1RO2rI',
              //'https://gateway.mapmetrics-atlas.net/styles/?fileName=7c3625ac-1f52-479e-8e6f-12299aae7e87/moon.json&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI3YzM2MjVhYy0xZjUyLTQ3OWUtOGU2Zi0xMjI5OWFhZTdlODciLCJzY29wZSI6WyJtYXBzIl0sImlhdCI6MTc2MDM0MTcwOX0.SKiNhdhqkq0FwzM4tn2Txmajw2YAJth6MQfYkAYPp_E',
        ),
        onMapCreated: (controller) {
          _mapController = controller;
        },
        onStyleLoaded: (styleController) async {
          _styleController = styleController;
          print('Style loaded');
          await _setupPoiLayer();
        },
        onEvent: (event) {
          if (event is MapEventLongClick) {
            _handleLongPress(event.point);
          }
        },
      ),
    );
  }

  /// Build icon-image expression from poi-mapping.json
  /// Generates a comprehensive expression that handles all ~400 POI mappings
  Future<Object> _buildIconImageExpression() async {
    try {
      // FIXED: Using nested case statements instead of coalesce to avoid evaluation issues
      final mappingJson = await rootBundle.loadString(
        'assets/poi/poi-mapping.json',
      );
      final mapping = jsonDecode(mappingJson) as Map<String, dynamic>;
      final mappings = mapping['mappings'] as Map<String, dynamic>;
      final fallback = mapping['fallbackSprite'] as String? ?? 'tourism-m';

      // Build nested case expressions - check each category in sequence
      // This avoids the coalesce evaluation issues with MapLibre
      Object expression = fallback; // Start with the final fallback

      // Process categories in reverse order so we can build nested structure
      final categories = mappings.keys.toList().reversed;

      // Debug: Track which categories are processed
      print('   Processing categories in order: ${categories.join(", ")}');

      for (final category in categories) {
        final categoryMappings = mappings[category];

        if (categoryMappings is Map) {
          // Build match cases for this category
          final matchCases = <dynamic>[];

          // Debug logging for each category
          print('   Processing $category category with ${categoryMappings.length} mappings');

          for (final entry in categoryMappings.entries) {
            final key = entry.key;
            if (key == 'default') continue; // Skip default entries for now

            final value = entry.value;
            if (value is String) {
              // Simple mapping: key → iconName
              matchCases.add(key);
              matchCases.add(value);

              // Debug: Show specific mappings for leisure
              if (category == 'leisure' && key == 'garden') {
                print('     Added garden → $value mapping to leisure category');
              }
            } else if (value is Map) {
              // Nested mapping (e.g., place_of_worship with religion)
              // For now, use the default value
              if (value['default'] != null) {
                matchCases.add(key);
                matchCases.add(value['default']);
              }
            }
          }

          if (matchCases.isNotEmpty) {
            // Get the default icon for this category
            final categoryDefault = categoryMappings['default'] ?? 'tourism-m';

            // Build nested case: if has this category, check match, else check next
            expression = [
              'case',
              ['has', category],
              [
                'match',
                ['get', category],
                ...matchCases,
                categoryDefault, // Use category default for unmapped values
              ],
              expression, // Previous expression (next category check or fallback)
            ];

            // Debug: Show expression structure for leisure
            if (category == 'leisure') {
              print('     Leisure expression built with ${matchCases.length ~/ 2} mappings');
              print('     Default icon for unmapped leisure: $categoryDefault');
            }
          }
        }
      }

      print(
        '✅ Built nested case expression for POI icons',
      );
      print('   Processing ${mappings.keys.length} categories without coalesce');

      // Debug: Print the expression structure for verification
      void printExpressionStructure(Object expr, int depth) {
        final indent = '  ' * depth;
        if (expr is List) {
          if (expr.isNotEmpty && expr[0] == 'case') {
            // It's a case statement
            print('$indent[case]');
            if (expr.length > 1 && expr[1] is List) {
              print('$indent  Condition: ${expr[1]}');
            }
            if (expr.length > 2 && expr[2] is List) {
              final trueExpr = expr[2] as List;
              if (trueExpr.isNotEmpty && trueExpr[0] == 'match') {
                print('$indent  If true → [match] on ${trueExpr[1]}');
                // Count mappings in match expression
                if (trueExpr.length > 2) {
                  final numMappings = (trueExpr.length - 3) ~/ 2; // Subtract match, get, and default
                  print('$indent    with $numMappings mappings + default');
                }
              }
            }
            if (expr.length > 3) {
              print('$indent  If false → continue to next:');
              printExpressionStructure(expr[3], depth + 1);
            }
          }
        } else if (expr is String) {
          print('$indent→ Final fallback: "$expr"');
        }
      }

      // Print the structure (only first 3 levels to avoid too much output)
      print('\n   Expression structure (nested case statements):');
      printExpressionStructure(expression, 2);

      // Verify leisure is included
      void verifyLeisureInExpression(Object expr) {
        if (expr is List) {
          for (var i = 0; i < expr.length; i++) {
            final item = expr[i];
            if (item is List && item.length > 1) {
              if (item[0] == 'has' && item[1] == 'leisure') {
                print('\n   ✅ Verified: leisure category IS included in expression');
                return;
              }
            }
            if (item is Object) {
              verifyLeisureInExpression(item);
            }
          }
        }
      }
      verifyLeisureInExpression(expression);

      return expression;
    } catch (e) {
      print('Error building icon expression: $e');
      // Return simple fallback expression
      return [
        'coalesce',
        [
          'image',
          [
            'concat',
            [
              'coalesce',
              ['get', 'amenity'],
              '',
            ],
            '-m',
          ],
        ],
        [
          'image',
          [
            'concat',
            'shop-',
            [
              'coalesce',
              ['get', 'shop'],
              '',
            ],
            '-m',
          ],
        ],
        [
          'image',
          [
            'concat',
            [
              'coalesce',
              ['get', 'tourism'],
              '',
            ],
            '-m',
          ],
        ],
        'tourism-m',
      ];
    }
  }

  Future<void> _setupPoiLayer() async {
    try {
      print('Setting up POI layer...');

      // Load actual icons from the sprite sheet using SDF coordinates
      print('Loading POI icons from sprite sheet...');

      await _loadIconsFromSprite();

      print('About to add vector source');
      // Add vector tile source for POIs
      // maxZoom: 16 because tiles are only available up to zoom 16
      // The layer can still render at higher zooms (overzooming)
      await _styleController.addSource(
        const VectorSource(
          id: 'poi-source',
          tiles: [
            'https://poi-tile-server-development.jim9710.workers.dev/tiles/{z}/{x}/{y}.mvt',
          ],
          minZoom: 16,
          maxZoom: 16, // Tiles available up to zoom 16, will overzoom beyond
        ),
      );
      print('POI vector source added successfully');

      // Wait a bit to ensure all base map layers are loaded
      await Future.delayed(const Duration(milliseconds: 500));

      // Add dot symbol layer with spacing (using dot-m icon)
      print('About to add POI dots layer');
      await _styleController.addLayer(
        SymbolStyleLayer(
          id: 'poi-circles',
          sourceId: 'poi-source',
          minZoom: 8,
          maxZoom: 24,
          filter: [
            '!=',
            ['get', 'man_made'],
            'surveillance',
          ],
          layout: {
            'source-layer': 'pois',
            'icon-image': 'dot-m',
            'icon-size': [
              'interpolate',
              ['linear'],
              ['zoom'],
              8,
              1.2,  // Half of previous size
              10,
              1.6,
              12,
              2.0,
              14,
              2.4,
              16,
              2.8,
              18,
              3.2,
              20,
              3.6,
              24,
              4.0,
            ],
            'icon-allow-overlap': false,  // Allow collision detection for spacing
            'icon-ignore-placement': false,
            'icon-padding': [
              'interpolate',
              ['linear'],
              ['zoom'],
              8, 10,   // More padding at low zoom for spacing
              12, 8,
              16, 5,
              20, 2,
            ],
          },
          paint: {
            'icon-color': '#FF0000',  // Recolor to red
            'icon-opacity': 0.6,
          },
        ),
      );
      print('POI dots layer added successfully');

      // Then add symbol layer on top with dynamic icon based on POI properties
      print('About to add POI symbol layer with dynamic icons');

      // Build icon expression from poi-mapping.json (handles all ~268 mappings)
      final iconImageExpression = await _buildIconImageExpression();
      // Icon size adjusted for visibility with circles
      final iconSize = Platform.isAndroid ? 2.0 : 0.5;  // Reasonable size with circles
      print(
        'Setting icon size to $iconSize for ${Platform.isAndroid ? "Android" : "iOS"}',
      );
      // Layer 1: Airports (zoom 10+)
      await _styleController.addLayer(
        SymbolStyleLayer(
          id: 'poi-airports',
          sourceId: 'poi-source',
          minZoom: 10,
          maxZoom: 24,
          filter: [
            '!=',
            ['get', 'man_made'],
            'surveillance',
          ],
          layout: {
            'source-layer': 'pois',
            'icon-image': iconImageExpression,
            'icon-size': iconSize,
            'icon-allow-overlap': false,
            'icon-ignore-placement': false,
            'icon-padding': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10, 40,  // Increased padding for more spacing
              16, 25,
              18, 20,
              20, 20
            ],
            'text-field': [
              'case',
              ['==', ['get', 'amenity'], 'bench'], '',
              ['==', ['get', 'leisure'], 'park'], '',
              ['==', ['get', 'amenity'], 'recycling'], '',
              ['==', ['get', 'amenity'], 'waste_basket'], '',
              ['==', ['get', 'amenity'], 'vending_machine'], '',
              ['==', ['get', 'amenity'], 'waste_disposal'], '',
              ['==', ['get', 'tourism'], 'artwork'], '',
              ['==', ['get', 'amenity'], 'parking_entrance'], '',
              ['==', ['get', 'amenity'], 'bicycle_parking'], '',
              ['==', ['get', 'amenity'], 'taxi'], '',
              ['==', ['get', 'amenity'], 'drinking_water'], '',
              [
                'coalesce',
                ['get', 'name'],
                ['get', 'aeroway'],
                '',
              ],
            ],
            'text-font': ['Montserrat Bold'],
            'text-size': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10, 8,
              16, 9,
              18, 11,
              20, 13,
              22, 14
            ],
            'text-anchor': 'left',
            'text-offset': [1.5, 0],
            'text-allow-overlap': true,
            'text-optional': true,
          },
          paint: {
            'icon-opacity': [
              'step',
              ['zoom'],
              0,    // invisible below zoom 10
              10, 1,  // visible at zoom 10+
            ],
            'text-opacity': [
              'step',
              ['zoom'],
              0,
              10, 1,
            ],
            'text-color': [
              'case',
              ['has', 'amenity'], '#FFD700',  // Gold/yellow for amenity
              ['has', 'leisure'], '#00B050',   // Green for leisure
              ['has', 'tourism'], '#FF6B6B',   // Red for tourism
              ['has', 'shop'], '#4A90E2',      // Blue for shop
              ['has', 'aeroway'], '#9B59B6',   // Purple for aeroway
              '#000000',  // Default black
            ],
            'text-halo-color': '#FFFFFF',
            'text-halo-width': 2,
          },
        ),
      );

      // Layer 2: Priority POIs (zoom 12+)
      await _styleController.addLayer(
        SymbolStyleLayer(
          id: 'poi-priority',
          sourceId: 'poi-source',
          minZoom: 12,
          maxZoom: 24,
          filter: [
            '!=',
            ['get', 'man_made'],
            'surveillance',
          ],
          layout: {
            'source-layer': 'pois',
            'icon-image': iconImageExpression,
            'icon-size': iconSize,
            'icon-allow-overlap': false,
            'icon-ignore-placement': false,
            'icon-padding': [
              'interpolate',
              ['linear'],
              ['zoom'],
              12, 35,  // Increased padding for more spacing
              16, 25,
              18, 15,
              20, 10
            ],
            'text-field': [
              'case',
              ['==', ['get', 'amenity'], 'bench'], '',
              ['==', ['get', 'leisure'], 'park'], '',
              ['==', ['get', 'amenity'], 'recycling'], '',
              ['==', ['get', 'amenity'], 'waste_basket'], '',
              ['==', ['get', 'amenity'], 'vending_machine'], '',
              ['==', ['get', 'amenity'], 'waste_disposal'], '',
              ['==', ['get', 'tourism'], 'artwork'], '',
              ['==', ['get', 'amenity'], 'parking_entrance'], '',
              ['==', ['get', 'amenity'], 'bicycle_parking'], '',
              ['==', ['get', 'amenity'], 'taxi'], '',
              ['==', ['get', 'amenity'], 'drinking_water'], '',
              [
                'coalesce',
                ['get', 'name'],
                ['get', 'amenity'],
                ['get', 'leisure'],
                ['get', 'tourism'],
                '',
              ],
            ],
            'text-font': ['Montserrat Bold'],
            'text-size': [
              'interpolate',
              ['linear'],
              ['zoom'],
              12, 8,
              16, 9,
              18, 11,
              20, 13,
              22, 14
            ],
            'text-anchor': 'left',
            'text-offset': [1.5, 0],
            'text-allow-overlap': true,
            'text-optional': true,
          },
          paint: {
            'icon-opacity': [
              'step',
              ['zoom'],
              0,    // invisible below zoom 12
              12, 1,  // visible at zoom 12+
            ],
            'text-opacity': [
              'step',
              ['zoom'],
              0,
              12, 1,
            ],
            'text-color': [
              'case',
              ['has', 'amenity'], '#FFD700',  // Gold/yellow for amenity
              ['has', 'leisure'], '#00B050',   // Green for leisure
              ['has', 'tourism'], '#FF6B6B',   // Red for tourism
              ['has', 'shop'], '#4A90E2',      // Blue for shop
              ['has', 'aeroway'], '#9B59B6',   // Purple for aeroway
              '#000000',  // Default black
            ],
            'text-halo-color': '#FFFFFF',
            'text-halo-width': 2,
          },
        ),
      );

      // Layer 3: All other POIs (zoom 16+)
      await _styleController.addLayer(
        SymbolStyleLayer(
          id: 'poi-all',
          sourceId: 'poi-source',
          minZoom: 16,
          maxZoom: 24,
          filter: [
            '!=',
            ['get', 'man_made'],
            'surveillance',
          ],
          layout: {
            'source-layer': 'pois',
            'icon-image': iconImageExpression,
            'icon-size': iconSize,
            'icon-allow-overlap': false,
            'icon-ignore-placement': false,
            'icon-padding': [
              'interpolate',
              ['linear'],
              ['zoom'],
              16, 25,  // Increased padding for more spacing
              18, 15,
              20, 10
            ],
            'text-field': [
              'case',
              ['==', ['get', 'amenity'], 'bench'], '',
              ['==', ['get', 'leisure'], 'park'], '',
              ['==', ['get', 'amenity'], 'recycling'], '',
              ['==', ['get', 'amenity'], 'waste_basket'], '',
              ['==', ['get', 'amenity'], 'vending_machine'], '',
              ['==', ['get', 'amenity'], 'waste_disposal'], '',
              ['==', ['get', 'tourism'], 'artwork'], '',
              ['==', ['get', 'amenity'], 'parking_entrance'], '',
              ['==', ['get', 'amenity'], 'bicycle_parking'], '',
              ['==', ['get', 'amenity'], 'taxi'], '',
              ['==', ['get', 'amenity'], 'drinking_water'], '',
              [
                'coalesce',
                ['get', 'name'],
                ['get', 'amenity'],
                ['get', 'shop'],
                ['get', 'tourism'],
                ['get', 'leisure'],
                '',
              ],
            ],
            'text-font': ['Montserrat Bold'],
            'text-size': [
              'interpolate',
              ['linear'],
              ['zoom'],
              16, 9,
              18, 11,
              20, 13,
              22, 14
            ],
            'text-anchor': 'left',
            'text-offset': [1.5, 0],
            'text-allow-overlap': true,
            'text-optional': true,
          },
          paint: {
            'icon-opacity': [
              'step',
              ['zoom'],
              0,    // invisible below zoom 16
              16, 1,  // visible at zoom 16+
            ],
            'text-opacity': [
              'step',
              ['zoom'],
              0,
              16, 1,
            ],
            'text-color': [
              'case',
              ['has', 'amenity'], '#E89914',  // Gold/yellow for amenity
              ['has', 'leisure'], '#3B863E',   // Green for leisure
              ['has', 'tourism'], '#195350',   // Red for tourism
              ['has', 'shop'], '#7C2889',      // Blue for shop
              ['has', 'aeroway'], '#1F4A77',   // Purple for aeroway
              '#323232',  // Default black
            ],
            'text-halo-color': '#FFFFFF',
            'text-halo-width': 2,
          },
        ),
      );
      print('POI layers added: Airports@10+, Priority@12+, All@16+');
    } catch (e, stack) {
      print('Error setting up POI layer: $e');
      print('Stack trace: $stack');
    }
  }

  // Extract a specific icon from the sprite sheet using SDF coordinates
  Future<Uint8List> _extractIconFromSprite(
    String spritePath,
    int minX,
    int minY,
    int maxX,
    int maxY,
  ) async {
    // Load the sprite sheet
    final ByteData data = await DefaultAssetBundle.of(context).load(spritePath);
    final Uint8List bytes = data.buffer.asUint8List();

    // Decode the sprite sheet image
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final spriteImage = frame.image;

    // Calculate icon dimensions
    final width = maxX - minX;
    final height = maxY - minY;

    // Create a canvas to draw the extracted icon
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw the specific region from the sprite sheet
    final srcRect = Rect.fromLTWH(
      minX.toDouble(),
      minY.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

    canvas.drawImageRect(spriteImage, srcRect, dstRect, Paint());

    // Convert to PNG bytes
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  // Create a restaurant icon (fork and knife symbol)
  Future<Uint8List> _createRestaurantIcon(int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint =
        Paint()
          ..color = Colors.red
          ..style = PaintingStyle.fill;

    final center = Offset(size / 2, size / 2);

    // Draw a circle background
    canvas.drawCircle(center, size / 2, paint);

    // Draw white border
    paint
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, size / 2 - 1.5, paint);

    // Draw fork and knife in white
    paint
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;

    // Draw simplified fork on left
    final forkPath = Path();
    final forkX = size * 0.35;
    final forkY = size * 0.3;
    forkPath.moveTo(forkX - 4, forkY);
    forkPath.lineTo(forkX - 4, forkY + size * 0.2);
    forkPath.lineTo(forkX - 2, forkY + size * 0.2);
    forkPath.lineTo(forkX - 2, forkY);
    forkPath.close();

    forkPath.moveTo(forkX + 2, forkY);
    forkPath.lineTo(forkX + 2, forkY + size * 0.2);
    forkPath.lineTo(forkX + 4, forkY + size * 0.2);
    forkPath.lineTo(forkX + 4, forkY);
    forkPath.close();

    // Fork handle
    forkPath.moveTo(forkX - 1.5, forkY + size * 0.15);
    forkPath.lineTo(forkX - 1.5, forkY + size * 0.4);
    forkPath.lineTo(forkX + 1.5, forkY + size * 0.4);
    forkPath.lineTo(forkX + 1.5, forkY + size * 0.15);
    forkPath.close();

    canvas.drawPath(forkPath, paint);

    // Draw simplified knife on right
    final knifePath = Path();
    final knifeX = size * 0.65;
    final knifeY = size * 0.3;

    // Knife blade
    knifePath.moveTo(knifeX - 2, knifeY);
    knifePath.lineTo(knifeX + 2, knifeY);
    knifePath.lineTo(knifeX + 1, knifeY + size * 0.15);
    knifePath.lineTo(knifeX - 1, knifeY + size * 0.15);
    knifePath.close();

    // Knife handle
    knifePath.moveTo(knifeX - 1.5, knifeY + size * 0.15);
    knifePath.lineTo(knifeX - 1.5, knifeY + size * 0.4);
    knifePath.lineTo(knifeX + 1.5, knifeY + size * 0.4);
    knifePath.lineTo(knifeX + 1.5, knifeY + size * 0.15);
    knifePath.close();

    canvas.drawPath(knifePath, paint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // Create a simple circle icon as bytes
  Future<Uint8List> _createCircleIcon(
    int size,
    Color fillColor,
    Color strokeColor,
    double strokeWidth,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint =
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill;

    final center = Offset(size / 2, size / 2);
    final radius = (size - strokeWidth) / 2;

    // Draw fill
    canvas.drawCircle(center, radius, paint);

    // Draw stroke
    paint
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, paint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // Create a fallback icon for unknown POI types
  Future<Uint8List> _createFallbackIcon(int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint =
        Paint()
          ..color = Colors.grey
          ..style = PaintingStyle.fill;

    final center = Offset(size / 2, size / 2);

    // Draw a simple marker pin shape
    canvas.drawCircle(center, size / 2, paint);

    // Draw white border
    paint
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, size / 2 - 1, paint);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _togglePoiLayer(bool visible) async {
    try {
      if (visible) {
        // Re-add both layers, source already exists
        // First add circles
        // await _styleController.addLayer(
        //   const CircleStyleLayer(
        //     id: 'poi-circles',
        //     sourceId: 'poi-source',
        //     minZoom: 8,
        //     maxZoom: 24,
        //     layout: {'source-layer': 'pois'},
        //     paint: {
        //       'circle-radius': [
        //         'interpolate',
        //         ['linear'],
        //         ['zoom'],
        //         8,
        //         3,
        //         10,
        //         4,
        //         12,
        //         5,
        //         14,
        //         6,
        //         16,
        //         7,
        //         18,
        //         8,
        //         20,
        //         9,
        //         24,
        //         12,
        //       ],
        //       'circle-color': '#FF0000',
        //       'circle-opacity': 0.3,
        //       'circle-stroke-width': 2,
        //       'circle-stroke-color': '#FFFFFF',
        //     },
        //   ),
        // );

        // Then add symbols on top with comprehensive icon mappings
        // Build icon expression from poi-mapping.json (handles all ~400 mappings)
        final iconImageExpression = await _buildIconImageExpression();

        // Platform-specific icon size: Android needs 2x the size of iOS
        final iconSize = Platform.isAndroid ? 1.2 : 0.6;

        await _styleController.addLayer(
          SymbolStyleLayer(
            id: 'poi-symbols',
            sourceId: 'poi-source',
            minZoom: 16,
            maxZoom: 24,
            filter: [
              'any',
              ['<', ['zoom'], 16],  // Show all POIs below zoom 16
              // Above zoom 16, only show important POIs
              ['in', ['get', 'amenity'], ['literal', ['hospital', 'police', 'fire_station', 'pharmacy', 'post_office', 'townhall', 'courthouse']]],
              ['in', ['get', 'tourism'], ['literal', ['hotel', 'museum', 'attraction']]],
              ['in', ['get', 'shop'], ['literal', ['supermarket', 'department_store']]],
            ],
            layout: {
              'source-layer': 'pois',
              // Icon expression built dynamically from poi-mapping.json
              'icon-image': iconImageExpression,
              'icon-size': iconSize,
              'icon-allow-overlap': false,
              'icon-ignore-placement': false,
              // Increase padding at higher zoom levels to reduce clutter
              // 'icon-padding': [
              //   'interpolate',
              //   ['linear'],
              //   ['zoom'],
              //   8, 0,     // 900px padding at zoom 8
              //   16, 0,    // 900px padding at zoom 16 (constant, filter kicks in)
              //   18, 0,     // 25px padding at zoom 18 (filter shows only important POIs)
              //   20, 0      // 25px padding at zoom 20 (minimal, filter active)
              // ],
            },
          ),
        );
        print('POI layers re-added with comprehensive icon mappings and zoom-based filtering');
      } else {
        // Remove both layers, keep the source
        // await _styleController.removeLayer('poi-circles');
        await _styleController.removeLayer('poi-symbols');
        print('POI layers removed');
      }
    } catch (e) {
      print('Error toggling POI layer: $e');
    }
  }

  Future<void> _handleLongPress(Position point) async {
    try {
      print('Long press detected at: ${point.lng}, ${point.lat}');

      // Convert the geographic position to screen coordinates
      final screenLocation = await _mapController.toScreenLocation(point);
      print('Screen location: ${screenLocation.dx}, ${screenLocation.dy}');

      // Query layers at that location - now returns maps with all properties
      final layers = await _mapController.queryLayers(screenLocation);
      print('Found ${layers.length} layers at location');

      // Filter for both POI circles and icon layers
      final poiFeatures =
          layers.where((feature) {
            final layerId = feature['layerId'];
            return layerId == 'poi-circles' ||
                   layerId == 'poi-airports' ||
                   layerId == 'poi-priority' ||
                   layerId == 'poi-all';
          }).toList();

      if (poiFeatures.isNotEmpty) {
        // Get the POI data from the circles layer
        final poiData = poiFeatures.first;

        print('POI detected!');
        print('Layer ID: ${poiData['layerId']}');
        print('Source ID: ${poiData['sourceId']}');
        print('Source Layer: ${poiData['sourceLayer']}');
        print('POI properties: $poiData');

        // Show POI information dialog with all properties
        if (mounted) {
          await _showPOIDialog(point, poiData);
        }
      } else {
        print('No POI found at this location');
      }
    } catch (e, stack) {
      print('Error handling long press: $e');
      print('Stack trace: $stack');
    }
  }

  Future<void> _showPOIDialog(
    Position point,
    Map<String, String> poiData,
  ) async {
    // Separate metadata properties from POI properties
    final metadataKeys = {'layerId', 'sourceId', 'sourceLayer'};
    final specialKeys = {
      'name',
      'amenity',
      'phone',
      'opening_hours',
      'cuisine',
      'website',
      'addr:street',
      'addr:housenumber',
      'addr:city',
    };

    // Get all POI properties (excluding metadata)
    final allProperties = <String, String>{};
    final specialProperties = <String, String>{};

    for (final entry in poiData.entries) {
      if (!metadataKeys.contains(entry.key) && entry.value.isNotEmpty) {
        if (specialKeys.contains(entry.key)) {
          specialProperties[entry.key] = entry.value;
        } else {
          allProperties[entry.key] = entry.value;
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(specialProperties['name'] ?? 'POI Information'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name (if different from title)
                    if (specialProperties['name'] != null) ...[
                      Text(
                        specialProperties['name']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Coordinates
                    const Text(
                      '📍 Coordinates:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Lat: ${point.lat.toStringAsFixed(6)}°'),
                    Text('Lng: ${point.lng.toStringAsFixed(6)}°'),

                    // Type/Category
                    if (specialProperties['amenity'] != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Type: ${specialProperties['amenity']}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],

                    // Contact Information
                    if (specialProperties['phone'] != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '📞 Contact:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(specialProperties['phone']!),
                    ],

                    if (specialProperties['website'] != null) ...[
                      const SizedBox(height: 4),
                      Text('🌐 ${specialProperties['website']}'),
                    ],

                    // Opening Hours
                    if (specialProperties['opening_hours'] != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '🕐 Opening Hours:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(specialProperties['opening_hours']!),
                    ],

                    // Cuisine
                    if (specialProperties['cuisine'] != null) ...[
                      const SizedBox(height: 12),
                      Text('🍽️ Cuisine: ${specialProperties['cuisine']}'),
                    ],

                    // Address
                    if (specialProperties['addr:street'] != null ||
                        specialProperties['addr:housenumber'] != null ||
                        specialProperties['addr:city'] != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '📫 Address:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (specialProperties['addr:housenumber'] != null &&
                          specialProperties['addr:street'] != null)
                        Text(
                          '${specialProperties['addr:housenumber']} ${specialProperties['addr:street']}',
                        ),
                      if (specialProperties['addr:city'] != null)
                        Text(specialProperties['addr:city']!),
                    ],

                    // All other POI properties
                    if (allProperties.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Additional Properties:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...allProperties.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${entry.key}:',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(flex: 3, child: Text(entry.value)),
                            ],
                          ),
                        );
                      }),
                    ],

                    // Layer Metadata (Debug Info)
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Layer Information:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Layer: ${poiData['layerId'] ?? "unknown"}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      'Source: ${poiData['sourceId'] ?? "unknown"}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    if (poiData['sourceLayer'] != null &&
                        poiData['sourceLayer']!.isNotEmpty)
                      Text(
                        'Source Layer: ${poiData['sourceLayer']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  /// Load POI icons from the sprite sheet using MapLibre sprite.json format
  ///
  /// This is a manual loading approach for compatibility with remote styles.
  /// For production use with full native sprite loading:
  /// 1. Add "sprite": "asset://assets/poi/poi-sprite" to your style JSON
  /// 2. Remove this manual loading function
  /// 3. MapLibre will load sprites automatically (10-20x faster)
  Future<void> _loadIconsFromSprite() async {
    try {
      // Load the MapLibre sprite.json (generated from symbols.sdf)
      final spriteJsonData = await rootBundle.loadString(
        'assets/poi/poi-sprite.json',
      );
      final spriteJson = jsonDecode(spriteJsonData) as Map<String, dynamic>;

      // Load the PNG sprite sheet
      final pngData = await rootBundle.load('assets/poi/poi-sprite.png');
      final pngBytes = pngData.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final spriteImage = frame.image;

      // Extract and load icons using sprite.json coordinates
      int loadedCount = 0;
      for (final entry in spriteJson.entries) {
        final name = entry.key;
        final iconData = entry.value as Map<String, dynamic>;

        final x = iconData['x'] as int;
        final y = iconData['y'] as int;
        final width = iconData['width'] as int;
        final height = iconData['height'] as int;

        if (width <= 0 || height <= 0) continue;

        // Extract icon from sprite sheet
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final srcRect = Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          width.toDouble(),
          height.toDouble(),
        );
        final dstRect = Rect.fromLTWH(
          0,
          0,
          width.toDouble(),
          height.toDouble(),
        );
        canvas.drawImageRect(spriteImage, srcRect, dstRect, Paint());

        final picture = recorder.endRecording();
        final iconImage = await picture.toImage(width, height);
        final byteData = await iconImage.toByteData(
          format: ui.ImageByteFormat.png,
        );

        if (byteData != null) {
          final iconBytes = byteData.buffer.asUint8List();
          await _styleController.addImage(name, iconBytes);
          loadedCount++;
        }
      }

      print('✅ Successfully loaded $loadedCount POI icons from sprite.json');
      print('ℹ️  Using manual loading for remote style compatibility');
      print(
        '💡 For native sprite loading: add "sprite": "asset://assets/poi/poi-sprite" to style JSON',
      );
    } catch (e, stack) {
      print('Error loading icons from sprite: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }
}
