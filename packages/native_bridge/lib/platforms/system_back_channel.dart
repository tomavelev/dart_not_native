/// Delivers the Android back button/gesture and the iOS edge swipe to
/// [SystemBack].
///
/// The native host (MainActivity on Android, AppDelegate on iOS) calls
/// `systemBack` on this channel when the user goes back, and acts on the
/// answer: true means the app consumed the gesture, false means the platform
/// should do what it normally would - finish the activity, or let the view
/// controller pop.
///
/// ```dart
/// void main() {
///   SystemBackChannel.bind();          // once, at startup
///   final app = NavigationApp(router: router)..bindSystemBack();
///   app.render(AndroidNativeRenderer());
/// }
/// ```
library;

import 'package:flutter/services.dart';

import '../src/system_back.dart';

class SystemBackChannel {
  SystemBackChannel._();

  static const MethodChannel channel = MethodChannel(
    'com.programtom.dart_not_native/system_back',
  );

  /// The method the native hosts invoke.
  static const String method = 'systemBack';

  static bool _bound = false;

  /// Whether the channel is listening.
  static bool get isBound => _bound;

  /// Starts answering the native host. Safe to call twice.
  static void bind() {
    if (_bound) return;
    _bound = true;
    channel.setMethodCallHandler(handleCall);
  }

  /// Stops answering; the native host then falls back to its default.
  static void unbind() {
    if (!_bound) return;
    _bound = false;
    channel.setMethodCallHandler(null);
  }

  /// Handles one call from the native host. Exposed for tests.
  static Future<Object?> handleCall(MethodCall call) async {
    if (call.method != method) {
      throw MissingPluginException(
        'SystemBackChannel does not implement ${call.method}',
      );
    }
    return SystemBack.dispatch();
  }
}
