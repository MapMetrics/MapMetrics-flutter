import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/cupertino.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'package:mapmetrics/src/platform/maplibre_ffi.dart';
import 'package:objective_c/objective_c.dart';

/// Internal extensions on [CLLocationCoordinate2D].
extension CLLocationCoordinate2DExt on CLLocationCoordinate2D {
  /// Convert a [CLLocationCoordinate2D] to [Position].
  Position toPosition() => Position(longitude, latitude);
}

/// Internal extensions on [Position].
extension PositionExt on Position {
  /// Convert a [Position] to a [CLLocationCoordinate2D].
  CLLocationCoordinate2D toCLLocationCoordinate2D() {
    final coords = Struct.create<CLLocationCoordinate2D>();
    coords.latitude = lat.toDouble();
    coords.longitude = lng.toDouble();
    return coords;
  }
}

/// Internal extensions on [Offset].
extension OffsetExt on Offset {
  /// Convert a [Position] to a [CGPoint].
  CGPoint toCGPoint() {
    final point = Struct.create<CGPoint>();
    point.x = dx;
    point.y = dy;
    return point;
  }
}

/// Internal extensions on [LngLatBounds].
extension LngLatBoundsExt on LngLatBounds {
  /// Convert a [LngLatBounds] to a [CGPoint].
  MLNCoordinateBounds toMLNCoordinateBounds() {
    final bounds = Struct.create<MLNCoordinateBounds>();
    bounds.sw =
        Struct.create<CLLocationCoordinate2D>()
          ..longitude = longitudeWest
          ..latitude = latitudeSouth;
    bounds.ne =
        Struct.create<CLLocationCoordinate2D>()
          ..longitude = longitudeEast
          ..latitude = latitudeNorth;
    return bounds;
  }
}

/// Internal extensions on [MLNCoordinateBounds].
extension MLNCoordinateBoundsExt on MLNCoordinateBounds {
  /// Convert a [MLNCoordinateBounds] to a [LngLatBounds].
  LngLatBounds toLngLatBounds() => LngLatBounds(
    longitudeWest: sw.longitude,
    longitudeEast: ne.longitude,
    latitudeSouth: sw.latitude,
    latitudeNorth: ne.latitude,
  );
}

/// Internal extensions on [CGPoint].
extension CGPointExt on CGPoint {
  /// Convert a [CGPoint] to a [Offset].
  Offset toOffset() => Offset(x, y);
}

/// Internal extensions on [String].
extension StringExt on String {
  /// Convert to a [NSURL].
  NSURL? toNSURL() => NSURL.URLWithString_(toNSString());

  /// Convert to a [NSURL].
  NSData? toNSDataUTF8() =>
      toNSString().dataUsingEncoding_(nsUTF8StringEncoding);

  /// Convert a dashed separated name to camel case.
  String dashedToCamelCase() =>
      split('-').indexed.map((entry) {
        final index = entry.$1;
        final word = entry.$2;
        // Keep the first word in lowercase
        if (index == 0) return word;
        return word[0].toUpperCase() + word.substring(1);
      }).join();
}

/// Convert a raw String to a [NSExpression].
NSExpression? parseNSExpression(String propertyName, String json) =>
    Helpers.parseExpressionWithPropertyName_expression_(
      propertyName.toNSString(),
      json.toNSString(),
    );

/// Create a simple expression from a complex one for iOS compatibility
/// iOS has limitations with nested case expressions, so we simplify to get/literal
NSExpression? _createSimpleExpression(List<dynamic> expression, String propertyName) {
  // Handle ['literal', value] expressions
  if (expression.length == 2 && expression[0] == 'literal') {
    return NSExpression.expressionForConstantValue_(expression[1].toNSObject());
  }

  // Handle ['get', 'propertyName'] expressions
  if (expression.length == 2 && expression[0] == 'get' && expression[1] is String) {
    return NSExpression.expressionForKeyPath_((expression[1] as String).toNSString());
  }

  // For complex case expressions, try to extract a reasonable fallback
  // The last element in a case expression is typically the fallback
  if (expression.isNotEmpty && expression[0] == 'case') {
    // Try to find the last string value as fallback
    for (var i = expression.length - 1; i >= 0; i--) {
      if (expression[i] is String && expression[i] != 'case') {
        debugPrint('  Using fallback icon from case expression: ${expression[i]}');
        return NSExpression.expressionForConstantValue_((expression[i] as String).toNSString());
      }
    }
  }

  // For icon-image, use a reasonable default
  if (propertyName == 'icon-image') {
    debugPrint('  Using default icon: tourism-m');
    return NSExpression.expressionForConstantValue_('tourism-m'.toNSString());
  }

  return null;
}

