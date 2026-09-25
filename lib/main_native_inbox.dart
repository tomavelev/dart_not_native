/// Runs the inbox (a LazyList of many messages) through the platform's own
/// views, to exercise the lazy-list keyed reconcile on scroll.
///
///   flutter run -t lib/main_native_inbox.dart -d `<device>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/inbox_example_app.dart';

void main() {
  // A high glass transparency shows the Liquid Glass sheet and dialog off on
  // iOS 26 - the list behind them shows through the frost. Ignored elsewhere.
  runApp(
    const InboxApp(),
    title: 'Native Inbox',
    appTheme: const AppTheme(glassTransparency: 0.6),
  );
}
