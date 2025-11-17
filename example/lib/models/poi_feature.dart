import 'package:flutter/material.dart';
import 'package:vector_tile/vector_tile.dart';

/// POI Feature Data Model
/// Supports both MVT tile data and reverse geocoding API data
class PoiFeature {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final double distance;
  final String? amenity;
  final String? shop;
  final String? highway;
  final String? tourism;
  final String? toilets;
  final String? street;
  final String? housenumber;
  final String? postcode;
  final String? city;
  final String? phone;
  final String? website;
  final String? openingHours;
  final String? cuisine;
  final String? wheelchair;

  PoiFeature({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.distance,
    this.amenity,
    this.shop,
    this.highway,
    this.tourism,
    this.toilets,
    this.street,
    this.housenumber,
    this.postcode,
    this.city,
    this.phone,
    this.website,
    this.openingHours,
    this.cuisine,
    this.wheelchair,
  });

  /// Helper to extract string value from VectorTileValue or dynamic
  static String? _extractString(dynamic value) {
    if (value == null) return null;
    if (value is VectorTileValue) {
      // Debug logging
      print('DEBUG: VectorTileValue type: ${value.type}, value: ${value.value}, runtimeType: ${value.value.runtimeType}');

      // Try direct getters first (these should work)
      if (value.stringValue != null) return value.stringValue;
      if (value.intValue != null) return value.intValue.toString();
      if (value.uintValue != null) return value.uintValue.toString();
      if (value.sintValue != null) return value.sintValue.toString();
      if (value.floatValue != null) return value.floatValue.toString();
      if (value.doubleValue != null) return value.doubleValue.toString();
      if (value.boolValue != null) return value.boolValue.toString();

      // Last resort - try to extract value directly
      try {
        final v = value.value;
        if (v != null) {
          // Check if it's Int64 (from fixnum package)
          if (v.runtimeType.toString().contains('Int64')) {
            return v.toString();
          }
          return v.toString();
        }
      } catch (e) {
        print('DEBUG: Error extracting value: $e');
      }

      return null;
    }
    return value.toString();
  }

  /// Create from MVT tile feature properties
  factory PoiFeature.fromMvt({
    required Map<String, dynamic> properties,
    required double lat,
    required double lon,
    required double distance,
  }) {
    final propId = _extractString(properties['id']);
    final fallbackId = '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';
    return PoiFeature(
      id: (propId == null || propId.isEmpty) ? fallbackId : propId,
      name: _extractString(properties['name']) ?? 'Unknown',
      lat: lat,
      lon: lon,
      distance: distance,
      amenity: _extractString(properties['amenity']),
      shop: _extractString(properties['shop']),
      highway: _extractString(properties['highway']),
      tourism: _extractString(properties['tourism']),
      toilets: _extractString(properties['toilets']),
      street: _extractString(properties['addr:street']),
      housenumber: _extractString(properties['addr:housenumber']),
      postcode: _extractString(properties['addr:postcode']),
      city: _extractString(properties['addr:city']),
      phone: _extractString(properties['phone']) ?? _extractString(properties['contact:phone']),
      website: _extractString(properties['website']) ?? _extractString(properties['contact:website']),
      openingHours: _extractString(properties['opening_hours']),
      cuisine: _extractString(properties['cuisine']),
      wheelchair: _extractString(properties['wheelchair']),
    );
  }

  /// Create from reverse geocoding API response
  factory PoiFeature.fromGeocodingApi(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>? ?? {};
    final geometry = json['geometry'] as Map<String, dynamic>? ?? {};
    final coordinates = geometry['coordinates'] as List<dynamic>? ?? [0.0, 0.0];
    final addendum = properties['addendum'] as Map<String, dynamic>?;
    final osm = addendum?['osm'] as Map<String, dynamic>?;

    return PoiFeature(
      id: properties['id']?.toString() ?? '',
      name: properties['name']?.toString() ?? 'Unknown',
      lat: coordinates.length > 1 ? (coordinates[1] as num).toDouble() : 0.0,
      lon: coordinates.length > 0 ? (coordinates[0] as num).toDouble() : 0.0,
      distance: (properties['distance'] as num?)?.toDouble() ?? 0.0,
      amenity: osm?['amenity']?.toString(),
      shop: osm?['shop']?.toString(),
      highway: osm?['highway']?.toString(),
      tourism: osm?['tourism']?.toString(),
      toilets: osm?['toilets']?.toString(),
      street: properties['street']?.toString(),
      housenumber: properties['housenumber']?.toString(),
      postcode: properties['postalcode']?.toString(),
      city: properties['locality']?.toString(),
      phone: properties['phone']?.toString() ?? osm?['phone']?.toString(),
      website: properties['website']?.toString() ?? osm?['website']?.toString(),
      openingHours: osm?['opening_hours']?.toString(),
      cuisine: osm?['cuisine']?.toString(),
      wheelchair: osm?['wheelchair']?.toString(),
    );
  }

  /// Get display type for the POI
  String get displayType {
    if (amenity != null) return amenity!.replaceAll('_', ' ').toUpperCase();
    if (shop != null) return shop!.replaceAll('_', ' ').toUpperCase();
    if (highway != null) return highway!.replaceAll('_', ' ').toUpperCase();
    if (tourism != null) return tourism!.replaceAll('_', ' ').toUpperCase();
    return 'VENUE';
  }

  /// Get formatted address
  String? get formattedAddress {
    final parts = <String>[];
    if (street != null) {
      parts.add('${housenumber ?? ''} $street'.trim());
    }
    if (city != null) {
      parts.add('${postcode ?? ''} $city'.trim());
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Get distance in readable format
  String get formattedDistance {
    if (distance < 0.1) {
      return '${(distance * 1000).toStringAsFixed(0)}m';
    } else {
      return '${distance.toStringAsFixed(2)}km';
    }
  }

  /// Get icon for POI type
  IconData get icon {
    if (amenity == 'toilets') return Icons.wc;
    if (amenity == 'restaurant') return Icons.restaurant;
    if (amenity == 'cafe') return Icons.local_cafe;
    if (amenity == 'bar' || amenity == 'pub') return Icons.local_bar;
    if (amenity == 'fuel') return Icons.local_gas_station;
    if (tourism == 'hotel' || tourism == 'motel' || tourism == 'hostel' || tourism == 'guest_house') {
      return Icons.hotel;
    }
    if (shop == 'mall' || shop == 'department_store') return Icons.local_mall;
    if (shop != null) return Icons.shopping_bag;
    return Icons.place;
  }
}
