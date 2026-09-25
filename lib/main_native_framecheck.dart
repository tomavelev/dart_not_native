/// Measures how smoothly the 10,000-row inbox scrolls, natively.
///
/// `TODO.md` §1.4 asks whether that list holds the display's refresh rate on a
/// device. The benchmarks in `test/benchmark` cannot answer it - they measure
/// Dart-side tree work, not what the platform put on screen - so this runs the
/// real app and asks the renderer's own [FrameProbe].
///
///   flutter run -t lib/main_native_framecheck.dart -d `<device>`
///
/// It settles for [_settle], records for [_window], then prints one
/// `DNN_FRAMES` line. Scroll the list during the recording - by hand, or:
///
///   # Android, repeatedly during the window
///   adb shell input swipe 540 1600 540 400 300
///   # iOS simulator (a plain swipe does not register)
///   idb ui swipe 200 600 200 200 --duration 0.25 --delta 20 --udid `<udid>`
///
/// A run with no scrolling is worth taking too: it is the control, and it
/// should come back clean.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/run_app.dart';
import 'package:dart_not_native/widgets.dart';

import 'examples/apps/inbox_example_app.dart';

/// Long enough for the first render and the list's first window to land.
const _settle = Duration(seconds: 5);

/// Long enough to cover a few flings without the log growing unreadable.
const _window = Duration(seconds: 10);

Future<void> main() async {
  final app = hostApp(const InboxApp());
  await runNativeApp(app, nativeViews: true, title: 'Frame check');

  await Future<void>.delayed(_settle);
  await app.frameProbe.start();
  // ignore: avoid_print
  print('DNN_FRAMES recording for ${_window.inSeconds}s - scroll now');

  await Future<void>.delayed(_window);
  final stats = await app.frameProbe.stop();
  // ignore: avoid_print
  print(
    stats == null
        // Not a zero: this target cannot see its own frames, which is a
        // different answer from "it drew none".
        ? 'DNN_FRAMES unavailable - this renderer cannot measure its frames'
        : 'DNN_FRAMES ${stats.describe()} · '
              'smooth=${stats.isSmooth()}',
  );
}
