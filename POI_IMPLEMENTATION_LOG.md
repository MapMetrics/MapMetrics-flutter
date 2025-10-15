# POI Vector Tiles Implementation Log

**Date**: October 15, 2025
**Status**: ✅ **WORKING**

## Summary

Successfully implemented POI (Point of Interest) vector tiles with tourism icons from a POI tile server. The implementation loads tourism icons from a sprite sheet CDN and displays them on the map using vector tile data.

## Working Configuration

### POI Tile Server
- **URL**: `https://poi-tile-server-development.jim9710.workers.dev/tiles/{z}/{x}/{y}.mvt`
- **Format**: Mapbox Vector Tiles (MVT)
- **Zoom Range**: 10-16
- **Layer Name**: `pois`
- **Status**: ✅ Active and returning data (verified 2.6KB tile at z16)

### Sprite Assets
- **Sprite Sheet**: `https://cdn.mapmetrics-atlas.net/Images/resources-hdpi_clear/symbols.png` (1024x1024, 767 icons)
- **Sprite Metadata**: `https://cdn.mapmetrics-atlas.net/Images/resources-hdpi_clear/symbols.sdf` (XML format)
- **Test Icon**: `tourism-m` (1528 bytes, loads successfully)

### Map Configuration
- **Map Center**: Position(5.472009, 51.451771) - Netherlands
- **Initial Zoom**: 16 (within valid range for POI data)
- **Base Style**: MapMetrics moon.json style

## Implementation Details

### Key Files Modified

**`/Users/jimvanderheiden/DEVPROG/MapMetrics-flutter/example/lib/layers_poi_vector_page.dart`**
- Main POI demonstration page
- Implements vector tile source, sprite loading, and layer configuration

### Critical Implementation Steps

#### 1. Sprite Loading
```dart
/// Load a single test icon from CDN
Future<void> _loadSingleTestIcon(StyleController style) async {
  // Load sprite sheet and metadata from CDN
  final spriteSheet = await SpriteSheetLoader.loadSpriteSheet(spriteSheetUrl);
  final spriteMetadata = await SpriteSheetLoader.loadSDF(spriteSdfUrl);

  // Find the tourism-m sprite
  final tourismSprite = spriteMetadata['tourism-m'];
  if (tourismSprite != null && tourismSprite.isValid) {
    // Extract and add to MapLibre
    final iconBytes = await SpriteSheetLoader.extractSprite(spriteSheet, tourismSprite);
    await style.addImage('tourism-m', iconBytes);
  }
}
```

#### 2. Vector Tile Source
```dart
/// Add POI vector tile source to the map
Future<void> _addPOISource(StyleController style) async {
  await style.addSource(
    VectorSource(
      id: 'pois',
      tiles: const [poiTileServerUrl],
      minZoom: 10,  // Server minimum zoom level
      maxZoom: 16,  // Server maximum zoom level
    ),
  );
}
```

#### 3. Symbol Layer Configuration
```dart
/// Add POI layer with tourism icons
Future<void> _addPOILayer(StyleController style) async {
  await style.addLayer(
    SymbolStyleLayer(
      id: 'poi-icons',
      sourceId: 'pois',
      layout: {
        'source-layer': 'pois',  // Vector tile layer name - CRITICAL
        'icon-image': 'tourism-m',
        'icon-size': 2.0,  // Larger for visibility
        'icon-allow-overlap': true,
      },
    ),
  );
}
```

#### 4. Debug Circle Layer
```dart
/// Add test circle layer to visualize POI locations
Future<void> _addTestCircleLayer(StyleController style) async {
  await style.addLayer(
    CircleStyleLayer(
      id: 'poi-test-circles',
      sourceId: 'pois',
      layout: {
        'source-layer': 'pois',  // Must match vector tile layer
      },
      paint: {
        'circle-radius': 20,  // Large for visibility
        'circle-color': '#FF0000',  // Red
        'circle-opacity': 1.0,
        'circle-stroke-width': 4,
        'circle-stroke-color': '#FFFF00',  // Yellow outline
        'circle-stroke-opacity': 1.0,
      },
    ),
  );
}
```

## Key Success Factors

### ✅ What Worked

1. **Vector Tile Source Configuration**
   - Using `VectorSource` instead of `GeoJsonSource`
   - Proper URL template: `{z}/{x}/{y}.mvt`
   - Correct minZoom/maxZoom matching server capabilities

2. **Source Layer Parameter**
   - **CRITICAL**: Must specify `'source-layer': 'pois'` in layer layout
   - Vector tiles can contain multiple layers - must specify which one
   - This was the key missing piece that prevented icons from displaying

