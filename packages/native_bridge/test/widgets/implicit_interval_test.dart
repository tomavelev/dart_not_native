/// An implicit animation given an [Interval] waits for the interval's start
/// before it moves, and moves over its share of the duration, along the
/// interval's own curve.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an opacity waits, then fades over the rest of the time', () async {
    final shown = ValueNotifier(false);
    final app = AppTester.widget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (_, on, _) => AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: const Interval(0.5, 1, curve: Curves.easeOut),
            child: const Text('late'),
          ),
        ),
      ),
    );
    Map<String, dynamic> fade() => app.ofType('AnimatedOpacity').single.props;
    expect(fade()['opacity'], 0);

    shown.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fade()['opacity'], 0);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(fade()['opacity'], 1);
    expect(fade()['durationMs'], 100);
    expect(fade()['curve'], Curves.easeOut.name);
  });

  test('one that starts at once moves over its share alone', () async {
    final shown = ValueNotifier(false);
    final app = AppTester.widget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (_, on, _) => AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: const Interval(0, 0.25),
            child: const Text('quick'),
          ),
        ),
      ),
    );
    shown.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final fade = app.ofType('AnimatedOpacity').single.props;
    expect(fade['opacity'], 1);
    expect(fade['durationMs'], 50);
  });
}
