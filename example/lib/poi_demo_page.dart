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
  MapController? _mapController;
  StyleController? _styleController;
  bool _isStyleLoaded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('POI Demo')),
      // MapMetricsView, not the raw MapLibreMap this page used to build.
      // MapMetricsView is MapLibreMap plus the MapMetrics logo overlay, so
      // using the inner widget directly made this the one page in the example
      // that rendered without MapMetrics attribution.
      body: MapMetricsView(
        options: MapOptions(
          initCenter: Position(4.89, 52.37), // Amsterdam
          initZoom: 14,
          // The unauthenticated demo style. NO CREDENTIAL -- that is the point.
          //
          // This line used to carry a production API key inline, and the one
          // before it a second. Both were non-expiring, and the first granted
          // the entire routing surface (directions, map_matching, optimize,
          // matrix, isochrone) to anyone who read the file. This repository is
          // public, so "anyone" was literal.
          //
          // An example has to load a map, and until the demo endpoint existed,
          // loading a map needed a key -- so a key got pasted in, twice. The
          // demo style removes the reason: it is rate-limited, capped at zoom
          // 12, watermarked, and there is nothing here to leak, rotate, or
          // revoke.
          //
          // If you are copying this file for real work, get your own key at
          // https://mapatlas.eu and pass it via --dart-define rather than
          // typing it into source.
          initStyle: 'https://gateway.mapmetrics-atlas.net/demo/style.json',
        ),
        onMapCreated: (controller) {
          _mapController = controller;
        },
        onStyleLoaded: (styleController) async {
          // Guard against multiple calls on iOS
          if (_isStyleLoaded) {
            print('Style already loaded, skipping duplicate callback');
            return;
          }
          _isStyleLoaded = true;
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
              printExpressionStructure(expr[3] as Object, depth + 1);
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

  /// POI tile server, supplied at build time. NOT COMMITTED, and empty by
  /// default.
  ///
  /// This used to be a hardcoded private hostname --
  /// poi-tile-server-development.jim9710.workers.dev -- shipped in a public
  /// example. It is a DEVELOPMENT worker: not ours to hand to customers, not
  /// guaranteed to exist, and it currently answers 204 with an empty body, so
  /// the POI layers below have been rendering nothing anyway.
  ///
  /// It cannot simply be repointed at the demo endpoint. The demo style caps
  /// at zoom 12 while this source starts at 16; the demo tiles use the
  /// Protomaps schema (`kind`) while these layers filter on raw OSM tags such
  /// as `man_made`; and the icons come from a sprite of ~268 mappings that the
  /// demo style's sprite does not contain. Repointing would compile cleanly
  /// and draw nothing, which is worse than not drawing at all.
  ///
  /// Run with your own POI tile server:
  ///
  ///   flutter run -t lib/main.dart \
  ///     --dart-define=POI_TILE_SERVER=https://your-host/tiles/{z}/{x}/{y}.mvt
  ///
  /// Unset, the page shows the demo basemap and skips the POI overlay.
  static const _poiTileServer = String.fromEnvironment(
    'POI_TILE_SERVER',
    defaultValue:
        'https://gateway.mapmetrics-atlas.net/v2/poi-tiles/{z}/{x}/{y}.mvt',
  );

  /// API key for the POI overlay, supplied at build time. NOT COMMITTED.
  ///
  /// /v2/poi-tiles authorises against a real key -- KV active check, per-scope
  /// revocation, origin lock, signature -- and then bills nothing. Authorised
  /// but free: the key is what makes traffic attributable and revocable, not
  /// what makes it chargeable, so POI tiles do not touch the customer's quota.
  ///
  ///   flutter run -t lib/main.dart --dart-define=MAPMETRICS_API_KEY=<jwt>
  ///
  /// Unset, the page shows the demo basemap and skips the POI overlay, exactly
  /// as it did when the tile server itself was unset. A key belongs on the
  /// command line or in a secret store, never in this file -- two were pasted
  /// into this repository before, and both are in a revocation queue now.
  static const _apiKey = String.fromEnvironment('MAPMETRICS_API_KEY');

  Future<void> _setupPoiLayer() async {
    try {
      print('Setting up POI layer...');

      if (_poiTileServer.isEmpty || _apiKey.isEmpty) {
        print(
          'MAPMETRICS_API_KEY is not set - showing the demo basemap without '
          'the POI overlay. Pass --dart-define=MAPMETRICS_API_KEY=<jwt> to '
          'enable it. POI tiles are authorised but never billed.',
        );
        return;
      }

      // Load actual icons from the sprite sheet using SDF coordinates
      print('Loading POI icons from sprite sheet...');

      await _loadIconsFromSprite();

      print('About to add vector source');
      // Add vector tile source for POIs
      // maxZoom: 16 because tiles are only available up to zoom 16
      // The layer can still render at higher zooms (overzooming)

      // ZOOM 10..14, NOT 16. The source claimed minZoom/maxZoom 16, which is
      // not what pois-v2-tileserver serves: its ROOT_ZOOM is 10 and MAX_ZOOM is
      // 14, and it answers 404 outside that. Asking for z16 fetched nothing but
      // 404s, so the overlay could not have drawn even with a valid key and a
      // reachable server. Below 14 the renderer overzooms z14 tiles, which is
      // what the page already relied on at higher zooms.
      await _styleController!.addSource(
        VectorSource(
          id: 'poi-source',
          tiles: ['$_poiTileServer?token=$_apiKey'],
          minZoom: 10,
          maxZoom: 14,
        ),
      );

      print('POI vector source added successfully');

      // Add dot symbol layer with spacing (using dot-m icon)
      print('About to add POI dots layer');
      // iOS needs quarter the icon size compared to Android
      final iosSizeMultiplier = Platform.isIOS ? 0.25 : 1.0;
      await _styleController!.addLayer(
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
              1.2 * iosSizeMultiplier,
              10,
              1.6 * iosSizeMultiplier,
              12,
              2.0 * iosSizeMultiplier,
              14,
              2.4 * iosSizeMultiplier,
              16,
              2.8 * iosSizeMultiplier,
              18,
              3.2 * iosSizeMultiplier,
              20,
              3.6 * iosSizeMultiplier,
              24,
              4.0 * iosSizeMultiplier,
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
      // // Layer 1: Airports (zoom 10+)
      // await _styleController!.addLayer(
      //   SymbolStyleLayer(
      //     id: 'poi-airports',
      //     sourceId: 'poi-source',
      //     minZoom: 10,
      //     maxZoom: 24,
      //     filter: [
      //       '!=',
      //       ['get', 'man_made'],
      //       'surveillance',
      //     ],
      //     layout: {
      //       'source-layer': 'pois',
      //       'icon-image': iconImageExpression,
      //       'icon-size': iconSize,
      //       'icon-allow-overlap': false,
      //       'icon-ignore-placement': false,
      //       'icon-padding': [
      //         'interpolate',
      //         ['linear'],
      //         ['zoom'],
      //         10, 40,  // Increased padding for more spacing
      //         16, 25,
      //         18, 20,
      //         20, 20
      //       ],
      //       'text-field': [
      //         'case',
      //         ['==', ['get', 'amenity'], 'bench'], '',
      //         ['==', ['get', 'leisure'], 'park'], '',
      //         ['==', ['get', 'amenity'], 'recycling'], '',
      //         ['==', ['get', 'amenity'], 'waste_basket'], '',
      //         ['==', ['get', 'amenity'], 'vending_machine'], '',
      //         ['==', ['get', 'amenity'], 'waste_disposal'], '',
      //         ['==', ['get', 'tourism'], 'artwork'], '',
      //         ['==', ['get', 'amenity'], 'parking_entrance'], '',
      //         ['==', ['get', 'amenity'], 'bicycle_parking'], '',
      //         ['==', ['get', 'amenity'], 'taxi'], '',
      //         ['==', ['get', 'amenity'], 'drinking_water'], '',
      //         [
      //           'coalesce',
      //           ['get', 'name'],
      //           ['get', 'aeroway'],
      //           '',
      //         ],
      //       ],
      //       'text-font': ['Montserrat Bold'],
      //       'text-size': [
      //         'interpolate',
      //         ['linear'],
      //         ['zoom'],
      //         10, 8,
      //         16, 9,
      //         18, 11,
      //         20, 13,
      //         22, 14
      //       ],
      //       'text-anchor': 'left',
      //       'text-offset': [1.5, 0],
      //       'text-allow-overlap': true,
      //       'text-optional': true,
      //     },
      //     paint: {
      //       'icon-opacity': [
      //         'step',
      //         ['zoom'],
      //         0,    // invisible below zoom 10
      //         10, 1,  // visible at zoom 10+
      //       ],
      //       'text-opacity': [
      //         'step',
      //         ['zoom'],
      //         0,
      //         10, 1,
      //       ],
      //       'text-color': [
      //         'case',
      //         ['has', 'aeroway'], '#9B59B6',   // Purple for aeroway,
      //         ['==', ['get', 'amenity'], 'restaurant'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'fast_food'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'cafe'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'bar'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'pub'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'bakery'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'ice_cream'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'hospital'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'clinic'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'pharmacy'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'dentist'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'veterinary'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'bank'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'atm'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'police'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'fire_station'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'post_office'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'school'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'kindergarten'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'college'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'university'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'library'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'theatre'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'cinema'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'nightclub'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'casino'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'fuel'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'parking'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'bicycle_parking'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'taxi'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'car_wash'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'car_sharing'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'charging_station'], '#00B050',
      //         ['==', ['get', 'amenity'], 'bicycle_rental'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'car_rental'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'motorcycle_parking'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'toilets'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'drinking_water'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'fountain'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'recycling'], '#717065',
      //         ['==', ['get', 'amenity'], 'waste_basket'], '#717065',
      //         ['==', ['get', 'amenity'], 'telephone'], '#717065',
      //         ['==', ['get', 'amenity'], 'marketplace'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'vending_machine'], '#707066',
      //         ['==', ['get', 'amenity'], 'bbq'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'bench'], '#717065',
      //         ['==', ['get', 'amenity'], 'shelter'], '#717065',
      //         ['==', ['get', 'amenity'], 'shower'], '#717065',
      //         ['==', ['get', 'amenity'], 'embassy'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'prison'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'courthouse'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'townhall'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'grave_yard'], '#717065',
      //         ['==', ['get', 'amenity'], 'crematorium'], '#717065',
      //         ['==', ['get', 'amenity'], 'place_of_worship'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'ferry_terminal'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'bus_station'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'trolleybus_station'], '#4A90E2',
      //         ['has', 'amenity'], '#6ABFBA',   // Teal for other amenity (fallback)
      //         ['==', ['get', 'shop'], 'supermarket'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'convenience'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'bakery'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'butcher'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'greengrocer'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'seafood'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'cheese'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'confectionery'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'ice_cream'], '#FFD700',
      //         ['==', ['get', 'shop'], 'alcohol'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'clothes'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'shoes'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'jewelry'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'gift'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'toys'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'books'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'stationery'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'electronics'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'mobile_phone'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'computer'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'photo'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'hairdresser'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'beauty'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'cosmetics'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'optician'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'laundry'], '#6ABFBA',
      //         ['==', ['get', 'shop'], 'furniture'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'florist'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'hardware'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'doityourself'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'bicycle'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'car'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'car_repair'], '#4A90E2',
      //         ['==', ['get', 'shop'], 'motorcycle'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'travel_agency'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'ticket'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'kiosk'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'pet'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'music'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'musical_instrument'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'video_games'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'tobacco'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'lottery'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'mall'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'department_store'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'outdoor'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'charity'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'second_hand'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'antiques'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'art'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'wholesale'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'newsagent'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'copyshop'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'erotic'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'wine'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'caravan'], '#9B59B6',
      //         ['has', 'shop'], '#9B59B6',   // Purple for other shop (fallback)
      //         ['==', ['get', 'tourism'], 'hotel'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'motel'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'hostel'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'apartment'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'guest_house'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'camp_site'], '#00B050',
      //         ['==', ['get', 'tourism'], 'caravan_site'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'alpine_hut'], '#C09B89',
      //         ['==', ['get', 'tourism'], 'museum'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'gallery'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'artwork'], '#805933',
      //         ['==', ['get', 'tourism'], 'attraction'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'theme_park'], '#4A90E2',
      //         ['==', ['get', 'tourism'], 'zoo'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'aquarium'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'viewpoint'], '#805933',
      //         ['==', ['get', 'tourism'], 'information'], '#4A90E2',
      //         ['==', ['get', 'tourism'], 'picnic_site'], '#717065',
      //         ['==', ['get', 'tourism'], 'wine_cellar'], '#9B59B6',
      //         ['has', 'tourism'], '#666564',   // Gray for other tourism (fallback)
      //         ['==', ['get', 'leisure'], 'playground'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'park'], '#00B050',
      //         ['==', ['get', 'leisure'], 'garden'], '#00B050',
      //         ['==', ['get', 'leisure'], 'sports_centre'], '#9B59B6',
      //         ['==', ['get', 'leisure'], 'stadium'], '#6ABFBA',
      //         ['==', ['get', 'leisure'], 'pitch'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'swimming_pool'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'fitness_centre'], '#4A90E2',
      //         ['==', ['get', 'leisure'], 'fitness_station'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'golf_course'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'marina'], '#6ABFBA',
      //         ['==', ['get', 'leisure'], 'bowling_alley'], '#9B59B6',
      //         ['==', ['get', 'leisure'], 'dog_park'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'beach_resort'], '#00B050',
      //         ['==', ['get', 'leisure'], 'sauna'], '#4A90E2',
      //         ['==', ['get', 'leisure'], 'outdoor_seating'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'picnic_table'], '#7F5933',
      //         ['has', 'leisure'], '#666564',   // Gray for other leisure (fallback)
      //         ['==', ['get', 'sport'], 'tennis'], '#717065',
      //         ['==', ['get', 'sport'], 'basketball'], '#717065',
      //         ['==', ['get', 'sport'], 'volleyball'], '#717065',
      //         ['==', ['get', 'sport'], 'soccer'], '#717065',
      //         ['==', ['get', 'sport'], 'american_football'], '#717065',
      //         ['==', ['get', 'sport'], 'baseball'], '#717065',
      //         ['==', ['get', 'sport'], 'cricket'], '#717065',
      //         ['==', ['get', 'sport'], 'hockey'], '#717065',
      //         ['==', ['get', 'sport'], 'handball'], '#717065',
      //         ['==', ['get', 'sport'], 'table_tennis'], '#717065',
      //         ['==', ['get', 'sport'], 'badminton'], '#717065',
      //         ['==', ['get', 'sport'], 'pelota'], '#717065',
      //         ['==', ['get', 'sport'], 'padel'], '#717065',
      //         ['==', ['get', 'sport'], 'swimming'], '#717065',
      //         ['==', ['get', 'sport'], 'diving'], '#717065',
      //         ['==', ['get', 'sport'], 'golf'], '#717065',
      //         ['==', ['get', 'sport'], 'climbing'], '#717065',
      //         ['==', ['get', 'sport'], 'archery'], '#717065',
      //         ['==', ['get', 'sport'], 'bowling'], '#717065',
      //         ['==', ['get', 'sport'], 'skateboard'], '#717065',
      //         ['==', ['get', 'sport'], 'skiing'], '#717065',
      //         ['==', ['get', 'sport'], 'curling'], '#717065',
      //         ['==', ['get', 'sport'], 'equestrian'], '#717065',
      //         ['==', ['get', 'sport'], 'australian_football'], '#717065',
      //         ['==', ['get', 'sport'], 'chess'], '#717065',
      //         ['==', ['get', 'sport'], 'gym'], '#717065',
      //         ['==', ['get', 'sport'], 'yoga'], '#717065',
      //         ['has', 'sport'], '#666564',     // gray for other sports (fallback)
      //         ['==', ['get', 'railway'], 'station'], '#619BD5',
      //         ['==', ['get', 'railway'], 'halt'], '#619BD5',
      //         ['==', ['get', 'railway'], 'tram_stop'], '#619BD5',
      //         ['==', ['get', 'railway'], 'subway_entrance'], '#006F35',
      //         ['==', ['get', 'railway'], 'level_crossing'], '#CC2A25',
      //         ['has', 'railway'], '#666564',   // Gray for other railway (fallback)
      //         ['==', ['get', 'highway'], 'bus_stop'], '#619BD5',
      //         ['==', ['get', 'highway'], 'toll_booth'], '#619BD5',
      //         ['==', ['get', 'highway'], 'speed_camera'], '#000000',
      //         ['has', 'highway'], '#666564',   // Gray for other highway (fallback)
      //         ['has', 'power'], '#666564',     // gray for power
      //         ['==', ['get', 'office'], 'government'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'company'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'lawyer'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'insurance'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'estate_agent'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'travel_agent'], '#AB58B7',
      //         ['has', 'office'], '#666564',    // gray for other office (fallback)
      //         ['==', ['get', 'barrier'], 'lift_gate'], '#717065',
      //         ['==', ['get', 'barrier'], 'toll_booth'], '#4A90E2',
      //         ['has', 'barrier'], '#666564',   // Gray for other barrier (fallback)
      //         ['==', ['get', 'public_transport'], 'station'], '#4A90E2',
      //         ['==', ['get', 'public_transport'], 'stop_position'], '#4A90E2',
      //         ['has', 'public_transport'], '#666564',   // Gray for other public_transport (fallback)
      //         ['==', ['get', 'emergency'], 'phone'], '#D63625',
      //         ['==', ['get', 'emergency'], 'fire_hydrant'], '#D63625',
      //         ['==', ['get', 'emergency'], 'defibrillator'], '#D63625',
      //         ['==', ['get', 'emergency'], 'assembly_point'], '#D63625',
      //         ['has', 'emergency'], '#666564',   // Gray for other emergency (fallback)
      //         ['==', ['get', 'man_made'], 'lighthouse'], '#4A90E2',
      //         ['==', ['get', 'man_made'], 'windmill'], '#4A90E2',
      //         ['==', ['get', 'man_made'], 'tower'], '#727065',
      //         ['==', ['get', 'man_made'], 'chimney'], '#727065',
      //         ['==', ['get', 'man_made'], 'surveillance'], '#000000',
      //         ['==', ['get', 'man_made'], 'survey_point'], '#727065',
      //         ['has', 'man_made'], '#666564',   // Gray for other man_made (fallback)
      //         ['==', ['get', 'historic'], 'archaeological_site'], '#7F5933',
      //         ['==', ['get', 'historic'], 'monument'], '#7F5933',
      //         ['==', ['get', 'historic'], 'castle'], '#7F5933',
      //         ['==', ['get', 'historic'], 'ruins'], '#7F5933',
      //         ['==', ['get', 'historic'], 'memorial'], '#7F5933',
      //         ['==', ['get', 'historic'], 'statue'], '#7F5933',
      //         ['==', ['get', 'historic'], 'cross'], '#7F5933',
      //         ['==', ['get', 'historic'], 'wayside_shrine'], '#7F5933',
      //         ['==', ['get', 'historic'], 'tomb'], '#7F5933',
      //         ['==', ['get', 'historic'], 'ship'], '#6ABFBA',
      //         ['==', ['get', 'historic'], 'cannon'], '#7F5933',
      //         ['==', ['get', 'historic'], 'tank'], '#7F5933',
      //         ['==', ['get', 'historic'], 'aircraft'], '#7F5933',
      //         ['==', ['get', 'historic'], 'locomotive'], '#7F5933',
      //         ['==', ['get', 'historic'], 'windmill'], '#4A90E2',
      //         ['==', ['get', 'historic'], 'watermill'], '#9B59B6',
      //         ['==', ['get', 'historic'], 'lighthouse'], '#4A90E2',
      //         ['==', ['get', 'historic'], 'mine'], '#4A90E2',
      //         ['==', ['get', 'historic'], 'wreck'], '#7F5933',
      //         ['has', 'historic'], '#666564',   // Gray for other historic (fallback)
      //         ['==', ['get', 'landuse'], 'grass'], '#00B050',
      //         ['==', ['get', 'landuse'], 'forest'], '#00B050',
      //         ['==', ['get', 'landuse'], 'park'], '#00B050',
      //         ['==', ['get', 'landuse'], 'recreation_ground'], '#00B050',
      //         ['==', ['get', 'landuse'], 'village_green'], '#00B050',
      //         ['==', ['get', 'landuse'], 'meadow'], '#00B050',
      //         ['==', ['get', 'landuse'], 'retail'], '#9B59B6',
      //         ['==', ['get', 'landuse'], 'cemetery'], '#7F5933',
      //         ['==', ['get', 'landuse'], 'vineyard'], '#9B59B6',
      //         ['has', 'landuse'], '#666564',   // Gray for other landuse (fallback)
      //         ['==', ['get', 'craft'], 'brewery'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'winery'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'carpenter'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'electrician'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'plumber'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'painter'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'blacksmith'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'beekeeper'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'caterer'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'key_cutter'], '#9B59B6',
      //         ['has', 'craft'], '#666564',   // Gray for other craft (fallback)
      //         ['==', ['get', 'healthcare'], 'audiologist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'optometrist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'physiotherapist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'podiatrist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'psychotherapist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'speech_therapist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'blood_donation'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'sample_collection'], '#E3897A',
      //         ['has', 'healthcare'], '#666564',   // Gray for other healthcare (fallback)
      //         ['==', ['get', 'natural'], 'beach'], '#00B050',
      //         ['==', ['get', 'natural'], 'cave_entrance'], '#7F5933',
      //         ['==', ['get', 'natural'], 'volcano'], '#7F5933',
      //         ['==', ['get', 'natural'], 'waterfall'], '#4A90E2',
      //         ['==', ['get', 'natural'], 'geyser'], '#4A90E2',
      //         ['==', ['get', 'natural'], 'peak'], '#7F5933',
      //         ['==', ['get', 'natural'], 'spring'], '#4A90E2',
      //         ['has', 'natural'], '#666564',   // Gray for other natural (fallback)
      //         '#000000',  // Default black
      //       ],
      //       'text-halo-color': '#FFFFFF',
      //       'text-halo-width': 2,
      //     },
      //   ),
      // );

      // // Layer 2: Priority POIs (zoom 12+)
      // await _styleController!.addLayer(
      //   SymbolStyleLayer(
      //     id: 'poi-priority',
      //     sourceId: 'poi-source',
      //     minZoom: 12,
      //     maxZoom: 24,
      //     filter: [
      //       '!=',
      //       ['get', 'man_made'],
      //       'surveillance',
      //     ],
      //     layout: {
      //       'source-layer': 'pois',
      //       'icon-image': iconImageExpression,
      //       'icon-size': iconSize,
      //       'icon-allow-overlap': false,
      //       'icon-ignore-placement': false,
      //       'icon-padding': [
      //         'interpolate',
      //         ['linear'],
      //         ['zoom'],
      //         12, 35,  // Increased padding for more spacing
      //         16, 25,
      //         18, 15,
      //         20, 10
      //       ],
      //       'text-field': [
      //         'case',
      //         ['==', ['get', 'amenity'], 'bench'], '',
      //         ['==', ['get', 'leisure'], 'park'], '',
      //         ['==', ['get', 'amenity'], 'recycling'], '',
      //         ['==', ['get', 'amenity'], 'waste_basket'], '',
      //         ['==', ['get', 'amenity'], 'vending_machine'], '',
      //         ['==', ['get', 'amenity'], 'waste_disposal'], '',
      //         ['==', ['get', 'tourism'], 'artwork'], '',
      //         ['==', ['get', 'amenity'], 'parking_entrance'], '',
      //         ['==', ['get', 'amenity'], 'bicycle_parking'], '',
      //         ['==', ['get', 'amenity'], 'taxi'], '',
      //         ['==', ['get', 'amenity'], 'drinking_water'], '',
      //         [
      //           'coalesce',
      //           ['get', 'name'],
      //           ['get', 'amenity'],
      //           ['get', 'leisure'],
      //           ['get', 'tourism'],
      //           '',
      //         ],
      //       ],
      //       'text-font': ['Montserrat Bold'],
      //       'text-size': [
      //         'interpolate',
      //         ['linear'],
      //         ['zoom'],
      //         12, 8,
      //         16, 9,
      //         18, 11,
      //         20, 13,
      //         22, 14
      //       ],
      //       'text-anchor': 'left',
      //       'text-offset': [1.5, 0],
      //       'text-allow-overlap': true,
      //       'text-optional': true,
      //     },
      //     paint: {
      //       'icon-opacity': [
      //         'step',
      //         ['zoom'],
      //         0,    // invisible below zoom 12
      //         12, 1,  // visible at zoom 12+
      //       ],
      //       'text-opacity': [
      //         'step',
      //         ['zoom'],
      //         0,
      //         12, 1,
      //       ],
      //       'text-color': [
      //         'case',
      //         ['has', 'aeroway'], '#9B59B6',   // Purple for aeroway
      //         ['==', ['get', 'amenity'], 'restaurant'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'fast_food'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'cafe'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'bar'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'pub'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'bakery'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'ice_cream'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'hospital'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'clinic'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'pharmacy'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'dentist'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'veterinary'], '#D06B5B',
      //         ['==', ['get', 'amenity'], 'bank'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'atm'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'police'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'fire_station'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'post_office'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'school'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'kindergarten'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'college'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'university'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'library'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'theatre'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'cinema'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'nightclub'], '#FFD700',
      //         ['==', ['get', 'amenity'], 'casino'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'fuel'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'parking'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'bicycle_parking'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'taxi'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'car_wash'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'car_sharing'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'charging_station'], '#00B050',
      //         ['==', ['get', 'amenity'], 'bicycle_rental'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'car_rental'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'motorcycle_parking'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'toilets'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'drinking_water'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'fountain'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'recycling'], '#717065',
      //         ['==', ['get', 'amenity'], 'waste_basket'], '#717065',
      //         ['==', ['get', 'amenity'], 'telephone'], '#717065',
      //         ['==', ['get', 'amenity'], 'marketplace'], '#9B59B6',
      //         ['==', ['get', 'amenity'], 'vending_machine'], '#707066',
      //         ['==', ['get', 'amenity'], 'bbq'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'bench'], '#717065',
      //         ['==', ['get', 'amenity'], 'shelter'], '#717065',
      //         ['==', ['get', 'amenity'], 'shower'], '#717065',
      //         ['==', ['get', 'amenity'], 'embassy'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'prison'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'courthouse'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'townhall'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'grave_yard'], '#717065',
      //         ['==', ['get', 'amenity'], 'crematorium'], '#717065',
      //         ['==', ['get', 'amenity'], 'place_of_worship'], '#6ABFBA',
      //         ['==', ['get', 'amenity'], 'ferry_terminal'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'bus_station'], '#4A90E2',
      //         ['==', ['get', 'amenity'], 'trolleybus_station'], '#4A90E2',
      //         ['has', 'amenity'], '#6ABFBA',   // Teal for other amenity (fallback)
      //         ['==', ['get', 'shop'], 'supermarket'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'convenience'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'bakery'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'butcher'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'greengrocer'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'seafood'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'cheese'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'confectionery'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'ice_cream'], '#FFD700',
      //         ['==', ['get', 'shop'], 'alcohol'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'clothes'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'shoes'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'jewelry'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'gift'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'toys'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'books'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'stationery'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'electronics'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'mobile_phone'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'computer'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'photo'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'hairdresser'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'beauty'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'cosmetics'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'optician'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'laundry'], '#6ABFBA',
      //         ['==', ['get', 'shop'], 'furniture'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'florist'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'hardware'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'doityourself'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'bicycle'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'car'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'car_repair'], '#4A90E2',
      //         ['==', ['get', 'shop'], 'motorcycle'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'travel_agency'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'ticket'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'kiosk'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'pet'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'music'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'musical_instrument'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'video_games'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'tobacco'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'lottery'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'mall'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'department_store'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'outdoor'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'charity'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'second_hand'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'antiques'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'art'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'wholesale'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'newsagent'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'copyshop'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'erotic'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'wine'], '#9B59B6',
      //         ['==', ['get', 'shop'], 'caravan'], '#9B59B6',
      //         ['has', 'shop'], '#9B59B6',   // Purple for other shop (fallback)
      //         ['==', ['get', 'tourism'], 'hotel'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'motel'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'hostel'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'apartment'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'guest_house'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'camp_site'], '#00B050',
      //         ['==', ['get', 'tourism'], 'caravan_site'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'alpine_hut'], '#C09B89',
      //         ['==', ['get', 'tourism'], 'museum'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'gallery'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'artwork'], '#805933',
      //         ['==', ['get', 'tourism'], 'attraction'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'theme_park'], '#4A90E2',
      //         ['==', ['get', 'tourism'], 'zoo'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'aquarium'], '#6ABFBA',
      //         ['==', ['get', 'tourism'], 'viewpoint'], '#805933',
      //         ['==', ['get', 'tourism'], 'information'], '#4A90E2',
      //         ['==', ['get', 'tourism'], 'picnic_site'], '#717065',
      //         ['==', ['get', 'tourism'], 'wine_cellar'], '#9B59B6',
      //         ['has', 'tourism'], '#666564',   // Gray for other tourism (fallback)
      //         ['==', ['get', 'leisure'], 'playground'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'park'], '#00B050',
      //         ['==', ['get', 'leisure'], 'garden'], '#00B050',
      //         ['==', ['get', 'leisure'], 'sports_centre'], '#9B59B6',
      //         ['==', ['get', 'leisure'], 'stadium'], '#6ABFBA',
      //         ['==', ['get', 'leisure'], 'pitch'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'swimming_pool'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'fitness_centre'], '#4A90E2',
      //         ['==', ['get', 'leisure'], 'fitness_station'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'golf_course'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'marina'], '#6ABFBA',
      //         ['==', ['get', 'leisure'], 'bowling_alley'], '#9B59B6',
      //         ['==', ['get', 'leisure'], 'dog_park'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'beach_resort'], '#00B050',
      //         ['==', ['get', 'leisure'], 'sauna'], '#4A90E2',
      //         ['==', ['get', 'leisure'], 'outdoor_seating'], '#7F5933',
      //         ['==', ['get', 'leisure'], 'picnic_table'], '#7F5933',
      //         ['has', 'leisure'], '#666564',   // Gray for other leisure (fallback)
      //         ['==', ['get', 'sport'], 'tennis'], '#717065',
      //         ['==', ['get', 'sport'], 'basketball'], '#717065',
      //         ['==', ['get', 'sport'], 'volleyball'], '#717065',
      //         ['==', ['get', 'sport'], 'soccer'], '#717065',
      //         ['==', ['get', 'sport'], 'american_football'], '#717065',
      //         ['==', ['get', 'sport'], 'baseball'], '#717065',
      //         ['==', ['get', 'sport'], 'cricket'], '#717065',
      //         ['==', ['get', 'sport'], 'hockey'], '#717065',
      //         ['==', ['get', 'sport'], 'handball'], '#717065',
      //         ['==', ['get', 'sport'], 'table_tennis'], '#717065',
      //         ['==', ['get', 'sport'], 'badminton'], '#717065',
      //         ['==', ['get', 'sport'], 'pelota'], '#717065',
      //         ['==', ['get', 'sport'], 'padel'], '#717065',
      //         ['==', ['get', 'sport'], 'swimming'], '#717065',
      //         ['==', ['get', 'sport'], 'diving'], '#717065',
      //         ['==', ['get', 'sport'], 'golf'], '#717065',
      //         ['==', ['get', 'sport'], 'climbing'], '#717065',
      //         ['==', ['get', 'sport'], 'archery'], '#717065',
      //         ['==', ['get', 'sport'], 'bowling'], '#717065',
      //         ['==', ['get', 'sport'], 'skateboard'], '#717065',
      //         ['==', ['get', 'sport'], 'skiing'], '#717065',
      //         ['==', ['get', 'sport'], 'curling'], '#717065',
      //         ['==', ['get', 'sport'], 'equestrian'], '#717065',
      //         ['==', ['get', 'sport'], 'australian_football'], '#717065',
      //         ['==', ['get', 'sport'], 'chess'], '#717065',
      //         ['==', ['get', 'sport'], 'gym'], '#717065',
      //         ['==', ['get', 'sport'], 'yoga'], '#717065',
      //         ['has', 'sport'], '#666564',     // gray for other sports (fallback)
      //         ['==', ['get', 'railway'], 'station'], '#619BD5',
      //         ['==', ['get', 'railway'], 'halt'], '#619BD5',
      //         ['==', ['get', 'railway'], 'tram_stop'], '#619BD5',
      //         ['==', ['get', 'railway'], 'subway_entrance'], '#006F35',
      //         ['==', ['get', 'railway'], 'level_crossing'], '#CC2A25',
      //         ['has', 'railway'], '#666564',   // Gray for other railway (fallback)
      //         ['==', ['get', 'highway'], 'bus_stop'], '#619BD5',
      //         ['==', ['get', 'highway'], 'toll_booth'], '#619BD5',
      //         ['==', ['get', 'highway'], 'speed_camera'], '#000000',
      //         ['has', 'highway'], '#666564',   // Gray for other highway (fallback)
      //         ['has', 'power'], '#666564',     // gray for power
      //         ['==', ['get', 'office'], 'government'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'company'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'lawyer'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'insurance'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'estate_agent'], '#7BB1E1',
      //         ['==', ['get', 'office'], 'travel_agent'], '#AB58B7',
      //         ['has', 'office'], '#666564',    // gray for other office (fallback)
      //         ['==', ['get', 'barrier'], 'lift_gate'], '#717065',
      //         ['==', ['get', 'barrier'], 'toll_booth'], '#4A90E2',
      //         ['has', 'barrier'], '#666564',   // Gray for other barrier (fallback)
      //         ['==', ['get', 'public_transport'], 'station'], '#4A90E2',
      //         ['==', ['get', 'public_transport'], 'stop_position'], '#4A90E2',
      //         ['has', 'public_transport'], '#666564',   // Gray for other public_transport (fallback)
      //         ['==', ['get', 'emergency'], 'phone'], '#D63625',
      //         ['==', ['get', 'emergency'], 'fire_hydrant'], '#D63625',
      //         ['==', ['get', 'emergency'], 'defibrillator'], '#D63625',
      //         ['==', ['get', 'emergency'], 'assembly_point'], '#D63625',
      //         ['has', 'emergency'], '#666564',   // Gray for other emergency (fallback)
      //         ['==', ['get', 'man_made'], 'lighthouse'], '#4A90E2',
      //         ['==', ['get', 'man_made'], 'windmill'], '#4A90E2',
      //         ['==', ['get', 'man_made'], 'tower'], '#727065',
      //         ['==', ['get', 'man_made'], 'chimney'], '#727065',
      //         ['==', ['get', 'man_made'], 'surveillance'], '#000000',
      //         ['==', ['get', 'man_made'], 'survey_point'], '#727065',
      //         ['has', 'man_made'], '#666564',   // Gray for other man_made (fallback)
      //         ['==', ['get', 'historic'], 'archaeological_site'], '#7F5933',
      //         ['==', ['get', 'historic'], 'monument'], '#7F5933',
      //         ['==', ['get', 'historic'], 'castle'], '#7F5933',
      //         ['==', ['get', 'historic'], 'ruins'], '#7F5933',
      //         ['==', ['get', 'historic'], 'memorial'], '#7F5933',
      //         ['==', ['get', 'historic'], 'statue'], '#7F5933',
      //         ['==', ['get', 'historic'], 'cross'], '#7F5933',
      //         ['==', ['get', 'historic'], 'wayside_shrine'], '#7F5933',
      //         ['==', ['get', 'historic'], 'tomb'], '#7F5933',
      //         ['==', ['get', 'historic'], 'ship'], '#6ABFBA',
      //         ['==', ['get', 'historic'], 'cannon'], '#7F5933',
      //         ['==', ['get', 'historic'], 'tank'], '#7F5933',
      //         ['==', ['get', 'historic'], 'aircraft'], '#7F5933',
      //         ['==', ['get', 'historic'], 'locomotive'], '#7F5933',
      //         ['==', ['get', 'historic'], 'windmill'], '#4A90E2',
      //         ['==', ['get', 'historic'], 'watermill'], '#9B59B6',
      //         ['==', ['get', 'historic'], 'lighthouse'], '#4A90E2',
      //         ['==', ['get', 'historic'], 'mine'], '#4A90E2',
      //         ['==', ['get', 'historic'], 'wreck'], '#7F5933',
      //         ['has', 'historic'], '#666564',   // Gray for other historic (fallback)
      //         ['==', ['get', 'landuse'], 'grass'], '#00B050',
      //         ['==', ['get', 'landuse'], 'forest'], '#00B050',
      //         ['==', ['get', 'landuse'], 'park'], '#00B050',
      //         ['==', ['get', 'landuse'], 'recreation_ground'], '#00B050',
      //         ['==', ['get', 'landuse'], 'village_green'], '#00B050',
      //         ['==', ['get', 'landuse'], 'meadow'], '#00B050',
      //         ['==', ['get', 'landuse'], 'retail'], '#9B59B6',
      //         ['==', ['get', 'landuse'], 'cemetery'], '#7F5933',
      //         ['==', ['get', 'landuse'], 'vineyard'], '#9B59B6',
      //         ['has', 'landuse'], '#666564',   // Gray for other landuse (fallback)
      //         ['==', ['get', 'craft'], 'brewery'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'winery'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'carpenter'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'electrician'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'plumber'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'painter'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'blacksmith'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'beekeeper'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'caterer'], '#9B59B6',
      //         ['==', ['get', 'craft'], 'key_cutter'], '#9B59B6',
      //         ['has', 'craft'], '#666564',   // Gray for other craft (fallback)
      //         ['==', ['get', 'healthcare'], 'audiologist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'optometrist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'physiotherapist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'podiatrist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'psychotherapist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'speech_therapist'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'blood_donation'], '#E3897A',
      //         ['==', ['get', 'healthcare'], 'sample_collection'], '#E3897A',
      //         ['has', 'healthcare'], '#666564',   // Gray for other healthcare (fallback)
      //         ['==', ['get', 'natural'], 'beach'], '#00B050',
      //         ['==', ['get', 'natural'], 'cave_entrance'], '#7F5933',
      //         ['==', ['get', 'natural'], 'volcano'], '#7F5933',
      //         ['==', ['get', 'natural'], 'waterfall'], '#4A90E2',
      //         ['==', ['get', 'natural'], 'geyser'], '#4A90E2',
      //         ['==', ['get', 'natural'], 'peak'], '#7F5933',
      //         ['==', ['get', 'natural'], 'spring'], '#4A90E2',
      //         ['has', 'natural'], '#666564',   // Gray for other natural (fallback)
      //         '#000000',  // Default black
      //       ],
      //       'text-halo-color': '#FFFFFF',
      //       'text-halo-width': 2,
      //     },
      //   ),
      // );

      // // Layer 3: All other POIs (zoom 16+)
      await _styleController!.addLayer(
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
              ['has', 'aeroway'], '#1F4A77',   // Purple for aeroway
              ['==', ['get', 'amenity'], 'restaurant'], '#E89914',
              ['==', ['get', 'amenity'], 'fast_food'], '#E89914',
              ['==', ['get', 'amenity'], 'cafe'], '#E89914',
              ['==', ['get', 'amenity'], 'bar'], '#E89914',
              ['==', ['get', 'amenity'], 'pub'], '#E89914',
              ['==', ['get', 'amenity'], 'bakery'], '#734087',
              ['==', ['get', 'amenity'], 'ice_cream'], '#E89914',
              ['==', ['get', 'amenity'], 'hospital'], '#9B4F42',
              ['==', ['get', 'amenity'], 'clinic'], '#9B4F42',
              ['==', ['get', 'amenity'], 'pharmacy'], '#9B4F42',
              ['==', ['get', 'amenity'], 'dentist'], '#9B4F42',
              ['==', ['get', 'amenity'], 'veterinary'], '#9B4F42',
              ['==', ['get', 'amenity'], 'bank'], '#356AA6',
              ['==', ['get', 'amenity'], 'atm'], '#356AA6',
              ['==', ['get', 'amenity'], 'police'], '#356AA6',
              ['==', ['get', 'amenity'], 'fire_station'], '#356AA6',
              ['==', ['get', 'amenity'], 'post_office'], '#356AA6',
              ['==', ['get', 'amenity'], 'school'], '#356AA6',
              ['==', ['get', 'amenity'], 'kindergarten'], '#356AA6',
              ['==', ['get', 'amenity'], 'college'], '#356AA6',
              ['==', ['get', 'amenity'], 'university'], '#356AA6',
              ['==', ['get', 'amenity'], 'library'], '#356AA6',
              ['==', ['get', 'amenity'], 'theatre'], '#4F8E8B',
              ['==', ['get', 'amenity'], 'cinema'], '#4F8E8B',
              ['==', ['get', 'amenity'], 'nightclub'], '#E89914',
              ['==', ['get', 'amenity'], 'casino'], '#4F8E8B',
              ['==', ['get', 'amenity'], 'fuel'], '#356AA6',
              ['==', ['get', 'amenity'], 'parking'], '#356AA6',
              ['==', ['get', 'amenity'], 'bicycle_parking'], '#356AA6',
              ['==', ['get', 'amenity'], 'taxi'], '#356AA6',
              ['==', ['get', 'amenity'], 'car_wash'], '#356AA6',
              ['==', ['get', 'amenity'], 'car_sharing'], '#356AA6',
              ['==', ['get', 'amenity'], 'charging_station'], '#008038',
              ['==', ['get', 'amenity'], 'bicycle_rental'], '#734087',
              ['==', ['get', 'amenity'], 'car_rental'], '#734087',
              ['==', ['get', 'amenity'], 'motorcycle_parking'], '#734087',
              ['==', ['get', 'amenity'], 'toilets'], '#4F8E8B',
              ['==', ['get', 'amenity'], 'drinking_water'], '#356AA6',
              ['==', ['get', 'amenity'], 'fountain'], '#356AA6',
              ['==', ['get', 'amenity'], 'recycling'], '#54504A',
              ['==', ['get', 'amenity'], 'waste_basket'], '#54504A',
              ['==', ['get', 'amenity'], 'telephone'], '#54504A',
              ['==', ['get', 'amenity'], 'marketplace'], '#734087',
              ['==', ['get', 'amenity'], 'vending_machine'], '#53504B',
              ['==', ['get', 'amenity'], 'bbq'], '#356AA6',
              ['==', ['get', 'amenity'], 'bench'], '#54504A',
              ['==', ['get', 'amenity'], 'shelter'], '#54504A',
              ['==', ['get', 'amenity'], 'shower'], '#54504A',
              ['==', ['get', 'amenity'], 'embassy'], '#356AA6',
              ['==', ['get', 'amenity'], 'prison'], '#356AA6',
              ['==', ['get', 'amenity'], 'courthouse'], '#356AA6',
              ['==', ['get', 'amenity'], 'townhall'], '#356AA6',
              ['==', ['get', 'amenity'], 'grave_yard'], '#54504A',
              ['==', ['get', 'amenity'], 'crematorium'], '#54504A',
              ['==', ['get', 'amenity'], 'place_of_worship'], '#4F8E8B',
              ['==', ['get', 'amenity'], 'ferry_terminal'], '#356AA6',
              ['==', ['get', 'amenity'], 'bus_station'], '#356AA6',
              ['==', ['get', 'amenity'], 'trolleybus_station'], '#356AA6',
              ['has', 'amenity'], '#4F8E8B',   // Darker teal for other amenity (fallback)
              ['==', ['get', 'shop'], 'supermarket'], '#734087',
              ['==', ['get', 'shop'], 'convenience'], '#734087',
              ['==', ['get', 'shop'], 'bakery'], '#734087',
              ['==', ['get', 'shop'], 'butcher'], '#734087',
              ['==', ['get', 'shop'], 'greengrocer'], '#734087',
              ['==', ['get', 'shop'], 'seafood'], '#734087',
              ['==', ['get', 'shop'], 'cheese'], '#734087',
              ['==', ['get', 'shop'], 'confectionery'], '#734087',
              ['==', ['get', 'shop'], 'ice_cream'], '#E89914',
              ['==', ['get', 'shop'], 'alcohol'], '#734087',
              ['==', ['get', 'shop'], 'clothes'], '#734087',
              ['==', ['get', 'shop'], 'shoes'], '#734087',
              ['==', ['get', 'shop'], 'jewelry'], '#734087',
              ['==', ['get', 'shop'], 'gift'], '#734087',
              ['==', ['get', 'shop'], 'toys'], '#734087',
              ['==', ['get', 'shop'], 'books'], '#734087',
              ['==', ['get', 'shop'], 'stationery'], '#734087',
              ['==', ['get', 'shop'], 'electronics'], '#734087',
              ['==', ['get', 'shop'], 'mobile_phone'], '#734087',
              ['==', ['get', 'shop'], 'computer'], '#734087',
              ['==', ['get', 'shop'], 'photo'], '#734087',
              ['==', ['get', 'shop'], 'hairdresser'], '#734087',
              ['==', ['get', 'shop'], 'beauty'], '#734087',
              ['==', ['get', 'shop'], 'cosmetics'], '#734087',
              ['==', ['get', 'shop'], 'optician'], '#734087',
              ['==', ['get', 'shop'], 'laundry'], '#4F8E8B',
              ['==', ['get', 'shop'], 'furniture'], '#734087',
              ['==', ['get', 'shop'], 'florist'], '#734087',
              ['==', ['get', 'shop'], 'hardware'], '#734087',
              ['==', ['get', 'shop'], 'doityourself'], '#734087',
              ['==', ['get', 'shop'], 'bicycle'], '#734087',
              ['==', ['get', 'shop'], 'car'], '#734087',
              ['==', ['get', 'shop'], 'car_repair'], '#356AA6',
              ['==', ['get', 'shop'], 'motorcycle'], '#734087',
              ['==', ['get', 'shop'], 'travel_agency'], '#734087',
              ['==', ['get', 'shop'], 'ticket'], '#734087',
              ['==', ['get', 'shop'], 'kiosk'], '#734087',
              ['==', ['get', 'shop'], 'pet'], '#734087',
              ['==', ['get', 'shop'], 'music'], '#734087',
              ['==', ['get', 'shop'], 'musical_instrument'], '#734087',
              ['==', ['get', 'shop'], 'video_games'], '#734087',
              ['==', ['get', 'shop'], 'tobacco'], '#734087',
              ['==', ['get', 'shop'], 'lottery'], '#734087',
              ['==', ['get', 'shop'], 'mall'], '#734087',
              ['==', ['get', 'shop'], 'department_store'], '#734087',
              ['==', ['get', 'shop'], 'outdoor'], '#734087',
              ['==', ['get', 'shop'], 'charity'], '#734087',
              ['==', ['get', 'shop'], 'second_hand'], '#734087',
              ['==', ['get', 'shop'], 'antiques'], '#734087',
              ['==', ['get', 'shop'], 'art'], '#734087',
              ['==', ['get', 'shop'], 'wholesale'], '#734087',
              ['==', ['get', 'shop'], 'newsagent'], '#734087',
              ['==', ['get', 'shop'], 'copyshop'], '#734087',
              ['==', ['get', 'shop'], 'erotic'], '#734087',
              ['==', ['get', 'shop'], 'wine'], '#734087',
              ['==', ['get', 'shop'], 'caravan'], '#734087',
              ['has', 'shop'], '#734087',   // Darker purple for other shop (fallback)
              ['==', ['get', 'tourism'], 'hotel'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'motel'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'hostel'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'apartment'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'guest_house'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'camp_site'], '#008038',
              ['==', ['get', 'tourism'], 'caravan_site'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'alpine_hut'], '#8C7360',
              ['==', ['get', 'tourism'], 'museum'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'gallery'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'artwork'], '#5A3F26',
              ['==', ['get', 'tourism'], 'attraction'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'theme_park'], '#356AA6',
              ['==', ['get', 'tourism'], 'zoo'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'aquarium'], '#4F8E8B',
              ['==', ['get', 'tourism'], 'viewpoint'], '#5A3F26',
              ['==', ['get', 'tourism'], 'information'], '#356AA6',
              ['==', ['get', 'tourism'], 'picnic_site'], '#54504A',
              ['==', ['get', 'tourism'], 'wine_cellar'], '#734087',
              ['has', 'tourism'], '#666564',   // Gray for other tourism (fallback)
              ['==', ['get', 'leisure'], 'playground'], '#5F4226',
              ['==', ['get', 'leisure'], 'park'], '#008038',
              ['==', ['get', 'leisure'], 'garden'], '#008038',
              ['==', ['get', 'leisure'], 'sports_centre'], '#734087',
              ['==', ['get', 'leisure'], 'stadium'], '#4F8E8B',
              ['==', ['get', 'leisure'], 'pitch'], '#5F4226',
              ['==', ['get', 'leisure'], 'swimming_pool'], '#5F4226',
              ['==', ['get', 'leisure'], 'fitness_centre'], '#356AA6',
              ['==', ['get', 'leisure'], 'fitness_station'], '#5F4226',
              ['==', ['get', 'leisure'], 'golf_course'], '#5F4226',
              ['==', ['get', 'leisure'], 'marina'], '#4F8E8B',
              ['==', ['get', 'leisure'], 'bowling_alley'], '#734087',
              ['==', ['get', 'leisure'], 'dog_park'], '#5F4226',
              ['==', ['get', 'leisure'], 'beach_resort'], '#008038',
              ['==', ['get', 'leisure'], 'sauna'], '#356AA6',
              ['==', ['get', 'leisure'], 'outdoor_seating'], '#5F4226',
              ['==', ['get', 'leisure'], 'picnic_table'], '#5F4226',
              ['has', 'leisure'], '#666564',   // Gray for other leisure (fallback)
              ['==', ['get', 'sport'], 'tennis'], '#5A5349',
              ['==', ['get', 'sport'], 'basketball'], '#5A5349',
              ['==', ['get', 'sport'], 'volleyball'], '#5A5349',
              ['==', ['get', 'sport'], 'soccer'], '#5A5349',
              ['==', ['get', 'sport'], 'american_football'], '#5A5349',
              ['==', ['get', 'sport'], 'baseball'], '#5A5349',
              ['==', ['get', 'sport'], 'cricket'], '#5A5349',
              ['==', ['get', 'sport'], 'hockey'], '#5A5349',
              ['==', ['get', 'sport'], 'handball'], '#5A5349',
              ['==', ['get', 'sport'], 'table_tennis'], '#5A5349',
              ['==', ['get', 'sport'], 'badminton'], '#5A5349',
              ['==', ['get', 'sport'], 'pelota'], '#5A5349',
              ['==', ['get', 'sport'], 'padel'], '#5A5349',
              ['==', ['get', 'sport'], 'swimming'], '#5A5349',
              ['==', ['get', 'sport'], 'diving'], '#5A5349',
              ['==', ['get', 'sport'], 'golf'], '#5A5349',
              ['==', ['get', 'sport'], 'climbing'], '#5A5349',
              ['==', ['get', 'sport'], 'archery'], '#5A5349',
              ['==', ['get', 'sport'], 'bowling'], '#5A5349',
              ['==', ['get', 'sport'], 'skateboard'], '#5A5349',
              ['==', ['get', 'sport'], 'skiing'], '#5A5349',
              ['==', ['get', 'sport'], 'curling'], '#5A5349',
              ['==', ['get', 'sport'], 'equestrian'], '#5A5349',
              ['==', ['get', 'sport'], 'australian_football'], '#5A5349',
              ['==', ['get', 'sport'], 'chess'], '#5A5349',
              ['==', ['get', 'sport'], 'gym'], '#5A5349',
              ['==', ['get', 'sport'], 'yoga'], '#5A5349',
              ['has', 'sport'], '#666564',     // Darker gray for other sports (fallback)
              ['==', ['get', 'railway'], 'station'], '#33597F',
              ['==', ['get', 'railway'], 'halt'], '#33597F',
              ['==', ['get', 'railway'], 'tram_stop'], '#33597F',
              ['==', ['get', 'railway'], 'subway_entrance'], '#005326',
              ['==', ['get', 'railway'], 'level_crossing'], '#9A1F1B',
              ['has', 'railway'], '#666564',   // Gray for other railway (fallback)
              ['==', ['get', 'highway'], 'bus_stop'], '#33597F',
              ['==', ['get', 'highway'], 'toll_booth'], '#33597F',
              ['==', ['get', 'highway'], 'speed_camera'], '#000000',
              ['has', 'highway'], '#666564',   // Gray for other highway (fallback)
              ['has', 'power'], '#CC8A99',     // Darker gray for power
              ['==', ['get', 'office'], 'government'], '#5A84A8',
              ['==', ['get', 'office'], 'company'], '#5A84A8',
              ['==', ['get', 'office'], 'lawyer'], '#5A84A8',
              ['==', ['get', 'office'], 'insurance'], '#5A84A8',
              ['==', ['get', 'office'], 'estate_agent'], '#5A84A8',
              ['==', ['get', 'office'], 'travel_agent'], '#7F3F88',
              ['has', 'office'], '#666564',    // Darker gray for other office (fallback)
              ['==', ['get', 'barrier'], 'lift_gate'], '#5A5349',
              ['==', ['get', 'barrier'], 'toll_booth'], '#356AA6',
              ['has', 'barrier'], '#666564',   // Gray for other barrier (fallback)
              ['==', ['get', 'public_transport'], 'station'], '#356AA6',
              ['==', ['get', 'public_transport'], 'stop_position'], '#356AA6',
              ['has', 'public_transport'], '#666564',   // Gray for other public_transport (fallback)
              ['==', ['get', 'emergency'], 'phone'], '#A12819',
              ['==', ['get', 'emergency'], 'fire_hydrant'], '#A12819',
              ['==', ['get', 'emergency'], 'defibrillator'], '#A12819',
              ['==', ['get', 'emergency'], 'assembly_point'], '#A12819',
              ['has', 'emergency'], '#666564',   // Gray for other emergency (fallback)
              ['==', ['get', 'man_made'], 'lighthouse'], '#356AA6',
              ['==', ['get', 'man_made'], 'windmill'], '#356AA6',
              ['==', ['get', 'man_made'], 'tower'], '#54504A',
              ['==', ['get', 'man_made'], 'chimney'], '#54504A',
              ['==', ['get', 'man_made'], 'surveillance'], '#000000',
              ['==', ['get', 'man_made'], 'survey_point'], '#54504A',
              ['has', 'man_made'], '#666564',   // Gray for other man_made (fallback)
              ['==', ['get', 'historic'], 'archaeological_site'], '#5F4226',
              ['==', ['get', 'historic'], 'monument'], '#5F4226',
              ['==', ['get', 'historic'], 'castle'], '#5F4226',
              ['==', ['get', 'historic'], 'ruins'], '#5F4226',
              ['==', ['get', 'historic'], 'memorial'], '#5F4226',
              ['==', ['get', 'historic'], 'statue'], '#5F4226',
              ['==', ['get', 'historic'], 'cross'], '#5F4226',
              ['==', ['get', 'historic'], 'wayside_shrine'], '#5F4226',
              ['==', ['get', 'historic'], 'tomb'], '#5F4226',
              ['==', ['get', 'historic'], 'ship'], '#4F8E8B',
              ['==', ['get', 'historic'], 'cannon'], '#5F4226',
              ['==', ['get', 'historic'], 'tank'], '#5F4226',
              ['==', ['get', 'historic'], 'aircraft'], '#5F4226',
              ['==', ['get', 'historic'], 'locomotive'], '#5F4226',
              ['==', ['get', 'historic'], 'windmill'], '#356AA6',
              ['==', ['get', 'historic'], 'watermill'], '#734087',
              ['==', ['get', 'historic'], 'lighthouse'], '#356AA6',
              ['==', ['get', 'historic'], 'mine'], '#356AA6',
              ['==', ['get', 'historic'], 'wreck'], '#5F4226',
              ['has', 'historic'], '#666564',   // Gray for other historic (fallback)
              ['==', ['get', 'landuse'], 'grass'], '#008038',
              ['==', ['get', 'landuse'], 'forest'], '#008038',
              ['==', ['get', 'landuse'], 'park'], '#008038',
              ['==', ['get', 'landuse'], 'recreation_ground'], '#008038',
              ['==', ['get', 'landuse'], 'village_green'], '#008038',
              ['==', ['get', 'landuse'], 'meadow'], '#008038',
              ['==', ['get', 'landuse'], 'retail'], '#734087',
              ['==', ['get', 'landuse'], 'cemetery'], '#5F4226',
              ['==', ['get', 'landuse'], 'vineyard'], '#734087',
              ['has', 'landuse'], '#666564',   // Gray for other landuse (fallback)
              ['==', ['get', 'craft'], 'brewery'], '#734087',
              ['==', ['get', 'craft'], 'winery'], '#734087',
              ['==', ['get', 'craft'], 'carpenter'], '#734087',
              ['==', ['get', 'craft'], 'electrician'], '#734087',
              ['==', ['get', 'craft'], 'plumber'], '#734087',
              ['==', ['get', 'craft'], 'painter'], '#734087',
              ['==', ['get', 'craft'], 'blacksmith'], '#734087',
              ['==', ['get', 'craft'], 'beekeeper'], '#734087',
              ['==', ['get', 'craft'], 'caterer'], '#734087',
              ['==', ['get', 'craft'], 'key_cutter'], '#734087',
              ['has', 'craft'], '#666564',   // Gray for other craft (fallback)
              ['==', ['get', 'healthcare'], 'audiologist'], '#AA6559',
              ['==', ['get', 'healthcare'], 'optometrist'], '#AA6559',
              ['==', ['get', 'healthcare'], 'physiotherapist'], '#AA6559',
              ['==', ['get', 'healthcare'], 'podiatrist'], '#AA6559',
              ['==', ['get', 'healthcare'], 'psychotherapist'], '#AA6559',
              ['==', ['get', 'healthcare'], 'speech_therapist'], '#AA6559',
              ['==', ['get', 'healthcare'], 'blood_donation'], '#AA6559',
              ['==', ['get', 'healthcare'], 'sample_collection'], '#AA6559',
              ['has', 'healthcare'], '#666564',   // Gray for other healthcare (fallback)
              ['==', ['get', 'natural'], 'beach'], '#008038',
              ['==', ['get', 'natural'], 'cave_entrance'], '#5F4226',
              ['==', ['get', 'natural'], 'volcano'], '#5F4226',
              ['==', ['get', 'natural'], 'waterfall'], '#356AA6',
              ['==', ['get', 'natural'], 'geyser'], '#356AA6',
              ['==', ['get', 'natural'], 'peak'], '#5F4226',
              ['==', ['get', 'natural'], 'spring'], '#356AA6',
              ['has', 'natural'], '#666564',   // Gray for other natural (fallback)
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
        // await _styleController!.addLayer(
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

        await _styleController!.addLayer(
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

            },
          ),
        );
        print('POI layers re-added with comprehensive icon mappings and zoom-based filtering');
      } else {
        // Remove both layers, keep the source
        // await _styleController!.removeLayer('poi-circles');
        await _styleController!.removeLayer('poi-symbols');
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
      final screenLocation = await _mapController!.toScreenLocation(point);
      print('Screen location: ${screenLocation.dx}, ${screenLocation.dy}');

      // Query layers at that location - now returns maps with all properties
      final layers = await _mapController!.queryLayers(screenLocation);
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
    final metadataKeys = {'layerId', 'sourceId', 'sourceLayer', 'latitude', 'longitude'};
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

    // Extract coordinates from POI data if available, otherwise use click point
    final lat = poiData['latitude'] != null
        ? (double.tryParse(poiData['latitude']!) ?? point.lat.toDouble())
        : point.lat.toDouble();
    final lng = poiData['longitude'] != null
        ? (double.tryParse(poiData['longitude']!) ?? point.lng.toDouble())
        : point.lng.toDouble();

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

                    // Coordinates (from POI feature geometry)
                    const Text(
                      '📍 Coordinates:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('Lat: ${lat.toStringAsFixed(6)}°'),
                    Text('Lng: ${lng.toStringAsFixed(6)}°'),

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
      final stopwatch = Stopwatch()..start();

      // Load sprite JSON and PNG
      final spriteJsonData = await rootBundle.loadString(
        'assets/poi/poi-sprite.json',
      );
      final pngData = await rootBundle.load('assets/poi/poi-sprite.png');
      final pngBytes = pngData.buffer.asUint8List();

      print('📦 Sprite assets loaded in ${stopwatch.elapsedMilliseconds}ms');

      // Use native sprite loading - all extraction happens in Kotlin (much faster!)
      final nativeStopwatch = Stopwatch()..start();
      await _styleController!.addSprite(spriteJsonData, pngBytes);

      print('✅ Native sprite loading complete in ${nativeStopwatch.elapsedMilliseconds}ms');
      print('⏱️  Total icon loading time: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stack) {
      print('Error loading icons from sprite: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }
}
