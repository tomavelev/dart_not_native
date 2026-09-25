/// Renders the component showcase (lists) through the platform's OWN views.
///
/// Exercises `ListView`/`ListTile` node types the counter does not.
///
///   flutter run -t lib/main_native_components_showcase.dart -d `<device>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/components_showcase_app.dart';

void main() {
  runApp(const ComponentsShowcaseApp(), title: 'Native Component Showcase');
}
