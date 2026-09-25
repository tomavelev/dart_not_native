/// Component Showcase - all components, rendered through the platform's own views.
///
/// Pages, state and events live in the plain Flutter `StatefulWidget`
/// [ComponentsShowcaseApp] (apps/components_showcase_app.dart); only the import
/// (`widgets.dart`) renders it natively rather than through the Flutter engine.
library;

import 'package:dart_not_native/widgets.dart';

import 'apps/components_showcase_app.dart';

void main() =>
    runApp(const ComponentsShowcaseApp(), title: 'Component Showcase');
