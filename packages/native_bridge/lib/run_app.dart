/// One entry point for every target.
///
/// ```dart
/// import 'package:dart_not_native/run_app.dart';
///
/// void main() => runNativeApp(MyApp());
/// ```
///
/// The right renderer is chosen for the platform the code is running on: the
/// DOM renderer on web, and on mobile either Flutter widgets (the default,
/// which paints every node type) or the platform's own views. Whichever is
/// chosen, the system back gesture is wired and the app is mounted.
///
/// Each target still has its own entry point if you want one: `runWebApp`
/// from `package:dart_not_native/web.dart`, or a `NativeUIAppHost` widget
/// placed wherever you like from `package:dart_not_native/material.dart`.
library;

// The vocabulary a screen is written in comes with the entry point, so one
// import is enough for an app that does not reach for a specific target.
export 'core.dart';
export 'src/run_app/run_app_flutter.dart'
    if (dart.library.js_interop) 'src/run_app/run_app_web.dart';
