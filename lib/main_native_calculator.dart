/// Runs the calculator - a plain Flutter `StatefulWidget` - through the
/// platform's own views. The only thing non-Flutter about it is the import.
///
///   flutter run -t lib/main_native_calculator.dart -d `<device>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/calculator_app.dart';

void main() {
  runApp(const CalculatorApp(), title: 'Native Calculator');
}
