/// The smallest app that uses dart_not_native, on every target.
///
/// The screen below is the whole app. It is not a Flutter widget: it builds a
/// tree that each platform draws with its own UI.
///
///   flutter run                      # Flutter paints the tree
///   flutter run --dart-define=...    # see nativeViews below for Android/iOS
///   dart compile js -o web/main.dart.js lib/main.dart   # DOM, no Flutter
///
/// For the web build, copy the shell from the package's `web_shell/` next to
/// the compiled `main.dart.js`.
library;

import 'package:dart_not_native/run_app.dart';

void main() => runNativeApp(CounterApp());

class CounterApp extends NativeUIApp {
  int count = 0;

  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Counter'),
    body: UIBuilder.center(
      child: UIBuilder.column(
        children: [
          UIBuilder.text('You have pushed the button this many times:'),
          UIBuilder.text('$count', fontSize: 34, id: 'count'),
          UIBuilder.sizedBox(height: 24),
          UIBuilder.button(
            label: 'Reset',
            variant: 'tertiary',
            onPressed: () => setState(() => count = 0),
          ),
        ],
      ),
    ),
    floatingActionButton: UIBuilder.floatingActionButton(
      tooltip: 'Increment',
      onPressed: () => setState(() => count++),
    ),
  );
}
