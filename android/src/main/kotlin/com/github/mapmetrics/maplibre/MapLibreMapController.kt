package com.github.mapmetrics.maplibre

// if imports can't resolve: https://stackoverflow.com/a/65903576/9439899

import CameraChangeReason
import LngLat
import MapCamera
import MapLibreFlutterApi
import MapLibreHostApi
import MapOptions
import android.content.Context
import android.graphics.BitmapFactory
import android.view.View
import android.widget.FrameLayout
import androidx.lifecycle.DefaultLifecycleObserver
import com.google.gson.Gson
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import org.maplibre.android.MapLibre
import org.maplibre.android.WellKnownTileServer
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapLibreMap.OnCameraMoveStartedListener.REASON_API_ANIMATION
import org.maplibre.android.maps.MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE
import org.maplibre.android.maps.MapLibreMap.OnCameraMoveStartedListener.REASON_DEVELOPER_ANIMATION
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.OnMapReadyCallback
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.BackgroundLayer
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.FillExtrusionLayer
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.HeatmapLayer
import org.maplibre.android.style.layers.HillshadeLayer
import org.maplibre.android.style.layers.LayoutPropertyValue
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PaintPropertyValue
import org.maplibre.android.style.layers.PropertyValue
import org.maplibre.android.style.layers.RasterLayer
import org.maplibre.android.style.layers.SymbolLayer
import java.io.IOException
import java.net.URL
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.locks.ReentrantLock

