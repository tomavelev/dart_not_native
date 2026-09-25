/// Design System Showcase - rendered through the platform's own views.
///
/// Comprehensive demonstration of the design-system tokens and components
/// across five pages. The app is a plain Flutter `StatefulWidget` in
/// apps/design_system_showcase_app.dart; only the import (`widgets.dart`)
/// renders it natively rather than through the Flutter engine.
library;

import 'package:dart_not_native/widgets.dart';

import 'apps/design_system_showcase_app.dart';

void main() =>
    runApp(const DesignSystemShowcaseApp(), title: 'Design System');
