/// Entry point that renders the example through Android's OWN views.
///
/// The counterpart to `lib/main_native_ios.dart`. The counter is written as a
/// plain Flutter app (see `examples/apps/counter_app.dart`); [runApp] from
/// `widgets.dart` mounts it on the Android renderer, so the widget tree crosses
/// the `com.programtom.dart_not_native/renderer` method channel and is drawn as
/// real Android Views (LinearLayout, MaterialToolbar, MaterialButton, FAB…) by
/// `android/.../NativeUIRenderer.kt`. Flutter only hosts the engine.
///
/// Run it with:
///   flutter run -t lib/main_native_android.dart -d `<android-emulator>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/counter_app.dart';

void main() {
  // runApp defaults to nativeViews: true - the platform's own renderer. On
  // Android that is AndroidNativeRenderer; if the plugin were missing it would
  // fall back to Flutter widgets instead of showing an empty screen.
  runApp(const CounterApp(), title: 'Native Android Counter');
}