class MapLibreMapController(
    private val viewId: Int,
    private val context: Context,
    private val lifecycleProvider: LifecycleProvider,
    binaryMessenger: BinaryMessenger,
) : PlatformView,
    DefaultLifecycleObserver,
    OnMapReadyCallback,
    MapLibreHostApi {
    private val mapViewContainer = FrameLayout(context)
    private lateinit var mapLibreMap: MapLibreMap
    private lateinit var mapView: MapView
    private val flutterApi: MapLibreFlutterApi
    private lateinit var mapOptions: MapOptions
    private var style: Style? = null

    // THREAD SAFETY: Handler for main thread, executor for background work, lock for synchronization
    private val mainHandler = Handler(Looper.getMainLooper())
    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val styleLock = ReentrantLock()
    private var isMapReady = false

    init {
        val channelSuffix = viewId.toString()
        MapLibreHostApi.setUp(binaryMessenger, this, channelSuffix)
        flutterApi = MapLibreFlutterApi(binaryMessenger, channelSuffix)
        flutterApi.getOptions { result: Result<MapOptions> ->
            mapOptions = result.getOrThrow()
            val cameraBuilder =
                CameraPosition
                    .Builder()
                    .zoom(mapOptions.zoom)
                    .bearing(mapOptions.bearing)
                    .tilt(mapOptions.pitch)
            if (mapOptions.center != null) {
                cameraBuilder.target(
                    LatLng(
                        mapOptions.center!!.lat,
                        mapOptions.center!!.lng,
                    ),
                )
            }
            val options =
                MapLibreMapOptions
                    .createFromAttributes(context)
                    .attributionEnabled(false)
                    .logoEnabled(false)
                    // TODO: textureMode comes at a significant performance penalty, https://maplibre.org/maplibre-native/android/api/-map-libre%20-native%20-android/org.maplibre.android.maps/-map-libre-map-options/texture-mode.html
                    .textureMode(mapOptions.androidTextureMode)
                    .compassEnabled(false)
                    .minZoomPreference(mapOptions.minZoom)
                    .maxZoomPreference(mapOptions.maxZoom)
                    .minPitchPreference(mapOptions.minPitch)
                    .maxPitchPreference(mapOptions.maxPitch)
                    .rotateGesturesEnabled(mapOptions.gestures.rotate)
                    .zoomGesturesEnabled(mapOptions.gestures.zoom)
                    .doubleTapGesturesEnabled(false)
                    .scrollGesturesEnabled(mapOptions.gestures.zoom)
                    .quickZoomGesturesEnabled(mapOptions.gestures.zoom)
                    .tiltGesturesEnabled(mapOptions.gestures.tilt)
                    .camera(cameraBuilder.build())

            // needs to be called before MapView gets created.
            // The 3-arg overload caches the maps-scoped api key, which the v2
            // MMMapSessionInterceptor (installed from getInstance) needs in order to
            // establish a session. The 1-arg overload caches a null key: the session
            // POST then sends an empty token, fails silently, and every tile falls
            // back to v1 billing with no crash and no log.
            MapLibre.getInstance(context, mapOptions.apiKey, WellKnownTileServer.MapLibre)
            mapView = MapView(context, options)
            lifecycleProvider.getLifecycle()?.addObserver(this)
            // v2 replaced the `initializeSessionWithToken` cookie handshake with
            // MMMapSessionInterceptor, installed by MapLibre.getInstance above.
            // These two calls used to be gated inside its callback; they now run directly.
            mapView.getMapAsync(this)
            mapViewContainer.addView(mapView)
        }
    }

    override fun getView(): View = mapViewContainer

    override fun onMapReady(mapLibreMap: MapLibreMap) {
        this.mapLibreMap = mapLibreMap
        MapLibreRegistry.addMap(viewId, mapLibreMap)
        this.mapLibreMap.addOnMapClickListener { latLng ->
            flutterApi.onClick(LngLat(latLng.longitude, latLng.latitude)) { }
            true
        }
        this.mapLibreMap.addOnMapLongClickListener { latLng ->
            flutterApi.onLongClick(LngLat(latLng.longitude, latLng.latitude)) { }
            true
        }
        this.mapLibreMap.addOnCameraMoveListener {
            val position = mapLibreMap.cameraPosition
            val target = mapLibreMap.cameraPosition.target!!
            val center = LngLat(target.longitude, target.latitude)
            val camera = MapCamera(center, position.zoom, position.tilt, position.bearing)
            flutterApi.onMoveCamera(camera) {}
        }
        this.mapLibreMap.addOnCameraIdleListener { flutterApi.onCameraIdle { } }
        this.mapView.addOnDidBecomeIdleListener { flutterApi.onIdle { } }
        this.mapLibreMap.addOnCameraMoveStartedListener { reason ->
            val changeReason =
                when (reason) {
                    REASON_API_ANIMATION -> CameraChangeReason.API_ANIMATION
                    REASON_API_GESTURE -> CameraChangeReason.API_GESTURE
                    REASON_DEVELOPER_ANIMATION -> CameraChangeReason.DEVELOPER_ANIMATION
                    else -> null
                }
            if (changeReason != null) flutterApi.onStartMoveCamera(changeReason) { }
        }
        val style = Style.Builder().fromUri(mapOptions.style)
        mapLibreMap.setStyle(style) { loadedStyle ->
            this.style = loadedStyle
            isMapReady = true
            println("Android: Map and style ready, isMapReady = true")
            flutterApi.onStyleLoaded { }
        }
        flutterApi.onMapReady { }
    }

    override fun dispose() {
        // free any resources
        isMapReady = false
        backgroundExecutor.shutdown()
        println("Android: MapController disposed, executor shutdown")
    }

    private val gson = Gson()

    private fun parsePaintProperties(entries: Map<String, Any>): Array<PropertyValue<*>> =
        entries
            .map { entry ->
//                println("${entry.key}; ${entry.value::class.java.typeName}; ${entry.value}")
                when (entry.value) {
                    is ArrayList<*> -> {
                        val value = entry.value as ArrayList<*>
                        if (value.isEmpty()) {
                            PaintPropertyValue(entry.key, value)
                        }
                        when (value.first()) {
                            is String -> {
                                val json = gson.toJsonTree(value)
                                val expression = Expression.Converter.convert(json)
                                PaintPropertyValue(entry.key, expression)
                            }

                            else -> {
                                PaintPropertyValue(entry.key, value.toArray())
                            }
                        }
                    }

                    else -> PaintPropertyValue(entry.key, entry.value)
                }
            }.toTypedArray()

    private fun parseLayoutProperties(entries: Map<String, Any>): Array<PropertyValue<*>> =
        entries
            .map { entry ->
                // text-font is DATA, not an expression. A font stack is a plain
                // list of face names, but the generic branch below treats ANY
                // array whose first element is a String as an expression and
                // hands it to Expression.Converter -- which reads
                // "Noto Sans Regular" as an operator name. It does not throw;
                // it yields an expression the renderer cannot use, and that
                // takes the whole symbol layer down: no icons and no labels,
                // silently.
                //
                // iOS had the identical bug in createExpression and was fixed
                // the same way. Any future property whose value is a genuine
                // array of strings needs the same treatment.
                if (entry.key == "text-font" && entry.value is ArrayList<*>) {
                    val fonts = (entry.value as ArrayList<*>).map { it.toString() }.toTypedArray()
                    return@map LayoutPropertyValue(entry.key, fonts)
                }
//                println("${entry.key}; ${entry.value::class.java.typeName}; ${entry.value}")
                when (entry.value) {
                    is ArrayList<*> -> {
                        val value = entry.value as ArrayList<*>
                        if (value.isEmpty()) {
                            LayoutPropertyValue(entry.key, value)
                        }
                        when (value.first()) {
                            is String -> {
                                val json = gson.toJsonTree(value)
                                val expression = Expression.Converter.convert(json)
                                LayoutPropertyValue(entry.key, expression)
                            }

                            else -> {
                                LayoutPropertyValue(entry.key, value.toArray())
                            }
                        }
                    }

                    else -> LayoutPropertyValue(entry.key, entry.value)
                }
            }.toTypedArray()

    /**
     * Safely remove an existing layer before adding a new one.
     * Prevents SIGSEGV from duplicate layer IDs in native MapLibre.
     */
    private fun safeRemoveExistingLayer(layerId: String) {
        try {
            val currentStyle = mapLibreMap.style ?: return
            val existing = currentStyle.getLayer(layerId)
            if (existing != null) {
                currentStyle.removeLayer(layerId)
            }
        } catch (e: Exception) {
            // Ignore — layer may not exist or style may be in transition
        }
    }

    /**
     * Safely add a layer, removing any duplicate first.
     * Wraps native addLayer/addLayerBelow in try/catch to prevent SIGSEGV.
     */
    private fun safeAddLayer(layer: org.maplibre.android.style.layers.Layer, belowLayerId: String?) {
        safeRemoveExistingLayer(layer.id)
        val currentStyle = mapLibreMap.style ?: return
        try {
            if (belowLayerId == null) {
                currentStyle.addLayer(layer)
            } else {
                currentStyle.addLayerBelow(layer, belowLayerId)
            }
        } catch (e: Exception) {
            println("MapLibre: safeAddLayer failed for '${layer.id}': ${e.message}")
        }
    }

    override fun addFillLayer(
        id: String,
        sourceId: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val layer = FillLayer(id, sourceId)
        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(layout))
        safeAddLayer(layer, belowLayerId)
        callback(Result.success(Unit))
    }

    override fun addCircleLayer(
        id: String,
        sourceId: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        // Handle source-layer separately if it exists in layout
        val sourceLayer = layout["source-layer"] as? String
        val layer = if (sourceLayer != null) {
            CircleLayer(id, sourceId).withSourceLayer(sourceLayer)
        } else {
            CircleLayer(id, sourceId)
        }

        // Handle filter if it exists in layout
        val filterArray = layout["__filter__"] as? ArrayList<*>
        if (filterArray != null) {
            val json = gson.toJsonTree(filterArray)
            val expression = Expression.Converter.convert(json)
            layer.setFilter(expression)
        }

        // Handle minZoom/maxZoom if they exist in layout
        val minZoom = layout["__minZoom__"] as? Double
        val maxZoom = layout["__maxZoom__"] as? Double
        if (minZoom != null) {
            layer.minZoom = minZoom.toFloat()
            // minZoom applied to circle layer
        }
        if (maxZoom != null) {
            layer.maxZoom = maxZoom.toFloat()
            // maxZoom applied to circle layer
        }

        // Filter out source-layer, __filter__, __minZoom__, __maxZoom__ from layout properties before parsing
        val filteredLayout = layout.filterKeys { it != "source-layer" && it != "__filter__" && it != "__minZoom__" && it != "__maxZoom__" }

        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(filteredLayout))
        safeAddLayer(layer, belowLayerId)
        callback(Result.success(Unit))
    }

    override fun addBackgroundLayer(
        id: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val layer = BackgroundLayer(id)
        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(layout))
        safeAddLayer(layer, belowLayerId)
        callback(Result.success(Unit))
    }

    override fun addFillExtrusionLayer(
        id: String,
        sourceId: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val layer = FillExtrusionLayer(id, sourceId)
        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(layout))
        safeAddLayer(layer, belowLayerId)
        callback(Result.success(Unit))
    }

    override fun addHeatmapLayer(
        id: String,
        sourceId: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val layer = HeatmapLayer(id, sourceId)
        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(layout))
        safeAddLayer(layer, belowLayerId)
        callback(Result.success(Unit))
    }

    override fun addHillshadeLayer(
        id: String,
        sourceId: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val layer = HillshadeLayer(id, sourceId)
        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(layout))
        safeAddLayer(layer, belowLayerId)
        callback(Result.success(Unit))
    }

    override fun addLineLayer(
        id: String,
        sourceId: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val layer = LineLayer(id, sourceId)
        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(layout))
        safeAddLayer(layer, belowLayerId)
        callback(Result.success(Unit))
    }

    override fun addRasterLayer(
        id: String,
        sourceId: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val layer = RasterLayer(id, sourceId)

        // The setProperties call here was commented out, so every raster
        // property the app set -- raster-opacity, raster-brightness-min/max,
        // raster-saturation, raster-contrast, visibility -- was discarded and
        // the layer drew at its defaults. A bare RasterLayer still shows the
        // source, so the layer looked like it worked and only the styling went
        // missing, silently. iOS had the mirror of this: its addRasterLayer was
        // a stub that ignored every argument and reported success.
        val minZoom = layout["__minZoom__"] as? Double
        val maxZoom = layout["__maxZoom__"] as? Double
        if (minZoom != null) layer.minZoom = minZoom.toFloat()
        if (maxZoom != null) layer.maxZoom = maxZoom.toFloat()

        val filteredLayout = layout.filterKeys {
            it != "source-layer" && it != "__filter__" && it != "__minZoom__" && it != "__maxZoom__"
        }
        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(filteredLayout))

        safeAddLayer(layer, belowLayerId)
        callback(Result.success(Unit))
    }

    override fun addSymbolLayer(
        id: String,
        sourceId: String,
        layout: Map<String, Any>,
        paint: Map<String, Any>,
        belowLayerId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        // addSymbolLayer: $id

        // Handle source-layer separately if it exists in layout
        val sourceLayer = layout["source-layer"] as? String
        val layer = if (sourceLayer != null) {
            SymbolLayer(id, sourceId).withSourceLayer(sourceLayer)
        } else {
            SymbolLayer(id, sourceId)
        }

        // Handle filter if it exists in layout
        val filterArray = layout["__filter__"] as? ArrayList<*>
        if (filterArray != null) {
            val json = gson.toJsonTree(filterArray)
            val expression = Expression.Converter.convert(json)
            layer.setFilter(expression)
            // Filter applied to symbol layer
        }

        // Handle minZoom/maxZoom if they exist in layout
        val minZoom = layout["__minZoom__"] as? Double
        val maxZoom = layout["__maxZoom__"] as? Double
        if (minZoom != null) {
            layer.minZoom = minZoom.toFloat()
            // minZoom applied
        }
        if (maxZoom != null) {
            layer.maxZoom = maxZoom.toFloat()
            // maxZoom applied
        }

        // Filter out source-layer, __filter__, __minZoom__, __maxZoom__ from layout properties before parsing
        val filteredLayout = layout.filterKeys { it != "source-layer" && it != "__filter__" && it != "__minZoom__" && it != "__maxZoom__" }

        // Use parseLayoutProperties and parsePaintProperties to handle complex expressions
        layer.setProperties(*parsePaintProperties(paint), *parseLayoutProperties(filteredLayout))

        safeAddLayer(layer, belowLayerId)
        // Symbol layer $id added
        callback(Result.success(Unit))
    }

    override fun loadImage(
        url: String,
        callback: (Result<ByteArray>) -> Unit,
    ) {
        try {
            val bytes = URL(url).openConnection().getInputStream().readBytes()
            callback(Result.success(bytes))
        } catch (e: IOException) {
            callback(Result.failure(e))
        }
    }

    override fun addImage(
        id: String,
        bytes: ByteArray,
        callback: (Result<Unit>) -> Unit,
    ) {
        // addImage: $id

        // THREAD SAFETY: Decode bitmap on background thread
        backgroundExecutor.execute {
            try {
                val bitmap = BitmapFactory.decodeStream(bytes.inputStream())
                if (bitmap == null) {
                    println("Android: ERROR - Failed to decode bitmap from bytes")
                    mainHandler.post {
                        callback(Result.failure(Exception("Failed to decode image bitmap")))
                    }
                    return@execute
                }

                // Bitmap decoded: ${bitmap.width}x${bitmap.height}

                // THREAD SAFETY: Add to style on main thread with lock
                mainHandler.post {
                    styleLock.lock()
                    try {
                        if (!isMapReady) {
                            println("Android: Map not ready yet for addImage '$id'")
                            callback(Result.failure(Exception("Map not ready")))
                            return@post
                        }

                        val currentStyle = mapLibreMap.style
                        if (currentStyle == null) {
                            println("Android: Style not available for addImage '$id'")
                            callback(Result.failure(Exception("Style not available")))
                            return@post
                        }

                        // SAFE: Add image to style
                        currentStyle.addImage(id, bitmap)

                        // Verify the image was added
                        val verifyImage = currentStyle.getImage(id)
                        if (verifyImage != null) {
                            // Image '$id' added to style
                        } else {
                            println("Android: ⚠️ WARNING - Image '$id' was set but cannot be retrieved from style")
                        }

                        callback(Result.success(Unit))
                    } finally {
                        styleLock.unlock()
                    }
                }
            } catch (e: Exception) {
                println("Android: Exception in addImage: ${e.message}")
                mainHandler.post {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun addImages(
        ids: List<String>,
        images: List<ByteArray>,
        callback: (Result<Unit>) -> Unit,
    ) {
        // addImages: ${ids.size} images
        val startTime = System.currentTimeMillis()

        // THREAD SAFETY: Decode all bitmaps on background thread
        backgroundExecutor.execute {
            try {
                // Decode all bitmaps on background thread
                val decodedImages = mutableListOf<Pair<String, android.graphics.Bitmap>>()
                var failCount = 0

                for (i in ids.indices) {
                    val id = ids[i]
                    val bytes = images[i]
                    val bitmap = BitmapFactory.decodeStream(bytes.inputStream())
                    if (bitmap != null) {
                        decodedImages.add(Pair(id, bitmap))
                    } else {
                        failCount++
                        println("Android: Failed to decode image: $id")
                    }
                }

                // THREAD SAFETY: Add all to style on main thread with lock
                mainHandler.post {
                    styleLock.lock()
                    try {
                        if (!isMapReady) {
                            println("Android: Map not ready for bulk addImages")
                            callback(Result.failure(Exception("Map not ready")))
                            return@post
                        }

                        val currentStyle = mapLibreMap.style
                        if (currentStyle == null) {
                            println("Android: Error - Style not available for bulk addImages")
                            callback(Result.failure(Exception("Style not available")))
                            return@post
                        }

                        // SAFE: Add all images to style
                        for ((id, bitmap) in decodedImages) {
                            currentStyle.addImage(id, bitmap)
                        }

                        val elapsed = System.currentTimeMillis() - startTime
                        // Bulk addImages: ${decodedImages.size} success, $failCount failed
                        callback(Result.success(Unit))
                    } finally {
                        styleLock.unlock()
                    }
                }
            } catch (e: Exception) {
                println("Android: Error in bulk addImages: ${e.message}")
                mainHandler.post {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun addSprite(
        spriteJson: String,
        spriteImage: ByteArray,
        callback: (Result<Unit>) -> Unit,
    ) {
        // addSprite called
        val startTime = System.currentTimeMillis()

        try {
            val style = mapLibreMap.style
            if (style == null) {
                println("Android: Error - Style not available for addSprite")
                callback(Result.failure(Exception("Style not available")))
                return
            }

            // Decode the full sprite sheet
            val spriteBitmap = BitmapFactory.decodeByteArray(spriteImage, 0, spriteImage.size)
            if (spriteBitmap == null) {
                println("Android: Error - Failed to decode sprite image")
                callback(Result.failure(Exception("Failed to decode sprite image")))
                return
            }

            // Parse sprite JSON
            val jsonObject = org.json.JSONObject(spriteJson)
            val keys = jsonObject.keys()
            var successCount = 0
            var failCount = 0

            while (keys.hasNext()) {
                val name = keys.next()
                try {
                    val iconData = jsonObject.getJSONObject(name)
                    val x = iconData.getInt("x")
                    val y = iconData.getInt("y")
                    val width = iconData.getInt("width")
                    val height = iconData.getInt("height")

                    if (width > 0 && height > 0 && x + width <= spriteBitmap.width && y + height <= spriteBitmap.height) {
                        // Extract icon from sprite sheet - this is very fast in native code
                        val iconBitmap = android.graphics.Bitmap.createBitmap(spriteBitmap, x, y, width, height)
                        style.addImage(name, iconBitmap)
                        successCount++
                    } else {
                        failCount++
                    }
                } catch (e: Exception) {
                    failCount++
                }
            }

            spriteBitmap.recycle()

            val elapsed = System.currentTimeMillis() - startTime
            // Sprite loading: $successCount icons
            callback(Result.success(Unit))
        } catch (e: Exception) {
            println("Android: Error in addSprite: ${e.message}")
            callback(Result.failure(e))
        }
    }

    override fun addClusteredGeoJsonSource(
        id: String,
        data: String,
        clustered: Boolean,
        clusterRadius: Double,
        clusterMaxZoom: Double,
        clusterPropertiesJson: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            // addClusteredGeoJsonSource: $id
            val style = mapLibreMap.style
            if (style == null) {
                println("Android: Error - Style not available")
                callback(Result.failure(Exception("Style not available")))
                return
            }

            val options = org.maplibre.android.style.sources.GeoJsonOptions()
            if (clustered) {
                options.withCluster(true)
                options.withClusterRadius(clusterRadius.toInt())
                options.withClusterMaxZoom(clusterMaxZoom.toInt())
                // Clustering enabled
            }

            val source = if (data.startsWith("http://") || data.startsWith("https://")) {
                // Creating URL source
                org.maplibre.android.style.sources.GeoJsonSource(id, data, options)
            } else {
                // Creating GeoJSON data source
                org.maplibre.android.style.sources.GeoJsonSource(id, data, options)
            }
            style.addSource(source)
            // Clustered source added: $id

            // Add visualization layers for clusters if clustering is enabled
            if (clustered) {
                // Adding cluster visualization layers

                // Add layer for unclustered points (individual points)
                val unclusteredLayer = CircleLayer("$id-unclustered", id)
                unclusteredLayer.setProperties(
                    org.maplibre.android.style.layers.PropertyFactory.circleRadius(8f),
                    org.maplibre.android.style.layers.PropertyFactory.circleColor("#11b4da"),
                    org.maplibre.android.style.layers.PropertyFactory.circleOpacity(0.8f),
                    org.maplibre.android.style.layers.PropertyFactory.circleStrokeWidth(2f),
                    org.maplibre.android.style.layers.PropertyFactory.circleStrokeColor("#ffffff")
                )
                unclusteredLayer.setFilter(org.maplibre.android.style.expressions.Expression.not(
                    org.maplibre.android.style.expressions.Expression.has("point_count")
                ))
                style.addLayer(unclusteredLayer)
                // Added unclustered points layer

                // Add layer for clusters (colored circles)
                val clustersLayer = CircleLayer("$id-clusters", id)
                clustersLayer.setProperties(
                    org.maplibre.android.style.layers.PropertyFactory.circleRadius(20f),
                    org.maplibre.android.style.layers.PropertyFactory.circleColor("#f1f075"),
                    org.maplibre.android.style.layers.PropertyFactory.circleOpacity(0.8f),
                    org.maplibre.android.style.layers.PropertyFactory.circleStrokeWidth(2f),
                    org.maplibre.android.style.layers.PropertyFactory.circleStrokeColor("#ffffff")
                )
                clustersLayer.setFilter(org.maplibre.android.style.expressions.Expression.has("point_count"))
                style.addLayer(clustersLayer)
                // Added clusters layer

                // Add layer for cluster count labels
                val clusterCountLayer = SymbolLayer("$id-cluster-count", id)
                clusterCountLayer.setProperties(
                    org.maplibre.android.style.layers.PropertyFactory.textField(
                        org.maplibre.android.style.expressions.Expression.get("point_count_abbreviated")
                    ),
                    org.maplibre.android.style.layers.PropertyFactory.textSize(12f),
                    org.maplibre.android.style.layers.PropertyFactory.textColor("#ffffff")
                )
                clusterCountLayer.setFilter(org.maplibre.android.style.expressions.Expression.has("point_count"))
                style.addLayer(clusterCountLayer)
                // Added cluster count labels layer
            }

            callback(Result.success(Unit))
        } catch (e: Exception) {
            println("Android: Error adding clustered source: ${e.message}")
            callback(Result.failure(e))
        }
    }

    /// Added for parity with iOS, which reaches raster sources through Pigeon.
    /// Android's StyleController builds RasterSource over JNI directly and so
    /// never calls this, but the generated MapLibreHostApi requires it.
    override fun addRasterSource(
        id: String,
        tiles: List<String>,
        minZoom: Double,
        maxZoom: Double,
        tileSize: Double,
        attribution: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            val style = mapLibreMap.style
            if (style == null) {
                callback(Result.failure(Exception("Style not available")))
                return
            }
            val tileSet = org.maplibre.android.style.sources.TileSet("2.2.0", *tiles.toTypedArray())
            tileSet.minZoom = minZoom.toFloat()
            tileSet.maxZoom = maxZoom.toFloat()
            if (attribution != null) tileSet.attribution = attribution
            style.addSource(
                org.maplibre.android.style.sources.RasterSource(id, tileSet, tileSize.toInt()),
            )
            callback(Result.success(Unit))
        } catch (e: Exception) {
            println("Android: Error adding raster source: ${e.message}")
            callback(Result.failure(e))
        }
    }

    override fun addVectorSource(
        id: String,
        tiles: List<String>,
        minZoom: Double,
        maxZoom: Double,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            // addVectorSource: $id
            val style = mapLibreMap.style
            if (style == null) {
                println("Android: Error - Style not available")
                callback(Result.failure(Exception("Style not available")))
                return
            }

            // Create VectorSource with TileSet
            // MapLibre Android VectorSource requires a TileSet with tile URLs
            // Creating TileSet
            val tileSet = org.maplibre.android.style.sources.TileSet("2.2.0", *tiles.toTypedArray())
            // Setting min/max zoom
            tileSet.minZoom = minZoom.toFloat()
            tileSet.maxZoom = maxZoom.toFloat()

            // Creating VectorSource
            val source = org.maplibre.android.style.sources.VectorSource(id, tileSet)

            // Adding source to style
            style.addSource(source)
            // Vector source added: $id

            callback(Result.success(Unit))
        } catch (e: Exception) {
            println("Android: Error adding vector source: ${e.message}")
            e.printStackTrace()
            callback(Result.failure(e))
        }
    }

    override fun testMethod(
        value: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        // testMethod: $value
        callback(Result.success(Unit))
    }

    override fun animateCamera(
        latitude: Double,
        longitude: Double,
        zoom: Double,
        bearing: Double,
        pitch: Double,
        duration: Long,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            val cameraUpdate = org.maplibre.android.camera.CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder()
                    .target(LatLng(latitude, longitude))
                    .zoom(zoom)
                    .bearing(bearing)
                    .tilt(pitch)
                    .build()
            )

            val animationDuration = if (duration > 0) duration.toInt() else 200
            mapLibreMap.animateCamera(cameraUpdate, animationDuration)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            println("Android: Error animating camera: ${e.message}")
            callback(Result.failure(e))
        }
    }

    override fun getCamera(): MapCamera {
        val position = mapLibreMap.cameraPosition
        val target = position.target ?: LatLng(0.0, 0.0)
        return MapCamera(
            LngLat(target.longitude, target.latitude),
            position.zoom,
            position.tilt,
            position.bearing
        )
    }

    override fun getZoomLevel(): Double {
        return mapLibreMap.cameraPosition.zoom
    }

    override fun getUserLocation(): LngLat {
        val userLocation = mapLibreMap.locationComponent.lastKnownLocation
        return if (userLocation != null) {
            LngLat(userLocation.longitude, userLocation.latitude)
        } else {
            LngLat(0.0, 0.0) // Default location if user location is not available
        }
    }

    // Add these methods to your MapLibreMapController.kt class

    override fun moveCamera(
        lat: Double,
        lng: Double,
        zoom: Double,
        bearing: Double,
        pitch: Double,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        // This is just a stub since Android uses JNI directly
        callback(Result.success(Unit))
    }

    override fun updateMapOptions(
        minZoom: Double,
        maxZoom: Double,
        minPitch: Double,
        maxPitch: Double,
        boundsWest: Double,
        boundsSouth: Double,
        boundsEast: Double,
        boundsNorth: Double,
        rotateEnabled: Boolean,
        panEnabled: Boolean,
        zoomEnabled: Boolean,
        pitchEnabled: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        callback(Result.success(Unit))
    }

    override fun enableLocation(
        fastestInterval: Long,
        maxWaitTime: Long,
        pulseFade: Boolean,
        accuracyAnimation: Boolean,
        compassAnimation: Boolean,
        pulse: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        callback(Result.success(Unit))
    }

    override fun fitBounds(
        west: Double,
        south: Double,
        east: Double,
        north: Double,
        bearing: Double,
        pitch: Double,
        duration: Long,
        paddingLeft: Double,
        paddingTop: Double,
        paddingRight: Double,
        paddingBottom: Double,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        callback(Result.success(Unit))
    }

    override fun setContentInset(
        left: Double,
        top: Double,
        right: Double,
        bottom: Double,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android uses JNI directly via MapLibreMap.setPadding from Dart side.
        callback(Result.success(Unit))
    }

    override fun getMetersPerPixelAtLatitude(
        latitude: Double,
        callback: (Result<Double>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        // For now, return a placeholder value
        callback(Result.success(156543.03392)) // meters per pixel at equator at zoom 0
    }

    override fun getVisibleRegion(
        callback: (Result<List<Double>>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        // Return [west, south, east, north]
        callback(Result.success(listOf(-180.0, -85.0, 180.0, 85.0)))
    }

    override fun toLngLat(
        x: Double,
        y: Double,
        callback: (Result<List<Double>>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        // For now, return placeholder coordinates
        // Return [lng, lat]
        callback(Result.success(listOf(0.0, 0.0)))
    }

    override fun toScreenLocation(
        lng: Double,
        lat: Double,
        callback: (Result<List<Double>>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        // For now, return placeholder screen coordinates
        // Return [x, y]
        callback(Result.success(listOf(0.0, 0.0)))
    }

    override fun queryLayers(
        x: Double,
        y: Double,
        callback: (Result<List<Map<String, String>>>) -> Unit
    ) {
        try {
            val screenPoint = android.graphics.PointF(x.toFloat(), y.toFloat())
            val results = mutableListOf<Map<String, String>>()

            // Get all layers from the style
            val style = mapLibreMap.style
            if (style != null) {
                val layers = style.layers

                // Query each layer individually to get layer metadata
                for (layer in layers) {
                    // Query features for this specific layer
                    val layerFeatures = mapLibreMap.queryRenderedFeatures(screenPoint, layer.id)

                    for (feature in layerFeatures) {
                        val properties = mutableMapOf<String, String>()

                        // Add layer metadata (matching iOS implementation)
                        properties["layerId"] = layer.id

                        // Get source ID from the layer
                        // Note: In MapLibre Android, layers don't directly expose source ID
                        // We'll extract it from the JSON if possible
                        properties["sourceId"] = ""

                        // Try to get source layer from feature properties or layer
                        properties["sourceLayer"] = feature.toJson()?.let { json ->
                            org.json.JSONObject(json).optString("source-layer", "")
                        } ?: ""

                        // Extract geometry coordinates from feature JSON
                        try {
                            val featureJson = feature.toJson()
                            if (featureJson != null) {
                                val jsonObject = org.json.JSONObject(featureJson)
                                val geometry = jsonObject.optJSONObject("geometry")
                                if (geometry != null && geometry.optString("type") == "Point") {
                                    val coordinates = geometry.optJSONArray("coordinates")
                                    if (coordinates != null && coordinates.length() >= 2) {
                                        properties["longitude"] = coordinates.getDouble(0).toString()
                                        properties["latitude"] = coordinates.getDouble(1).toString()
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            println("Android: Error extracting coordinates: ${e.message}")
                        }

                        // Extract all feature properties (using empty string instead of null)
                        val featureProperties = feature.properties()
                        if (featureProperties != null) {
                            for (key in featureProperties.keySet()) {
                                val value = featureProperties.get(key)
                                properties[key] = value?.toString() ?: ""
                            }
                        }

                        // First feature debug removed for cleaner logs

                        results.add(properties)
                    }
                }
            }

            // queryLayers: ${results.size} features
            callback(Result.success(results))
        } catch (e: Exception) {
            println("Android: Error querying layers: ${e.message}")
            e.printStackTrace()
            callback(Result.failure(e))
        }
    }

    override fun queryLayersInRect(
        left: Double,
        top: Double,
        right: Double,
        bottom: Double,
        callback: (Result<List<Map<Any?, Any?>>>) -> Unit
    ) {
        try {
            val rect = android.graphics.RectF(left.toFloat(), top.toFloat(), right.toFloat(), bottom.toFloat())
            val results = mutableListOf<Map<Any?, Any?>>()

            // Get all layers from the style
            val style = mapLibreMap.style
            if (style != null) {
                val layers = style.layers

                // Query each layer individually using the bounding box
                for (layer in layers) {
                    // Query features within the rect for this specific layer
                    val layerFeatures = mapLibreMap.queryRenderedFeatures(rect, layer.id)

                    for (feature in layerFeatures) {
                        val properties = mutableMapOf<Any?, Any?>()

                        // Add layer metadata
                        properties["layerId"] = layer.id
                        properties["sourceId"] = ""
                        properties["sourceLayer"] = feature.toJson()?.let { json ->
                            org.json.JSONObject(json).optString("source-layer", "")
                        } ?: ""

                        // Extract geometry coordinates
                        try {
                            val featureJson = feature.toJson()
                            if (featureJson != null) {
                                val jsonObject = org.json.JSONObject(featureJson)
                                val geometry = jsonObject.optJSONObject("geometry")
                                if (geometry != null && geometry.optString("type") == "Point") {
                                    val coordinates = geometry.optJSONArray("coordinates")
                                    if (coordinates != null && coordinates.length() >= 2) {
                                        properties["longitude"] = coordinates.getDouble(0).toString()
                                        properties["latitude"] = coordinates.getDouble(1).toString()
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            println("Android: Error extracting coordinates in rect query: ${e.message}")
                        }

                        // Extract all feature properties
                        val featureProperties = feature.properties()
                        if (featureProperties != null) {
                            // Feature in layer ${layer.id}
                            for (key in featureProperties.keySet()) {
                                val value = featureProperties.get(key)
                                // Strip quotes from string values (JsonElement.toString() keeps quotes)
                                var strValue = value?.toString() ?: ""
                                if (strValue.startsWith("\"") && strValue.endsWith("\"")) {
                                    strValue = strValue.substring(1, strValue.length - 1)
                                }
                                properties[key] = strValue
                                // POI name tracking removed for cleaner logs
                            }
                        } else {
                            // No properties for feature in layer
                        }

                        results.add(properties)
                    }
                }
            }

            // queryLayersInRect: ${results.size} features
            callback(Result.success(results))
        } catch (e: Exception) {
            println("Android: Error querying layers in rect: ${e.message}")
            e.printStackTrace()
            callback(Result.failure(e))
        }
    }

    override fun trackLocation(
        track: Boolean,
        bearingMode: Long,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        callback(Result.success(Unit))
    }

    override fun showUserLocationPuck(
        show: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            // Android uses location component to control user location display
            mapLibreMap?.locationComponent?.let { locationComponent ->
                if (show) {
                    locationComponent.isLocationComponentEnabled = true
                } else {
                    locationComponent.isLocationComponentEnabled = false
                }
                // showUserLocationPuck: $show
            }
            callback(Result.success(Unit))
        } catch (e: Exception) {
            println("Android: Error in showUserLocationPuck: ${e.message}")
            callback(Result.success(Unit)) // Don't fail, just log
        }
    }

    override fun removeLayer(
        id: String,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        callback(Result.success(Unit))
    }

    override fun removeSource(
        id: String,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        callback(Result.success(Unit))
    }

    override fun updateGeoJsonSource(
        id: String,
        data: String,
        callback: (Result<Unit>) -> Unit
    ) {
        // Android implementation - you can use your existing JNI code
        callback(Result.success(Unit))
    }

    override fun setStyleUri(styleUri: String, callback: (Result<Unit>) -> Unit) {
        if (!isMapReady) {
            callback(Result.failure(Exception("Map not ready")))
            return
        }
        style = null
        val newStyle = Style.Builder().fromUri(styleUri)
        mapLibreMap.setStyle(newStyle) { loadedStyle ->
            style = loadedStyle
            flutterApi.onStyleLoaded { }
            callback(Result.success(Unit))
        }
    }
}
