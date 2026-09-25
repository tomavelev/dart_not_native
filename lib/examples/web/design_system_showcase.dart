/// Web entry for the design system showcase: DOM + Material CSS, no Flutter.
/// Build with maestro/web/build_examples.sh.
import 'package:dart_not_native/web.dart';
import 'package:dart_not_native/widgets.dart' show hostApp;

import '../apps/design_system_showcase_app.dart';

void main() => runWebApp(hostApp(const DesignSystemShowcaseApp()));
