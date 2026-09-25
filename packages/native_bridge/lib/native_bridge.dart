import 'package:flutter/foundation.dart';

// Platform-specific implementations
import 'platforms/mobile_bridge.dart'
    if (dart.library.js_interop) 'platforms/web_bridge.dart'
    as platform_impl;

/// Generic native bridge supporting both mobile (FFI) and web (in-memory).
///
/// On mobile (Android/iOS): Loads native C library via FFI
/// On web (browser): Uses in-memory Dart methods
///
/// Client code is identical across all platforms:
/// ```dart
/// void main() {
///   NativeBridge.initialize('libbridge.so'); // No-op on web
///   runApp(MyApp());
/// }
///
/// // Later:
/// int result = NativeBridge.callMethod('increment_counter');
/// ```
class NativeBridge {
  /// Initialize the native bridge.
  ///
  /// On mobile: Loads the native library (e.g., 'libbridge.so')
  /// On web: No-op (methods already in memory)
  static void initialize(String libraryName) {
    if (kIsWeb) {
      // Web: no initialization needed, methods are in-memory
      platform_impl.initializeWeb();
    } else {
      // Mobile: load native library
      platform_impl.initializeMobile(libraryName);
    }
  }

  /// Call a native method by name with optional arguments.
  /// Returns an int32 result.
  ///
  /// Works identically on mobile (calls C via FFI) and web (calls Dart methods).
  static int callMethod(String methodName, [String args = '']) {
    return platform_impl.callNativeMethod(methodName, args);
  }
}