3. **Sprite Loading**
   - Loading sprite sheet from CDN works correctly
   - Extracting sprites using SDF metadata
   - Adding sprites to MapLibre with `style.addImage()`

4. **Layer Configuration**
   - SymbolStyleLayer for icons
   - CircleStyleLayer for debug visualization
   - Both layers use the same source but different rendering

### ❌ What Didn't Work

1. **GeoJSON Inline Approach**
   - `GeoJsonSource.data` expects a URL, not inline JSON string
   - Attempted to pass JSON string directly - resulted in URI parsing error
   - Error: "Illegal character in scheme name at index 0"

2. **Hot Reload Limitations**
   - Hot reload doesn't pick up changes to `onStyleLoaded` callback
   - Required full rebuild to test layer configuration changes
   - This slowed debugging significantly

3. **Text Labels Without Fonts**
   - Text labels require font files that weren't available
   - Font loading errors: 404 for Open Sans Regular font
   - Solution: Removed text-field configuration to avoid font dependencies

## Debugging Process

### Issues Encountered

1. **Icons Not Displaying Initially**
   - Problem: Missing `'source-layer'` parameter in SymbolStyleLayer
   - Symptom: Icon loaded successfully but not visible on map
   - Solution: Added `'source-layer': 'pois'` to layout configuration

2. **Red Circles Not Appearing**
   - Problem: Hot reload not updating `onStyleLoaded` callback
   - Symptom: Circle layer code added but not executing
   - Solution: Full rebuild with `flutter run`

3. **GeoJSON Approach Failed**
   - Problem: API limitation in MapMetrics/MapLibre
   - Symptom: Runtime URI parsing error
   - Solution: Reverted to vector tile source approach

### Verification Steps

1. **Tile Server Check**
   ```bash
   curl -I "https://poi-tile-server-development.jim9710.workers.dev/tiles/16/33614/21538.mvt"
   # Result: HTTP 200, 2.6KB tile data
   ```

2. **Tile Content Analysis**
   ```python
   # Found layer names: 'pois', 'poi', 'data'
   # Confirmed POI data exists in tiles
   ```

3. **Log Monitoring**
   ```
   ✓ Added tourism-m icon (1528 bytes)
   POI source added successfully
   === POI ICON LAYER ADDED SUCCESSFULLY ===
   === POI CIRCLE LAYER ADDED SUCCESSFULLY ===
   === POI TEST COMPLETE ===
   ```

## Current Status

### ✅ Working Components

- **POI Tile Server**: Active and returning valid MVT data
- **Sprite Loading**: tourism-m icon loads successfully (1528 bytes)
- **Vector Source**: POI source added with correct zoom range
- **Icon Layer**: SymbolStyleLayer displays tourism icons
- **Debug Layer**: CircleStyleLayer shows POI locations as red circles
- **Map Display**: Icons visible at zoom level 16 in Netherlands location

### 🔧 Known Limitations

- **Text Labels**: Disabled due to missing font files (non-critical)
- **Hot Reload**: Doesn't work with onStyleLoaded - requires full rebuild
- **Zoom Range**: Limited to 10-16 by tile server
- **Icon Set**: Currently only using tourism-m icon for testing

### 📋 Next Steps (Future Enhancements)

1. **Dynamic Icon Mapping**: Use POI config's buildIconExpression() for type-specific icons
2. **Font Loading**: Add proper font files for text labels
3. **Full Sprite Sheet**: Load all 767 sprites for complete icon coverage
4. **Interactive Popups**: Implement click handling for POI details
5. **Performance**: Optimize sprite loading and rendering
6. **Error Handling**: Add retry logic for tile server failures

## Technical Notes

### MapLibre Vector Tile Layers

- Vector tiles can contain multiple named layers
- Must specify `'source-layer'` to tell MapLibre which layer to render
- Different from GeoJSON sources which don't use source-layer parameter

### Sprite Sheet Processing

- SDF (Sprite Definition File) uses XML format with symbol coordinates
- Each sprite defined by minX, minY, maxX, maxY attributes
- Sprites extracted using canvas operations and encoded as PNG
- MapLibre addImage() accepts PNG-encoded Uint8List

### Flutter/MapLibre Integration

- `StyleController` provides access to map style and layer management
- `onStyleLoaded` callback is the correct place to add layers
- Layer operations are async and must be awaited
- Layer order matters - circles render on top of icons if added later

## Conclusion

The POI vector tiles implementation is now fully functional. Tourism icons from the POI tile server are displaying correctly on the map using vector tile data and CDN-hosted sprite sheets. Both icon display (SymbolStyleLayer) and debug visualization (CircleStyleLayer) are working as expected.

**Key Learning**: The `'source-layer'` parameter in the layout configuration is critical for vector tile rendering and was the missing piece that prevented icons from displaying initially.
