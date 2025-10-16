/// **Use your own key for your project!**
///
/// This key will be rotated occasionally.
abstract class MapStyles {
  static const protomapsLight =
      'https://api.protomaps.com/styles/v2/light.json?key=$_protomapsKey';
  static const protomapsDark =
      'https://api.protomaps.com/styles/v2/dark.json?key=$_protomapsKey';
  static const maptilerStreets =
      'https://api.maptiler.com/maps/streets-v2/style.json?key=$_maptilerKey';

  static const _maptilerKey = 'OPCgnZ51sHETbEQ4wnkd';
  static const _protomapsKey = 'a6f9aebb3965458c';

  static const token =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI4MjQ5NGNjNy04YTUzLTQwNGUtODNlOS1hZjA5OWY1MGE0Y2IiLCJzY29wZSI6WyJtYXBzIiwic2VhcmNoIl0sImlhdCI6MTc0NDY5NTgxOH0.3oDQzbcD72gIvtd4lkKi96aMFF3-d-i7UnIdc9iADeA';
  static const testMap =
      'https://gateway.mapmetrics.org/styles/?fileName=82494cc7-8a53-404e-83e9-af099f50a4cb/testMap.json&token=$token';
}
