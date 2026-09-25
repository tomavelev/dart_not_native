/// Internationalization - rendered through the platform's own views.
///
/// The app is a plain Flutter `StatelessWidget` in apps/i18n_example_app.dart -
/// it needs no state, because every `Tr` follows the locale itself; only the
/// import (`widgets.dart`) renders it natively rather than through the Flutter
/// engine.
library;

import 'package:dart_not_native/widgets.dart';

import 'apps/i18n_example_app.dart';

void main() =>
    runApp(I18nExampleApp(setUpDemoI18n()), title: 'Internationalization');
