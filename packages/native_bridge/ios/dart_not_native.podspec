Pod::Spec.new do |s|
  s.name             = 'dart_not_native'
  s.version          = '0.1.0'
  s.summary          = 'Native UI rendering and the system back gesture for dart_not_native.'
  s.description      = <<-DESC
Renders dart_not_native widget trees as UIKit views and forwards the swipe from
the left screen edge to Dart.
                       DESC
  s.homepage         = 'https://programtom.com'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Toma Velev' => 'tomavelev@gmail.com' }
  s.source           = { :git => 'https://github.com/tomavelev/dart_not_native.git', :tag => s.version.to_s }
  # Where Swift Package Manager expects them, so both build the same files.
  s.source_files     = 'dart_not_native/Sources/dart_not_native/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
