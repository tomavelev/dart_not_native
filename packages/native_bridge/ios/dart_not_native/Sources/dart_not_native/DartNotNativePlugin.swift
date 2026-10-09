import Flutter
import UIKit

/**
 Registers everything dart_not_native needs on iOS.

 Flutter's generated plugin registrant creates this, so an app gets both of the
 following by depending on the package - no AppDelegate edits, no files to
 copy:

  - the native UI renderer, which paints widget trees as UIViews;
  - the swipe from the left screen edge, forwarded to Dart as a `systemBack`
    call.

 The framework renders views rather than a UINavigationController stack, so the
 system interactive-pop gesture has nothing of its own to pop: the recogniser
 below takes its place and lets the Dart router decide. Dart answers false when
 the app is on its first screen, and the gesture is left alone.
 */
public class DartNotNativePlugin: NSObject, FlutterPlugin {
  private static let systemBackChannelName = "com.programtom.dart_not_native/system_back"

  private var systemBackChannel: FlutterMethodChannel?
  private var renderer: NativeUIRenderer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DartNotNativePlugin()
    instance.systemBackChannel = FlutterMethodChannel(
      name: systemBackChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.publish(instance)

    // Registration runs while the root view controller is still being set up,
    // so the view work waits until it exists. On a physical device the UIScene
    // and its FlutterViewController can take several run-loop turns to appear,
    // so retry rather than give up after one - otherwise the renderer channel
    // is never registered and the app falls back to Flutter.
    DispatchQueue.main.async {
      instance.attachWhenReady(messenger: registrar.messenger())
    }
  }

  private func attachWhenReady(messenger: FlutterBinaryMessenger, attempt: Int = 0) {
    if Self.rootFlutterViewController() != nil {
      attachToRootViewController(messenger: messenger)
    } else if attempt < 100 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.attachWhenReady(messenger: messenger, attempt: attempt + 1)
      }
    }
  }

  private func attachToRootViewController(messenger: FlutterBinaryMessenger) {
    guard let controller = Self.rootFlutterViewController() else { return }

    renderer = NativeUIRenderer(controller: controller, messenger: messenger)

    let edgeSwipe = UIScreenEdgePanGestureRecognizer(
      target: self,
      action: #selector(handleEdgeSwipe(_:))
    )
    edgeSwipe.edges = .left
    controller.view.addGestureRecognizer(edgeSwipe)
  }

  private static func rootFlutterViewController() -> FlutterViewController? {
    let scenes = UIApplication.shared.connectedScenes
    for scene in scenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let controller = window.rootViewController as? FlutterViewController {
          return controller
        }
      }
    }
    return UIApplication.shared.delegate?.window??.rootViewController
      as? FlutterViewController
  }

  @objc private func handleEdgeSwipe(_ recognizer: UIScreenEdgePanGestureRecognizer) {
    // Only a completed swipe counts, so a hesitant drag does not navigate.
    guard recognizer.state == .ended, let view = recognizer.view else { return }

    let travelled = recognizer.translation(in: view).x
    let velocity = recognizer.velocity(in: view).x
    let committed = travelled > view.bounds.width / 3 || velocity > 500
    guard committed else { return }

    systemBackChannel?.invokeMethod("systemBack", arguments: nil)
  }
}
