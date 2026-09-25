import Flutter
import UIKit

/// Hosts the Flutter engine.
///
/// The native UI renderer and the left-edge back swipe are registered by
/// `DartNotNativePlugin` through `GeneratedPluginRegistrant`, so nothing
/// framework-specific is needed here.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
