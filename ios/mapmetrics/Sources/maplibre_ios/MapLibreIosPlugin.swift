import Flutter
import MapLibre
import UIKit
import CoreLocation  // Add this line

public class MapLibreIosPlugin: NSObject, FlutterPlugin {
    private static var permissionManager: PermissionManagerIos?
    private static var currentStyle: MLNStyle?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "mapmetrics", binaryMessenger: registrar.messenger()
        )
        let instance = MapLibreIosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // register MapLibre view factory
        let factory = MapLibreViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "plugins.flutter.io/maplibre")

        // setup OfflineManager
        OfflineManager(messenger: registrar.messenger())

        let permissionManager = PermissionManagerIos()
        self.permissionManager = permissionManager

        PermissionManagerHostApiSetup.setUp(
            binaryMessenger: registrar.messenger(),
            api: permissionManager
        )

        print("iOS: PermissionManager registered successfully")
    }

    public func handle(
        _ call: FlutterMethodCall, result: @escaping FlutterResult
    ) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        // MARK: - Permission Status Methods (ADD THESE)
        case "getLocationPermissionsGranted":
            let granted = PermissionManagerIos.isLocationPermissionGranted()
            result(granted)

        case "getBackgroundLocationPermissionGranted":
            let granted = PermissionManagerIos.isBackgroundLocationPermissionGranted()
            result(granted)

        case "getRuntimePermissionsRequired":
            let required = PermissionManagerIos.isRuntimePermissionsRequired()
            result(required)

        case "addClusteredGeoJsonSource":
            guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? String,
                let data = args["data"] as? String,
                let clustered = args["clustered"] as? Bool,
                let clusterRadius = args["clusterRadius"] as? Double,
                let clusterMaxZoom = args["clusterMaxZoom"] as? Double
            else {
                print("iOS: addClusteredGeoJsonSource - Invalid arguments")
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid arguments for addClusteredGeoJsonSource", details: nil))
                return
            }

            print(
                "iOS: addClusteredGeoJsonSource - Adding source with ID: \(id), clustered: \(clustered)"
            )

            // Create clustering options
            var options: [MLNShapeSourceOption: Any] = [:]
            if clustered {
                options[.clustered] = true
                options[.clusterRadius] = clusterRadius
                options[.maximumZoomLevelForClustering] = clusterMaxZoom
                print(
                    "iOS: addClusteredGeoJsonSource - Clustering enabled with radius: \(clusterRadius), maxZoom: \(clusterMaxZoom)"
                )
            }

            // Create the shape source
            let source: MLNShapeSource
            if data.hasPrefix("http://") || data.hasPrefix("https://") {
                // Handle URL source
                guard let url = URL(string: data) else {
                    print("iOS: addClusteredGeoJsonSource - Invalid URL: \(data)")
                    result(
                        FlutterError(
                            code: "INVALID_URL", message: "Invalid URL: \(data)", details: nil))
                    return
                }
                source = MLNShapeSource(identifier: id, url: url, options: options)
                print("iOS: addClusteredGeoJsonSource - Created URL source")
            } else {
                // Handle GeoJSON data
                guard let dataBytes = data.data(using: .utf8),
                    let shape = try? MLNShape(
                        data: dataBytes, encoding: String.Encoding.utf8.rawValue)
                else {
                    print("iOS: addClusteredGeoJsonSource - Invalid GeoJSON data")
                    result(
                        FlutterError(
                            code: "INVALID_GEOJSON", message: "Invalid GeoJSON data", details: nil))
                    return
                }
                source = MLNShapeSource(identifier: id, shape: shape, options: options)
                print(
                    "iOS: addClusteredGeoJsonSource - Created GeoJSON source with \(data.count) characters"
                )
            }

            // Add the source to the current style
            if let currentStyle = MapLibreIosPlugin.currentStyle {
                // CRASH FIX: Check if source already exists to prevent MLNRedundantSourceIdentifierException
                if let existingSource = currentStyle.source(withIdentifier: id) {
                    print("iOS: addClusteredGeoJsonSource - Source \(id) already exists, removing first")
                    currentStyle.removeSource(existingSource)
                }

                currentStyle.addSource(source)
                print("iOS: addClusteredGeoJsonSource - Source added to style successfully")

                result(nil)
            } else {
                print("iOS: addClusteredGeoJsonSource - No current style available")
                result(
                    FlutterError(
                        code: "NO_STYLE", message: "No current style available", details: nil))
            }
        case "addCircleLayer":
            guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? String,
                let sourceId = args["sourceId"] as? String,
                let layout = args["layout"] as? [String: Any],
                let paint = args["paint"] as? [String: Any]
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS", message: "Invalid arguments for addCircleLayer",
                        details: nil))
                return
            }

            if let currentStyle = MapLibreIosPlugin.currentStyle {
                let layer = MLNCircleStyleLayer(
                    identifier: id, source: currentStyle.source(withIdentifier: sourceId)!)

                // Apply layout properties
                for (key, value) in layout {
                    layer.setValue(value, forKey: key)
                }

                // Apply paint properties
                for (key, value) in paint {
                    layer.setValue(value, forKey: key)
                }

                currentStyle.addLayer(layer)
                result(nil)
            } else {
                result(
                    FlutterError(
                        code: "NO_STYLE", message: "No current style available", details: nil))
            }
        case "addSymbolLayer":
            guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? String,
                let sourceId = args["sourceId"] as? String,
                let layout = args["layout"] as? [String: Any],
                let paint = args["paint"] as? [String: Any]
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS", message: "Invalid arguments for addSymbolLayer",
                        details: nil))
                return
            }

            if let currentStyle = MapLibreIosPlugin.currentStyle {
                let layer = MLNSymbolStyleLayer(
                    identifier: id, source: currentStyle.source(withIdentifier: sourceId)!)

                // Apply layout properties
                for (key, value) in layout {
                    layer.setValue(value, forKey: key)
                }

                // Apply paint properties
                for (key, value) in paint {
                    layer.setValue(value, forKey: key)
                }

                currentStyle.addLayer(layer)
                result(nil)
            } else {
                result(
                    FlutterError(
                        code: "NO_STYLE", message: "No current style available", details: nil))
            }
        case "addFillLayer":
            guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? String,
                let sourceId = args["sourceId"] as? String,
                let layout = args["layout"] as? [String: Any],
                let paint = args["paint"] as? [String: Any]
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS", message: "Invalid arguments for addFillLayer",
                        details: nil))
                return
            }

            if let currentStyle = MapLibreIosPlugin.currentStyle {
                let layer = MLNFillStyleLayer(
                    identifier: id, source: currentStyle.source(withIdentifier: sourceId)!)

                // Apply layout properties
                for (key, value) in layout {
                    layer.setValue(value, forKey: key)
                }

                // Apply paint properties
                for (key, value) in paint {
                    layer.setValue(value, forKey: key)
                }

                currentStyle.addLayer(layer)
                result(nil)
            } else {
                result(
                    FlutterError(
                        code: "NO_STYLE", message: "No current style available", details: nil))
            }
        case "addLineLayer":
            guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? String,
                let sourceId = args["sourceId"] as? String,
                let layout = args["layout"] as? [String: Any],
                let paint = args["paint"] as? [String: Any]
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS", message: "Invalid arguments for addLineLayer",
                        details: nil))
                return
            }

            if let currentStyle = MapLibreIosPlugin.currentStyle {
                let layer = MLNLineStyleLayer(
                    identifier: id, source: currentStyle.source(withIdentifier: sourceId)!)

                // Apply layout properties
                for (key, value) in layout {
                    layer.setValue(value, forKey: key)
                }

                // Apply paint properties
                for (key, value) in paint {
                    layer.setValue(value, forKey: key)
                }

                currentStyle.addLayer(layer)
                result(nil)
            } else {
                result(
                    FlutterError(
                        code: "NO_STYLE", message: "No current style available", details: nil))
            }
        case "addBackgroundLayer":
            guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? String,
                let layout = args["layout"] as? [String: Any],
                let paint = args["paint"] as? [String: Any]
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Invalid arguments for addBackgroundLayer", details: nil))
                return
            }

            if let currentStyle = MapLibreIosPlugin.currentStyle {
                let layer = MLNBackgroundStyleLayer(identifier: id)

                // Apply layout properties
                for (key, value) in layout {
                    layer.setValue(value, forKey: key)
                }

                // Apply paint properties
                for (key, value) in paint {
                    layer.setValue(value, forKey: key)
                }

                currentStyle.addLayer(layer)
                result(nil)
            } else {
                result(
                    FlutterError(
                        code: "NO_STYLE", message: "No current style available", details: nil))
            }
        case "addImage":
            guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? String,
                let bytes = args["bytes"] as? FlutterStandardTypedData
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENTS", message: "Invalid arguments for addImage",
                        details: nil))
                return
            }

            if let currentStyle = MapLibreIosPlugin.currentStyle,
                let image = UIImage(data: bytes.data)
            {
                currentStyle.setImage(image, forName: id)
                result(nil)
            } else {
                result(
                    FlutterError(
                        code: "NO_STYLE",
                        message: "No current style available or invalid image data", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FFI Bridge for Clustering
    @objc public static func createShapeSourceWithClustering(
        _ identifier: UnsafePointer<CChar>,
        _ shape: UnsafePointer<CChar>,
        _ options: UnsafePointer<CChar>
    ) -> UnsafeMutableRawPointer? {
        let id = String(cString: identifier)
        let shapeStr = String(cString: shape)
        let optionsStr = String(cString: options)

        // Parse options JSON to get clustering parameters
        guard let optionsData = optionsStr.data(using: .utf8),
            let optionsDict = try? JSONSerialization.jsonObject(with: optionsData) as? [String: Any]
        else {
            return nil
        }

        let isClustered = optionsDict["clustered"] as? Bool ?? false
        let clusterRadius = optionsDict["clusterRadius"] as? Double ?? 50.0
        let clusterMaxZoom = optionsDict["maximumZoomLevelForClustering"] as? Double ?? 16.0

        var mlOptions: [MLNShapeSourceOption: Any] = [:]

        if isClustered {
            mlOptions[.clustered] = true
            mlOptions[.clusterRadius] = clusterRadius
            mlOptions[.maximumZoomLevelForClustering] = clusterMaxZoom
        }

        let source: MLNShapeSource

        // Check if shape is a URL or GeoJSON data
        if shapeStr.hasPrefix("http://") || shapeStr.hasPrefix("https://") {
            // Handle URL source
            guard let url = URL(string: shapeStr) else { return nil }
            source = MLNShapeSource(identifier: id, url: url, options: mlOptions)
        } else {
            // Handle GeoJSON data
            guard let data = shapeStr.data(using: .utf8),
                let mlShape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
            else {
                return nil
            }
            source = MLNShapeSource(identifier: id, shape: mlShape, options: mlOptions)
        }

        // Return an unmanaged pointer to the source
        return Unmanaged.passRetained(source).toOpaque()
    }

    // Method to set the current style
    public static func setCurrentStyle(_ style: MLNStyle) {
        currentStyle = style
    }
}

import CoreLocation
import Foundation

class PermissionManagerIos: NSObject, PermissionManagerHostApi {
    private var locationManager: CLLocationManager?
    private var permissionCompletion: ((Result<Bool, Error>) -> Void)?

    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager?.delegate = self
    }

    // MARK: - Static Status Checking Methods (ADD THESE)

    /// Get current location permission status synchronously
    @objc public static func isLocationPermissionGranted() -> Bool {
        let status = CLLocationManager.authorizationStatus()
        let granted = status == .authorizedWhenInUse || status == .authorizedAlways
        print("iOS: Static permission check - status: \(status.rawValue), granted: \(granted)")
        return granted
    }

    /// Get current background location permission status synchronously
    @objc public static func isBackgroundLocationPermissionGranted() -> Bool {
        let status = CLLocationManager.authorizationStatus()
        let granted = status == .authorizedAlways
        print("iOS: Static background permission check - status: \(status.rawValue), granted: \(granted)")
        return granted
    }

    /// Runtime permissions are always required on iOS
    @objc public static func isRuntimePermissionsRequired() -> Bool {
        return true
    }

    // MARK: - PermissionManagerHostApi Implementation

    func requestLocationPermissions(
        explanation: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        print("iOS: Requesting location permissions with explanation: \(explanation)")

        guard let locationManager = locationManager else {
            print("iOS: Location manager not available")
            completion(
                .failure(
                    NSError(
                        domain: "PermissionManager",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Location manager not available"]
                    )))
            return
        }

        // FIRST: Check current authorization status in real-time
        let currentStatus = CLLocationManager.authorizationStatus()
        print("iOS: Current location authorization status: \(currentStatus.rawValue)")

        switch currentStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission is ALREADY GRANTED - return immediately
            print("iOS: Location permission already granted, returning true immediately")
            completion(.success(true))
            return

        case .denied, .restricted:
            // Permission is DENIED - return false immediately (don't request again)
            print("iOS: Location permission denied or restricted, returning false")
            completion(.success(false))
            return

        case .notDetermined:
            // Permission is NOT DETERMINED - need to request it
            print("iOS: Permission not determined, requesting authorization")
            // Store completion for later use in delegate
            permissionCompletion = completion
            locationManager.requestWhenInUseAuthorization()

        @unknown default:
            print("iOS: Unknown location authorization status")
            completion(.success(false))
            return
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PermissionManagerIos: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus
    ) {
        print("iOS: Location authorization status changed to: \(status.rawValue)")

        guard let completion = permissionCompletion else {
            print("iOS: No pending permission completion")
            return
        }

        switch status {
        case .notDetermined:
            // Still waiting for user decision, don't call completion yet
            print("iOS: Still waiting for user decision")
            return

        case .denied, .restricted:
            print("iOS: Location permission denied or restricted in delegate")
            completion(.success(false))

        case .authorizedWhenInUse, .authorizedAlways:
            print("iOS: Location permission granted in delegate")
            completion(.success(true))

        @unknown default:
            print("iOS: Unknown location authorization status in delegate")
            completion(.success(false))
        }

        // Clear the completion handler
        permissionCompletion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("iOS: Location manager failed with error: \(error.localizedDescription)")

        if let completion = permissionCompletion {
            completion(.failure(error))
            permissionCompletion = nil
        }
    }
}