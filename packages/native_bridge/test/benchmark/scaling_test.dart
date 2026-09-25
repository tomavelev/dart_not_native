/// Performance as a property, not a number.
///
/// The benchmarks next door report timings, which are the machine's as much as
/// the code's - useful to a human comparing two runs, useless as a gate. What
/// *is* comparable between machines is the shape of the curve: four times the
/// rows should cost about four times as much, not sixteen. An accidental
/// O(n²) - a lookup inside a loop over children, a string rebuilt per node -
/// shows up here however fast or slow the machine is.
///
/// The thresholds are deliberately loose. This is a test for algorithmic
/// regressions, and a test that fails because a runner was busy is worse than
/// no test.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bench.dart';
import 'scenes.dart';

/// The median of [iterations] runs of [body], in microseconds.
int medianMicros(int iterations, void Function() body) {
  final bench = Bench(iterations: iterations, warmup: iterations ~/ 5)
    ..run('x', body);
  return bench.results.single.median;
}

void main() {
  test('building a tree scales with the number of rows, not their square', () {
    // 4x the rows. Anything quadratic would be ~16x; the ceiling is 8x, which
    // leaves room for a slow machine and none for a changed complexity class.
    final small = medianMicros(200, () => todoScene(items: 50));
    final large = medianMicros(200, () => todoScene(items: 200));

    expect(
      large,
      lessThan(small * 8),
      reason: 'todo(200) took ${large}us against todo(50) at ${small}us',
    );
  });

  test('serialising scales the same way', () {
    final small = todoScene(items: 50);
    final large = todoScene(items: 200);

    final smallMicros = medianMicros(200, small.toJson);
    final largeMicros = medianMicros(200, large.toJson);

    expect(
      largeMicros,
      lessThan(smallMicros * 8),
      reason: 'toJson of 200 rows took ${largeMicros}us '
          'against ${smallMicros}us for 50',
    );
  });

  test('a scene is the size it looks', () {
    // Guards the scaling tests themselves: if todoScene stopped growing with
    // its argument, the two above would compare a tree with itself and pass
    // whatever the code did.
    expect(countNodes(todoScene(items: 200)),
        greaterThan(countNodes(todoScene(items: 50)) * 3));
  });
}
