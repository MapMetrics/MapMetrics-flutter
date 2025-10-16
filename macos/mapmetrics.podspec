#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mapmetrics.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'mapmetrics'
  s.version          = '0.1.0'
  s.summary          = 'Permissive and performant mapping library that supports Mapbox Vector Tiles (MVT) powered by MapLibre SDKs.'
  s.description      = <<-DESC
Permissive and performant mapping library that supports Mapbox Vector Tiles (MVT) powered by MapLibre SDKs.
                       DESC
  s.homepage         = 'https://github.com/MapMetrics/MapMetrics-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MapMetrics' => 'info@mapmetrics.org' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
