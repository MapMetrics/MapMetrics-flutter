import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Configuration for POI rendering loaded from CDN
class POIRendererConfig {
  const POIRendererConfig({
    required this.skipPatterns,
    required this.fallbackSprite,
    required this.mappings,
    required this.popupConfig,
    required this.iconConfig,
  });

  final List<String> skipPatterns;
  final String fallbackSprite;
  final Map<String, dynamic> mappings;
  final PopupConfig popupConfig;
  final IconConfig iconConfig;

  factory POIRendererConfig.fromJson(Map<String, dynamic> json) {
    final skipPatterns = json['skipPatterns'];
    final mappings = json['mappings'];

    return POIRendererConfig(
      skipPatterns: skipPatterns is List ? List<String>.from(skipPatterns) : <String>[],
      fallbackSprite: json['fallbackSprite'] as String? ?? 'tourism-m',
      mappings: mappings is Map ? Map<String, dynamic>.from(mappings) : <String, dynamic>{},
      popupConfig: PopupConfig.fromJson(
        json['popupConfig'] as Map<String, dynamic>? ?? {},
      ),
      iconConfig: IconConfig.fromJson(
        json['iconConfig'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  /// Get icon name for a POI based on its properties
  String? getIconName(Map<String, dynamic> properties) {
    // Check each category in the mappings
    for (final entry in mappings.entries) {
      final category = entry.key;
      final categoryMappings = entry.value as Map<String, dynamic>?;

      if (categoryMappings == null) continue;

      // Check if the POI has this category
      final categoryValue = properties[category];
      if (categoryValue == null) continue;

      // Look up the icon in the category mappings
      final mapping = categoryMappings[categoryValue];

      if (mapping is String) {
        return mapping;
      } else if (mapping is Map<String, dynamic>) {
        // Handle special cases like religion-based icons
        if (mapping.containsKey('religion')) {
          final religionMappings =
              mapping['religion'] as Map<String, dynamic>?;
          if (religionMappings != null) {
            final religion = properties['religion'] as String?;
            if (religion != null && religionMappings.containsKey(religion)) {
              return religionMappings[religion] as String?;
            }
          }
        }
        // Return default for this mapping
        return mapping['default'] as String?;
      }
    }

    return fallbackSprite;
  }

  /// Build MapLibre expression for dynamic icon selection
  /// Returns a ['case', ...conditions, fallback] expression array
  /// that can be used as the 'icon-image' property in a SymbolStyleLayer
  List<dynamic> buildIconExpression() {
    final expression = <dynamic>['case'];

    // Iterate through each category in mappings
    for (final categoryEntry in mappings.entries) {
      final category = categoryEntry.key;
      final categoryMappings = categoryEntry.value as Map<String, dynamic>?;

      if (categoryMappings == null) continue;

      // Iterate through each mapping in this category
      for (final mappingEntry in categoryMappings.entries) {
        final key = mappingEntry.key;
        final value = mappingEntry.value;

        if (value is String) {
          // Simple mapping: category == key -> icon name
          expression.addAll([
            ['==', ['get', category], key],
            value,
          ]);
        } else if (value is Map<String, dynamic>) {
          // Complex mapping with religion-based or other conditional logic
          if (value.containsKey('religion')) {
            final religionMappings = value['religion'] as Map<String, dynamic>?;
            if (religionMappings != null) {
              // Handle each religion variant
              for (final religionEntry in religionMappings.entries) {
                final religion = religionEntry.key;
                final iconName = religionEntry.value as String;

                // Condition: category == key AND religion == specific religion
                expression.addAll([
                  ['all',
                    ['==', ['get', category], key],
                    ['==', ['get', 'religion'], religion],
                  ],
                  iconName,
                ]);
              }
            }
          }

          // If there's a default for this complex mapping
          if (value.containsKey('default')) {
            final defaultIcon = value['default'] as String;
            expression.addAll([
              ['==', ['get', category], key],
              defaultIcon,
            ]);
          }
        }
      }
    }

    // Add fallback icon at the end
    expression.add(fallbackSprite);

    return expression;
  }

  /// Build iOS-compatible MapLibre expression for dynamic icon selection
  /// iOS can't handle complex nested ['all', ...] expressions, so we flatten them
  /// Returns a ['case', ...conditions, fallback] expression array
  List<dynamic> buildIconExpressionIOS() {
    final expression = <dynamic>['case'];

    // Iterate through each category in mappings
    for (final categoryEntry in mappings.entries) {
      final category = categoryEntry.key;
      final categoryMappings = categoryEntry.value as Map<String, dynamic>?;

      if (categoryMappings == null) continue;

      // Iterate through each mapping in this category
      for (final mappingEntry in categoryMappings.entries) {
        final key = mappingEntry.key;
        final value = mappingEntry.value;

        if (value is String) {
          // Simple mapping: category == key -> icon name
          expression.addAll([
            <dynamic>['==', <dynamic>['get', category], key],
            value,
          ]);
        } else if (value is Map<String, dynamic>) {
          // For iOS, skip complex religion-based mappings and use default
          // iOS can't handle nested ['all', ...] expressions well
          if (value.containsKey('default')) {
            final defaultIcon = value['default'] as String;
            expression.addAll([
              <dynamic>['==', <dynamic>['get', category], key],
              defaultIcon,
            ]);
          }
        }
      }
    }

    // Add fallback icon at the end
    expression.add(fallbackSprite);

    return expression;
  }
}

/// Configuration for POI popups
class PopupConfig {
  const PopupConfig({
    required this.maxWidth,
    required this.displayedKeys,
  });

  final String maxWidth;
  final List<String> displayedKeys;

  factory PopupConfig.fromJson(Map<String, dynamic> json) {
    final displayedKeys = json['displayedKeys'];

    return PopupConfig(
      maxWidth: json['maxWidth'] as String? ?? '320px',
      displayedKeys: displayedKeys is List ? List<String>.from(displayedKeys) : <String>[],
    );
  }
}

/// Configuration for POI icons
class IconConfig {
  const IconConfig({
    required this.sizeStops,
    required this.allowOverlap,
  });

  final List<List<num>> sizeStops;
  final AllowOverlapConfig allowOverlap;

  factory IconConfig.fromJson(Map<String, dynamic> json) {
    final sizeStopsRaw = json['sizeStops'] as List? ?? [];
    final sizeStops = sizeStopsRaw
        .map((e) => (e as List).map((n) => n as num).toList())
        .toList();

    return IconConfig(
      sizeStops: sizeStops,
      allowOverlap: AllowOverlapConfig.fromJson(
        json['allowOverlap'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  /// Get icon size for a given zoom level
  double getIconSize(double zoom) {
    if (sizeStops.isEmpty) return 1.0;

    // Find the appropriate size stops
    for (var i = 0; i < sizeStops.length - 1; i++) {
      final currentStop = sizeStops[i];
      final nextStop = sizeStops[i + 1];

      final currentZoom = currentStop[0].toDouble();
      final nextZoom = nextStop[0].toDouble();

      if (zoom >= currentZoom && zoom < nextZoom) {
        // Interpolate between stops
        final currentSize = currentStop[1].toDouble();
        final nextSize = nextStop[1].toDouble();
        final ratio = (zoom - currentZoom) / (nextZoom - currentZoom);
        return currentSize + (nextSize - currentSize) * ratio;
      }
    }

    // If zoom is beyond last stop, use last size
    if (zoom >= sizeStops.last[0].toDouble()) {
      return sizeStops.last[1].toDouble();
    }

    // If zoom is before first stop, use first size
    return sizeStops.first[1].toDouble();
  }

  /// Convert to MapLibre icon-size expression
  List<dynamic> toIconSizeExpression() {
    final List<dynamic> result = ['interpolate', ['linear'], ['zoom']];

    // Add all size stops as [zoom, size] pairs
    for (final stop in sizeStops) {
      result.add(stop[0]);
      result.add(stop[1]);
    }

    return result;
  }
}

/// Configuration for icon overlap behavior
class AllowOverlapConfig {
  const AllowOverlapConfig({
    required this.zoomThreshold,
    required this.ignorePlacement,
  });

  final int zoomThreshold;
  final bool ignorePlacement;

  factory AllowOverlapConfig.fromJson(Map<String, dynamic> json) {
    return AllowOverlapConfig(
      zoomThreshold: json['zoomThreshold'] as int? ?? 16,
      ignorePlacement: json['ignorePlacement'] as bool? ?? true,
    );
  }
}

/// Service to load POI configuration from CDN
class POIConfigLoader {
  static const String configUrl =
      'https://cdn.mapmetrics-atlas.net/Images/poi-config.json';

  /// Load POI configuration from CDN
  static Future<POIRendererConfig> loadConfig() async {
    try {
      final response = await http.get(Uri.parse(configUrl));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return POIRendererConfig.fromJson(json);
      } else {
        debugPrint(
          'Failed to load POI config: ${response.statusCode}',
        );
        throw Exception('Failed to load POI config: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error loading POI config: $e');
      rethrow;
    }
  }
}
