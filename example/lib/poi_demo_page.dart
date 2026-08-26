import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          // Opens at 17, not 14. The category badges below ramp from zero at
          // zoom 14 and only read from about 16, so a page that opened at 14
          // showed none of them -- a demo that hides the thing it is
          // demonstrating. flutter-mapmetrics keeps 14 because it is a
          // navigation app where that is a normal browse zoom; this page
          // exists to show the layers.
          initZoom: 17,
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

      // ==================================================================
      // ONE ICON LAYER, KEYED ON category_group.
      //
      // This replaces two layers that between them could never draw what
      // they promised:
      //
      //   poi-circles  red dot-m markers, the only thing that ever appeared
      //   poi-all      the real icons -- but minZoom 16, while this page
      //                opens at 14, so it was invisible before a single
      //                expression was evaluated
      //
      // Both keyed their icons off raw OSM tags (amenity, shop, leisure,
      // tourism...) via a ~268-entry nested case built from poi-mapping.json.
      // pois-v2-tileserver does not emit those tags. Decoded from a live
      // z14 tile over Amsterdam: `amenity` absent, `category_group` present
      // with values accommodation, eat_and_drink, retail, health_and_medical,
      // education, travel, automotive, financial_service, active_life,
      // attractions_and_activities. So every feature missed every branch and
      // fell through to the `tourism-m` fallback -- which is exactly what
      // "the icons look wrong" looks like.
      //
      // The match below mirrors flutter-mapmetrics
      // (lib/screens/home/services/poi_service.dart), which reads these same
      // tiles and renders them correctly.
      // ==================================================================
      // A coloured disc behind each icon, doubling as a category badge --
      // ported from flutter-mapmetrics (poi_service.dart), same colours and
      // same ramps. ADDED BEFORE THE SYMBOL LAYER so it draws underneath;
      // MapLibre paints in insertion order, and adding it afterwards would
      // hide every icon behind its own badge.
      //
      // Invisible at zoom 14, which is where this page opens: radius, opacity
      // and stroke all interpolate from 0 there, so only the icons read at
      // first sight and the badges fade in as you zoom toward 18. That is the
      // reference's intent, not a bug -- zoom in to see them.
      const circleColorExpression = <Object>[
        'match',
        ['get', 'category_group'],
        'eat_and_drink', '#E89914',
        'health_and_medical', '#9B4F42',
        'financial_service', '#356AA6',
        'public_service_and_government', '#356AA6',
        'education', '#356AA6',
        'religious_organization', '#4F8E8B',
        'retail', '#734087',
        'beauty_and_spa', '#734087',
        'accommodation', '#666564',
        'attractions_and_activities', '#666564',
        'arts_and_entertainment', '#666564',
        'active_life', '#666564',
        'real_estate', '#5A84A8',
        'professional_services', '#5A84A8',
        'private_establishments_and_corporates', '#5A84A8',
        'business_to_business', '#5A84A8',
        'travel', '#33597F',
        'automotive', '#54504A',
        'home_service', '#54504A',
        'structure_and_geography', '#5F4226',
        '#323232', // default
      ];

      await _styleController!.addLayer(
        const CircleStyleLayer(
          id: 'poi-circles',
          sourceId: 'poi-source',
          minZoom: 14,
          maxZoom: 24,
          filter: ['has', 'category_group'],
          layout: {'source-layer': 'pois'},
          paint: {
            'circle-radius': [
              'interpolate',
              ['linear'],
              ['zoom'],
              14, 0,
              16, 1.5,
              18, 3,
              20, 4.5,
            ],
            'circle-color': circleColorExpression,
            'circle-opacity': [
              'interpolate',
              ['linear'],
              ['zoom'],
              14, 0,
              16, 0.25,
              18, 0.7,
            ],
            'circle-stroke-width': [
              'interpolate',
              ['linear'],
              ['zoom'],
              14, 0,
              17, 0.5,
              19, 0.75,
            ],
            'circle-stroke-color': '#FFFFFF',
            'circle-stroke-opacity': [
              'interpolate',
              ['linear'],
              ['zoom'],
              14, 0,
              17, 0.8,
              19, 1.0,
            ],
          },
        ),
      );
      print('POI circle badge layer added');

      const iconImageExpression = <Object>[
        'match',
        ['get', 'category_group'],
        'accommodation', 'hotel-m',
        'active_life', 'fitness_centre-m',
        'arts_and_entertainment', 'theatre-m',
        'attractions_and_activities', 'theme_park-m',
        'automotive', 'car-repair-m',
        'beauty_and_spa', 'beauty-m',
        'business_to_business', 'office-m',
        'eat_and_drink', 'restaurant-m',
        'education', 'school-m',
        'financial_service', 'bank-m',
        'health_and_medical', 'hospital-m',
        'home_service', 'doityourself-m',
        'mass_media', 'newsagent_shop-m',
        'pets', 'petshop-m',
        'private_establishments_and_corporates', 'office-m',
        'professional_services', 'office-m',
        'public_service_and_government', 'public-building-m',
        'real_estate', 'apartment-m',
        'religious_organization', 'place-of-worship-m',
        'retail', 'shop-m',
        'structure_and_geography', 'monument-m',
        'travel', 'information-m',
        'tourism-m', // default
      ];

      // Popular POIs win icon collisions: lowest sort key is placed first and
      // kept when icons overlap, so negating the score puts the best first.
      // richness_score is absent from the tiles decoded above, so coalesce
      // holds every feature at 0 today -- harmless, and it starts working the
      // moment the field ships.
      const popularitySortKey = <Object>[
        '-',
        0,
        ['coalesce', ['get', 'richness_score'], 0],
      ];

      // iOS renders the sprite noticeably larger than Android at the same
      // icon-size, so the two need different numbers to look alike.
      //
      // SCALED FOR THIS REPO'S SPRITE, not copied from flutter-mapmetrics.
      // Its numbers are 1.0/0.4 against a sheet whose icons are 58x58; the
      // sheet here draws them at 31x31. Reusing 0.4 verbatim rendered icons
      // at ~12px next to 11px labels, which is what "icons seem small
      // compared to the text" was. 58/31 = 1.87, so:
      //
      //     Android  1.0 * 1.87 = 1.87
      //     iOS      0.4 * 1.87 = 0.75
      //
      // A size constant is only meaningful next to the sprite it was tuned
      // against; carrying one across sheets is how it silently drifts.
      final iconSize = Platform.isAndroid ? 1.87 : 0.75;

      await _styleController!.addLayer(
        SymbolStyleLayer(
          id: 'poi-icons',
          sourceId: 'poi-source',
          // No minZoom: the source is 10..14 and the renderer overzooms past
          // that, so the layer should draw wherever the source has data.
          maxZoom: 24,
          filter: const ['has', 'category_group'],
          layout: {
            'source-layer': 'pois',
            'icon-image': iconImageExpression,
            'icon-size': iconSize,
            'icon-allow-overlap': false,
            'icon-ignore-placement': false,
            'symbol-sort-key': popularitySortKey,
            // Wider padding at low zoom keeps the map readable on open and
            // tightens as the user zooms in and wants density.
            'icon-padding': [
              'interpolate',
              ['linear'],
              ['zoom'],
              14, 40,
              16, 25,
              18, 12,
              20, 6,
            ],
            'text-field': ['coalesce', ['get', 'name'], ''],
            // ONE entry. A multi-font stack is requested as a single
            // comma-joined path that the glyph endpoint does not serve.
            'text-font': ['Noto Sans Regular'],
            // Zoom-interpolated, as in flutter-mapmetrics. A flat 11 was
            // oversized at the zoom this page opens at: the reference clamps
            // to 9 below z16, and 11px labels beside 12px icons is what made
            // the icons look like an afterthought.
            'text-size': [
              'interpolate',
              ['linear'],
              ['zoom'],
              16, 9,
              18, 11,
              20, 13,
              22, 14,
            ],
            'text-anchor': 'top',
            'text-offset': [0, 1.2],
            'text-optional': true,
          },
          paint: {
            'text-color': '#323232',
            'text-halo-color': '#FFFFFF',
            'text-halo-width': 1.5,
          },
        ),
      );
      print('POI icon layer added (category_group -> sprite)');
    } catch (e, stack) {
      print('Error setting up POI layer: $e');
      print('Stack trace: $stack');
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
            // The one layer this page now adds. This used to list
            // poi-circles / poi-airports / poi-priority / poi-all: the first
            // was the red-dot layer, the other three were never added at all
            // (two are still commented out below), so long-press could only
            // ever hit a dot.
            return layerId == 'poi-icons';
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
