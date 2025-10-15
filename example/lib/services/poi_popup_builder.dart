import 'package:flutter/material.dart';
import 'package:maplibre_example/services/poi_config_loader.dart';

/// Service to build POI popup content
/// Based on the JavaScript POIRenderer popup logic
class POIPopupBuilder {
  /// Build a formatted popup widget from POI properties
  /// This matches the JavaScript buildPopupContent() function
  static Widget buildPopup({
    required Map<String, dynamic> properties,
    required POIRendererConfig config,
  }) {
    final displayedKeys = config.popupConfig.displayedKeys;
    final maxWidth = _parseMaxWidth(config.popupConfig.maxWidth);

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title (name)
          if (properties['name'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                properties['name'] as String,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),

          // Display configured properties
          ...displayedKeys.map((key) {
            final value = properties[key];
            if (value == null) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildPropertyRow(key, value),
            );
          }),
        ],
      ),
    );
  }

  /// Build a row for a property key-value pair
  static Widget _buildPropertyRow(String key, dynamic value) {
    // Format the key (e.g., "opening_hours" -> "Opening Hours")
    final formattedKey = _formatPropertyKey(key);
    final formattedValue = _formatPropertyValue(key, value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$formattedKey: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        Expanded(
          child: _buildValueWidget(key, formattedValue),
        ),
      ],
    );
  }

  /// Build a widget for the property value (handles links, phones, etc.)
  static Widget _buildValueWidget(String key, String value) {
    // Handle special types
    if (key == 'website' || key == 'url') {
      return Text(
        value,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      );
    }

    if (key == 'phone' || key == 'contact:phone') {
      return Text(
        value,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      );
    }

    // Default text
    return Text(
      value,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.black87,
      ),
    );
  }

  /// Format property key for display
  /// Converts snake_case to Title Case
  static String _formatPropertyKey(String key) {
    // Remove namespace prefixes (e.g., "contact:phone" -> "phone")
    final withoutPrefix = key.contains(':') ? key.split(':').last : key;

    // Convert snake_case to Title Case
    return withoutPrefix
        .split('_')
        .map((word) => word.isEmpty
            ? ''
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Format property value for display
  static String _formatPropertyValue(String key, dynamic value) {
    if (value == null) return '';

    // Handle boolean values
    if (value is bool) {
      return value ? 'Yes' : 'No';
    }

    // Handle numbers
    if (value is num) {
      return value.toString();
    }

    // Convert to string
    return value.toString();
  }

  /// Parse maxWidth from config string (e.g., "320px" -> 320.0)
  static double _parseMaxWidth(String maxWidth) {
    final number = maxWidth.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(number) ?? 320.0;
  }

  /// Build popup content as a string (for native map popups)
  /// This matches the JavaScript buildPopupContent() HTML generation
  static String buildPopupHTML({
    required Map<String, dynamic> properties,
    required POIRendererConfig config,
  }) {
    final buffer = StringBuffer();
    final displayedKeys = config.popupConfig.displayedKeys;

    buffer.write('<div style="padding: 12px; max-width: ${config.popupConfig.maxWidth};">');

    // Add title (name)
    if (properties['name'] != null) {
      buffer.write('<div style="font-size: 16px; font-weight: bold; margin-bottom: 8px;">');
      buffer.write(_escapeHtml(properties['name'].toString()));
      buffer.write('</div>');
    }

    // Add configured properties
    for (final key in displayedKeys) {
      final value = properties[key];
      if (value == null) continue;

      final formattedKey = _formatPropertyKey(key);
      final formattedValue = _formatPropertyValue(key, value);

      buffer.write('<div style="font-size: 12px; margin-bottom: 4px;">');
      buffer.write('<strong>$formattedKey:</strong> ');

      // Handle special types with links
      if (key == 'website' || key == 'url') {
        buffer.write('<a href="$formattedValue" target="_blank" style="color: blue; text-decoration: underline;">$formattedValue</a>');
      } else if (key == 'phone' || key == 'contact:phone') {
        buffer.write('<a href="tel:$formattedValue" style="color: blue; text-decoration: underline;">$formattedValue</a>');
      } else {
        buffer.write(_escapeHtml(formattedValue));
      }

      buffer.write('</div>');
    }

    buffer.write('</div>');

    return buffer.toString();
  }

  /// Escape HTML special characters
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
