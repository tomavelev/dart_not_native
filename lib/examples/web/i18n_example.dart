/// Web entry for the i18n example: DOM + Material CSS, no Flutter.
/// Build with maestro/web/build_examples.sh.
import 'package:dart_not_native/web.dart';
import 'package:dart_not_native/widgets.dart' show hostApp;

import '../apps/i18n_example_app.dart';

void main() => runWebApp(hostApp(I18nExampleApp(setUpDemoI18n())));
