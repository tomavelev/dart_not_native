/// Renders the controls gallery through the platform's OWN views.
///
/// One of each thing a device test has to be able to find - tappable boxes,
/// layers, a dropdown, tabs, a bottom bar, a dialog, a snackbar - which is
/// what the `e2e/agent-device` flows drive.
///
///   flutter run -t lib/main_native_gallery.dart -d `<device>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/controls_gallery_app.dart';

void main() {
  runApp(const ControlsGalleryApp(), title: 'Native Controls Gallery');
}
