/// TextInput Showcase - rendered through the platform's own views.
///
/// The app is a plain Flutter `StatefulWidget` in
/// apps/textinput_showcase_app.dart; only the import (`widgets.dart`) renders it
/// natively rather than through the Flutter engine.
library;

import 'package:dart_not_native/widgets.dart';

import 'apps/textinput_showcase_app.dart';

void main() =>
    runApp(const TextInputShowcaseApp(), title: 'TextInput Showcase');
