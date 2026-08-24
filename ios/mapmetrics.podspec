#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint maplibre_ios.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'mapmetrics'
  s.version          = '0.0.1'
  s.summary          = 'Helper package for maplibre that provides iOS FFI bindings'
  s.description      = <<-DESC
Helper package for maplibre that provides iOS FFI bindings
                       DESC
  s.homepage         = 'https://github.com/josxha/flutter-maplibre'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Joscha Eckert' => 'info@joscha-eckert.de' }
  s.source           = { :path => '.' }
  s.source_files = 'mapmetrics/Sources/maplibre_ios/**/*'
  s.public_header_files = 'mapmetrics/Sources/maplibre_ios/**/*.h'
  s.dependency 'Flutter'
  # MapMetrics-SDK is our own build of the map core: MapLibre 6.28.0 plus v2
  # HMAC map sessions, gateway pinning, MapMetrics branding, and Mapbox
  # telemetry removed. Upstream `MapLibre` has none of that, so this must not
  # be swapped back without also giving up billing on iOS.
  #
  # It still vendors a framework NAMED MapLibre.xcframework, exporting module
  # `MapLibre` -- which is why every `import MapLibre` in Sources/ still
  # resolves and this swap needed no source changes. If that framework is ever
  # renamed, those imports change with it.
  #
  # NOT the same dependency as maplibre_ios/Package.swift, which still points
  # at maplibre-gl-native-distribution: we publish no Swift Package Manager
  # artefact yet, so the SPM path silently gets upstream MapLibre instead.
  # See the comment there.
  # 2.0.1 IS A FLOOR, NOT A PREFERENCE. 2.0.0 sends the opening style-and-tile
  # wave before its session create lands, so those requests carry only the
  # style's `?token=` and bill once PER TILE -- 8 charges for one map load,
  # measured against staging. Nothing is visibly wrong when that happens: the
  # map renders correctly and the cost is silent. Do not relax this to '~> 2.0'.
  s.dependency 'MapMetrics-SDK', '~> 2.0.1'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'maplibre_ios_privacy' => ['maplibre_ios/Sources/maplibre_ios/PrivacyInfo.xcprivacy']}
end
