/// dart_not_native Framework - Complete Cross-Platform Solution
///
/// This library provides a unified interface for:
/// 1. **Native Bridge** - Cross-platform abstraction (FFI on mobile, in-memory on web)
/// 2. **Web Bridge** - Material CSS widgets for web
/// 3. **Plugin System** - Extensible plugins for offline-sync, persistence, etc.
///
/// ## Usage
///
/// ### Standard Import (Automatic Platform Detection)
/// ```dart
/// import 'package:dart_not_native/material.dart';
///
/// void main() {
///   runApp(const MyApp());
/// }
///
/// class MyApp extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return MaterialApp(
///       home: Scaffold(
///         appBar: AppBar(title: Text('Hello')),
///         body: Center(child: Text('Works everywhere!')),
///       ),
///     );
///   }
/// }
/// ```
///
/// The framework automatically uses:
/// - **Android/iOS**: Flutter Material (native rendering)
/// - **Web**: Material CSS (Material Design Lite)
///
/// ### With Optional Native Code
/// ```dart
/// void main() {
///   NativeBridge.initialize('libbridge.so');
///   runApp(const MyApp());
/// }
/// ```
///
/// ### With Backend Sync (Coming Soon)
/// ```dart
/// void main() {
///   NativeBridge.use(BackendSyncPlugin(
///     apiUrl: 'https://api.example.com',
///   ));
///   runApp(const MyApp());
/// }
/// ```

library dart_not_native;

// Export core bridge functionality
export 'native_bridge.dart';
export 'platforms/mobile_bridge.dart' show initializeMobile;
export 'platforms/web_bridge.dart' show initializeWeb;

// Export plugin system (designed, implementation coming)
export 'plugins/backend_sync_plugin.dart';

// Material widgets exported via material_adapter with platform detection
// This single export provides different implementations per platform:
// - Mobile (Android/iOS): Flutter Material
// - Web: Material CSS (web_ui)
// Access via: import 'package:dart_not_native/material.dart';