/// Internal extensions on [MLNStyleLayer].
extension MLNStyleLayerExt on MLNStyleLayer {
  /// Apply all paint or layout properties on the [MLNStyleLayer].
  void setProperties(Map<String, Object> properties) {
    for (final property in properties.entries) {
      // print('${property.key}   ${jsonEncode(property.value)}');
      switch (property.key) {
        case 'visibility':
          visible = property.value == 'none';
        default:
          setProperty(property.key, property.value);
      }
    }
  }

  /// Set a layout or paint property for a [MLNStyleLayer].
  void setProperty(String key, Object value) {
    // convert to a String
    var rawValue = switch (value) {
      List() || Map() => jsonEncode(value),
      String() => value,
      _ => value.toString(),
    };
    // convert html color names to hex strings
    if (key.contains('color')) {
      rawValue = htmlColorNames[rawValue] ?? rawValue;
    }
    final NSExpression? expression;
    try {
      expression = parseNSExpression(key, rawValue);
    } catch (error, stacktrace) {
      // iOS has limitations with complex expressions
      // If parsing fails, try to extract a simple 'get' expression or fallback value
      debugPrint('⚠️ iOS expression parsing failed for "$key": $error');

      if (value is List) {
        // Try to create a simple expression from the complex one
        final simpleExpr = _createSimpleExpression(value as List, key);
        if (simpleExpr != null) {
          debugPrint('✅ iOS: Using simplified expression for "$key"');
          _applyExpression(this, key, simpleExpr);
          return;
        }
      }

      debugPrint('⚠️ iOS: Skipping property "$key" due to unsupported expression');
      return;
    }
    // print('${expression?.description1 ?? 'no expression!'}');
    if (expression == null) return;

    _applyExpression(this, key, expression);
  }

