/// Navigation & routing - rendered through the platform's own views.
///
/// The app is a plain Flutter `StatelessWidget` building a MaterialApp with
/// named routes in apps/routing_example_app.dart; only the import
/// (`widgets.dart`) renders it natively rather than through the Flutter engine.
library;

import 'package:dart_not_native/widgets.dart';

import 'apps/routing_example_app.dart';

void main() => runApp(const RoutingExampleApp(), title: 'Routing');
