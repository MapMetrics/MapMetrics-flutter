import 'package:mapmetrics/mapmetrics.dart';

/// Represents a Point of Interest with all relevant metadata
class POI {
  const POI({
    required this.id,
    required this.name,
    required this.coordinates,
    this.type,
    this.category,
    this.description,
    this.address,
    this.phone,
    this.website,
    this.email,
    this.openingHours,
    this.wheelchair,
    this.parking,
    this.toilets,
    this.fee,
    this.access,
    this.properties = const {},
  });

  final String id;
  final String name;
  final Position coordinates;
  final String? type;
  final String? category;
  final String? description;
  final String? address;
  final String? phone;
  final String? website;
  final String? email;
  final String? openingHours;
  final String? wheelchair;
  final String? parking;
  final String? toilets;
  final String? fee;
  final String? access;
  final Map<String, dynamic> properties;

  /// Convert POI to GeoJSON Feature
  Map<String, dynamic> toGeoJson() {
    return {
      'type': 'Feature',
      'id': id,
      'geometry': {
        'type': 'Point',
        'coordinates': [coordinates.lng, coordinates.lat],
      },
      'properties': {
        'name': name,
        if (type != null) 'type': type,
        if (category != null) 'category': category,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (website != null) 'website': website,
        if (email != null) 'email': email,
        if (openingHours != null) 'opening_hours': openingHours,
        if (wheelchair != null) 'wheelchair': wheelchair,
        if (parking != null) 'parking': parking,
        if (toilets != null) 'toilets': toilets,
        if (fee != null) 'fee': fee,
        if (access != null) 'access': access,
        ...properties,
      },
    };
  }

  /// Create POI from GeoJSON Feature
  factory POI.fromGeoJson(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List;
    final properties = feature['properties'] as Map<String, dynamic>? ?? {};

    return POI(
      id: feature['id']?.toString() ?? properties['id']?.toString() ?? '',
      name: properties['name']?.toString() ?? '',
      coordinates: Position(coordinates[0] as num, coordinates[1] as num),
      type: properties['type']?.toString(),
      category: properties['category']?.toString(),
      description: properties['description']?.toString(),
      address: properties['address']?.toString(),
      phone: properties['phone']?.toString(),
      website: properties['website']?.toString(),
      email: properties['email']?.toString(),
      openingHours: properties['opening_hours']?.toString(),
      wheelchair: properties['wheelchair']?.toString(),
      parking: properties['parking']?.toString(),
      toilets: properties['toilets']?.toString(),
      fee: properties['fee']?.toString(),
      access: properties['access']?.toString(),
      properties: properties,
    );
  }
}

/// Configuration for POI rendering
class POIConfig {
  const POIConfig({
    required this.mappings,
    required this.fallbackSprite,
    this.skipPrefixes = const [],
    this.minZoom = 10,
    this.maxZoom = 16,
    this.iconSizeByZoom = const {
      10: 0.3,
      12: 0.5,
      14: 0.7,
      16: 1.0,
    },
    this.allowOverlapZoom = 14,
  });

  final Map<String, Map<String, String>> mappings;
  final String fallbackSprite;
  final List<String> skipPrefixes;
  final int minZoom;
  final int maxZoom;
  final Map<int, double> iconSizeByZoom;
  final int allowOverlapZoom;

  /// Get icon name for a POI type and category
  String? getIconName(String? category, String? type) {
    if (category == null || type == null) return null;

    // Check if type should be skipped
    for (final prefix in skipPrefixes) {
      if (type.startsWith(prefix)) return null;
    }

    // Look up icon in mappings
    final categoryMap = mappings[category.toLowerCase()];
    return categoryMap?[type.toLowerCase()];
  }

  /// Get icon size for a zoom level
  double getIconSize(double zoom) {
    // Find the closest zoom level in the map
    int? lowerZoom;
    int? upperZoom;

    for (final z in iconSizeByZoom.keys) {
      if (z <= zoom) {
        if (lowerZoom == null || z > lowerZoom) {
          lowerZoom = z;
        }
      }
      if (z >= zoom) {
        if (upperZoom == null || z < upperZoom) {
          upperZoom = z;
        }
      }
    }

    if (lowerZoom == null) return iconSizeByZoom.values.first;
    if (upperZoom == null) return iconSizeByZoom.values.last;
    if (lowerZoom == upperZoom) return iconSizeByZoom[lowerZoom]!;

    // Interpolate between zoom levels
    final lowerSize = iconSizeByZoom[lowerZoom]!;
    final upperSize = iconSizeByZoom[upperZoom]!;
    final ratio = (zoom - lowerZoom) / (upperZoom - lowerZoom);
    return lowerSize + (upperSize - lowerSize) * ratio;
  }

  /// Check if icons should overlap at this zoom level
  bool shouldAllowOverlap(double zoom) {
    return zoom >= allowOverlapZoom;
  }

  /// Create default POI configuration
  factory POIConfig.defaultConfig() {
    return POIConfig(
      mappings: {
        'amenity': {
          'restaurant': 'restaurant-m',
          'cafe': 'cafe-m',
          'bar': 'bar-m',
          'pub': 'bar-m',
          'fast_food': 'fast-food-m',
          'bank': 'bank-m',
          'atm': 'atm-m',
          'pharmacy': 'pharmacy-m',
          'hospital': 'hospital-m',
          'police': 'police-m',
          'fire_station': 'fire-station-m',
          'post_office': 'post-m',
          'library': 'library-m',
          'school': 'school-m',
          'university': 'college-m',
          'parking': 'parking-m',
          'fuel': 'fuel-m',
          'charging_station': 'charging-station-m',
          'toilets': 'toilet-m',
          'place_of_worship': 'place-of-worship-m',
        },
        'shop': {
          'supermarket': 'grocery-m',
          'convenience': 'convenience-m',
          'bakery': 'bakery-m',
          'clothes': 'clothing-store-m',
          'hairdresser': 'hairdresser-m',
          'bicycle': 'bicycle-m',
          'car': 'car-m',
          'mobile_phone': 'mobile-phone-m',
          'electronics': 'electronics-m',
          'furniture': 'furniture-m',
          'hardware': 'hardware-m',
          'florist': 'florist-m',
          'shoes': 'shoe-m',
          'sports': 'sports-m',
          'alcohol': 'alcohol-shop-m',
          'gift': 'gift-m',
          'jewelry': 'jewelry-store-m',
          'pet': 'pet-m',
        },
        'tourism': {
          'hotel': 'lodging-m',
          'motel': 'lodging-m',
          'hostel': 'lodging-m',
          'museum': 'museum-m',
          'gallery': 'art-gallery-m',
          'attraction': 'attraction-m',
          'viewpoint': 'attraction-m',
          'zoo': 'zoo-m',
          'theme_park': 'amusement-park-m',
          'information': 'information-m',
          'camp_site': 'campsite-m',
        },
        'leisure': {
          'park': 'park-m',
          'playground': 'playground-m',
          'sports_centre': 'sports-m',
          'stadium': 'stadium-m',
          'swimming_pool': 'swimming-m',
          'fitness_centre': 'fitness-m',
          'garden': 'garden-m',
          'golf_course': 'golf-m',
        },
        'sport': {
          'soccer': 'soccer-m',
          'tennis': 'tennis-m',
          'basketball': 'basketball-m',
          'baseball': 'baseball-m',
          'swimming': 'swimming-m',
          'golf': 'golf-m',
        },
      },
      fallbackSprite: 'marker-m',
      skipPrefixes: ['addr:', 'source:', 'attribution:'],
      minZoom: 10,
      maxZoom: 18,
    );
  }
}