  /// Apply an NSExpression to a layer property
  void _applyExpression(MLNStyleLayer layer, String key, NSExpression expression) {
    // Handle source-layer property (vector tile layer selection)
    if (key == 'source-layer') {
      // source-layer needs to be set on the vector source layer types
      if (MLNVectorStyleLayer.isInstance(layer)) {
        final vectorLayer = MLNVectorStyleLayer.castFrom(layer);
        // Extract the string value from the expression
        // expressionType 0 = NSConstantValueExpressionType
        try {
          final value = expression.constantValue;
          if (value != null) {
            if (NSString.isInstance(value)) {
              final stringValue = NSString.castFrom(value);
              vectorLayer.sourceLayerIdentifier = stringValue;
              debugPrint('✅ iOS: Set source-layer to: ${stringValue.toDartString()}');
              return;
            } else {
              debugPrint('⚠️ iOS: source-layer value is not an NSString: ${value.runtimeType}');
            }
          } else {
            debugPrint('⚠️ iOS: source-layer constantValue is null');
          }
        } catch (e) {
          debugPrint('⚠️ iOS: Error extracting source-layer value: $e');
        }
      } else {
        debugPrint('⚠️ iOS: Layer is not a vector style layer: ${layer.runtimeType}');
      }
      debugPrint('⚠️ iOS: Could not set source-layer property');
      return;
    }

    // some variables have a different name in ios than in the style spec
    // https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre-native-for-ios/for_style_authors#Configuring-the-map-contents-appearance
    switch (key) {
      // Circle layer properties
      case 'circle-radius':
        (this as MLNCircleStyleLayer).circleRadius = expression;
      case 'circle-color':
        (this as MLNCircleStyleLayer).circleColor = expression;
      case 'circle-opacity':
        (this as MLNCircleStyleLayer).circleOpacity = expression;
      case 'circle-stroke-width':
        (this as MLNCircleStyleLayer).circleStrokeWidth = expression;
      case 'circle-stroke-color':
        (this as MLNCircleStyleLayer).circleStrokeColor = expression;
      case 'circle-stroke-opacity':
        (this as MLNCircleStyleLayer).circleStrokeOpacity = expression;
      case 'circle-blur':
        (this as MLNCircleStyleLayer).circleBlur = expression;
      case 'circle-pitch-scale':
        (this as MLNCircleStyleLayer).circleScaleAlignment = expression;
      case 'circle-translate':
        (this as MLNCircleStyleLayer).circleTranslation = expression;
      case 'circle-translate-anchor':
        (this as MLNCircleStyleLayer).circleTranslateAnchor = expression;
      case 'fill-antialias':
        (this as MLNFillStyleLayer).fillAntialiased = expression;
      case 'fill-translate':
        (this as MLNFillStyleLayer).fillTranslation = expression;
      case 'fill-translate-anchor':
        (this as MLNFillStyleLayer).fillTranslationAnchor = expression;
      case 'fill-extrusion-vertical-gradient':
        (this as MLNFillExtrusionStyleLayer).fillExtrusionHasVerticalGradient =
            expression;
      case 'fill-extrusion-translate':
        (this as MLNFillExtrusionStyleLayer).fillExtrusionTranslation =
            expression;
      case 'fill-extrusion-translate-anchor':
        (this as MLNFillExtrusionStyleLayer).fillExtrusionTranslationAnchor =
            expression;
      case 'line-dasharray':
        (this as MLNLineStyleLayer).lineDashPattern = expression;
      case 'line-translate':
        (this as MLNLineStyleLayer).lineTranslation = expression;
      case 'line-translate-anchor':
        (this as MLNLineStyleLayer).lineTranslationAnchor = expression;
      case 'raster-brightness-max':
        (this as MLNRasterStyleLayer).maximumRasterBrightness = expression;
      case 'raster-brightness-min':
        (this as MLNRasterStyleLayer).minimumRasterBrightness = expression;
      case 'raster-hue-rotate':
        (this as MLNRasterStyleLayer).rasterHueRotation = expression;
      case 'raster-resampling':
        (this as MLNRasterStyleLayer).rasterResamplingMode = expression;
      case 'icon-allow-overlap':
        (this as MLNSymbolStyleLayer).iconAllowsOverlap = expression;
      case 'icon-ignore-placement':
        (this as MLNSymbolStyleLayer).iconIgnoresPlacement = expression;
      case 'icon-image':
        (this as MLNSymbolStyleLayer).iconImageName = expression;
      case 'icon-optional':
        (this as MLNSymbolStyleLayer).iconOptional = expression;
      case 'icon-rotate':
        (this as MLNSymbolStyleLayer).iconRotation = expression;
      case 'icon-size':
        (this as MLNSymbolStyleLayer).iconScale = expression;
      case 'icon-keep-upright':
        (this as MLNSymbolStyleLayer).keepsIconUpright = expression;
      case 'text-keep-upright':
        (this as MLNSymbolStyleLayer).keepsTextUpright = expression;
      case 'text-max-angle':
        (this as MLNSymbolStyleLayer).maximumTextAngle = expression;
      case 'text-max-width':
        (this as MLNSymbolStyleLayer).maximumTextWidth = expression;
      case 'symbol-avoid-edges':
        (this as MLNSymbolStyleLayer).symbolAvoidsEdges = expression;
      case 'text-field':
        (this as MLNSymbolStyleLayer).text = expression;
      case 'text-allow-overlap':
        (this as MLNSymbolStyleLayer).textAllowsOverlap = expression;
      case 'text-font':
        (this as MLNSymbolStyleLayer).textFontNames = expression;
      case 'text-size':
        (this as MLNSymbolStyleLayer).textFontSize = expression;
      case 'text-ignore-placement':
        (this as MLNSymbolStyleLayer).textIgnoresPlacement = expression;
      case 'text-justify':
        (this as MLNSymbolStyleLayer).textJustification = expression;
      case 'text-optional':
        (this as MLNSymbolStyleLayer).textOptional = expression;
      case 'text-rotate':
        (this as MLNSymbolStyleLayer).textRotation = expression;
      case 'text-writing-mode':
        (this as MLNSymbolStyleLayer).textWritingModes = expression;
      case 'icon-translate':
        (this as MLNSymbolStyleLayer).iconTranslation = expression;
      case 'icon-translate-anchor':
        (this as MLNSymbolStyleLayer).iconTranslationAnchor = expression;
      case 'text-translate':
        (this as MLNSymbolStyleLayer).textTranslation = expression;
      case 'text-translate-anchor':
        (this as MLNSymbolStyleLayer).textTranslationAnchor = expression;
      default:
        // iOS FFI FIX: Do NOT use Key-Value Coding - it crashes with MapLibre properties
        // Instead, just log and skip unhandled properties to prevent app crashes
        debugPrint('⚠️ iOS: Unhandled property "$key" skipped (prevents KVC crash)');
    }
  }
}

/// UTF8 Encoding
const nsUTF8StringEncoding = 4;
