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
/// "Web" there means a program compiled with `dart compile js`, which has no
/// Flutter in it. A `flutter build web` has - `dart:ui_web` is how the two
/// are told apart - and takes the Flutter entry point: the tree is painted by
/// Flutter's canvas through the Flutter renderer, and the app's Flutter
/// plugins work as they do in any Flutter web app. That is the web build for
/// an app whose plugins a plain dart2js program cannot link.
///
/// Each target still has its own entry point if you want one: `runWebApp`
/// from `package:dart_not_native/web.dart`, or a `NativeUIAppHost` widget
/// placed wherever you like from `package:dart_not_native/material.dart`.
library;

// The vocabulary a screen is written in comes with the entry point, so one
// import is enough for an app that does not reach for a specific target.
export 'core.dart';
export 'src/run_app/run_app_flutter.dart'
    if (dart.library.ui_web) 'src/run_app/run_app_flutter.dart'
    if (dart.library.js_interop) 'src/run_app/run_app_web.dart';
