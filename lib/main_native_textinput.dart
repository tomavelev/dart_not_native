/// Runs the text-input showcase through the platform's OWN views, to exercise
/// the native editor path (floating labels, secure entry, focus/blur).
///
///   flutter run -t lib/main_native_textinput.dart -d `<device>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/textinput_showcase_app.dart';

void main() {
  runApp(const TextInputShowcaseApp(), title: 'Native TextInput');
}
