/// Entry point that renders the example through the platform's OWN views.
///
/// Unlike `lib/main.dart` (which uses Flutter Material widgets), this mounts the
/// same counter - written as a plain Flutter app in
/// `examples/apps/counter_app.dart` - on the iOS `UIView` renderer via [runApp]
/// from `widgets.dart`: the widget tree crosses the
/// `com.programtom.dart_not_native/renderer` method channel and is drawn as
/// real UIKit views by `ios/dart_not_native/Sources/dart_not_native/NativeUIRenderer.swift`. Flutter only hosts
/// the engine; every pixel on screen is a UIView.
///
/// Run it with:
///   flutter run -t lib/main_native_ios.dart -d `<ios-simulator>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/counter_app.dart';

void main() {
  // runApp defaults to nativeViews: true - the platform's own renderer. On iOS
  // that is iOSNativeRenderer; if the plugin were missing it would fall back to
  // Flutter widgets instead of showing an empty screen.
  runApp(const CounterApp(), title: 'Native iOS Counter');
}
