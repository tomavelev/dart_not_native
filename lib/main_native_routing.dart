/// Runs the routing example through the platform's own views, which is where
/// the store several screens share is worth seeing: favourite a user on their
/// own page, go home, and the count is there.
///
///   flutter run -t lib/main_native_routing.dart -d `<device>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/routing_example_app.dart';

void main() {
  runApp(const RoutingExampleApp(), title: 'Native Routing');
}
