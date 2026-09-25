/// Renders the design-system showcase through the platform's OWN views.
///
/// Five pages of tokens and components (Card, Badge, Alert, Divider, Switch,
/// progress bars) - the richest exercise of the native renderers, and the one
/// that stresses layout, nested Rows/Columns, Expanded weights and the feedback
/// widgets the counter never touches.
///
/// It also follows the device between light and dark, which makes it the
/// example to run when checking a palette change: every surface, divider,
/// helper line and status colour is on screen at once.
///
///   flutter run -t lib/main_native_design_system.dart -d `<device>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/design_system_showcase_app.dart';

void main() {
  runApp(
    const DesignSystemShowcaseApp(),
    title: 'Native Design System',
    appTheme: const AppTheme(mode: AppThemeMode.system),
  );
}
