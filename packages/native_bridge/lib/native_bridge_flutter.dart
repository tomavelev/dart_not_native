/// The FFI bridge: call into C by method name, with the same Dart on every
/// target.
///
/// This is the oldest part of the package and is separate from the renderers.
/// An app drawing its screens with the framework imports
/// `package:dart_not_native/widgets.dart` and needs none of this.
///
/// ```dart
/// import 'package:dart_not_native/native_bridge_flutter.dart';
///
/// void main() {
///   NativeBridge.initialize('libbridge.so');
///   final count = NativeBridge.callMethod('increment_counter');
/// }
/// ```
///
/// On Android [NativeBridge.initialize] opens the named library; on iOS it
/// looks the symbols up in the app's own process; on web it does nothing, and
/// calls go to in-memory Dart functions (`platforms/web_bridge.dart`).
library dart_not_native;

// Export core bridge functionality
export 'native_bridge.dart';
export 'platforms/mobile_bridge.dart' show initializeMobile;
export 'platforms/web_bridge.dart' show initializeWeb;

// The plugin system is exported by 'package:dart_not_native/material.dart'.
