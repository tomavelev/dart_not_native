/// The arithmetic behind a claim about smoothness.
///
/// The renderers each report frame intervals; what those intervals *mean* is
/// decided here, and this is the part that can be checked without a device.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// [count] intervals of [ms], the shape of a run with nothing wrong.
List<double> steady(int count, double ms) => List.filled(count, ms);

void main() {
  group('FrameStats', () {
    test('a steady 60Hz run is smooth and reads as the budget', () {
      final stats = FrameStats.fromIntervals(steady(120, 16.7), refreshHz: 60);

      expect(stats.frames, 120);
      expect(stats.budgetMs, closeTo(16.7, 0.1));
      expect(stats.meanMs, closeTo(16.7, 0.01));
      expect(stats.worstMs, closeTo(16.7, 0.01));
      expect(stats.jankFrames, 0);
      expect(stats.isSmooth(), isTrue);
    });

    test('a frame over budget is counted, one a shade late is not', () {
      // 17.2ms is within the tolerance; 33.4 is a dropped frame.
      final stats = FrameStats.fromIntervals(
        [...steady(98, 16.7), 17.2, 33.4],
        refreshHz: 60,
      );

      expect(stats.jankFrames, 1, reason: 'only the 33.4ms frame');
      expect(stats.worstMs, 33.4);
    });

    test('the budget follows the refresh rate', () {
      // 16.7ms is a whole frame at 60Hz and two missed ones at 120Hz.
      final intervals = steady(100, 16.7);

      expect(
        FrameStats.fromIntervals(intervals, refreshHz: 60).jankFrames,
        0,
      );
      expect(
        FrameStats.fromIntervals(intervals, refreshHz: 120).jankFrames,
        100,
      );
    });

    test('one stutter in two hundred still counts as smooth', () {
      final stats = FrameStats.fromIntervals(
        [...steady(199, 16.7), 50.0],
        refreshHz: 60,
      );

      expect(stats.jankFrames, 1);
      expect(stats.isSmooth(), isTrue, reason: '0.5% is under the 1% line');
      expect(
        stats.isSmooth(maxJankRatio: 0.001),
        isFalse,
        reason: 'a caller can demand better',
      );
    });

    test('a run that misses a tenth of its frames is not smooth', () {
      final stats = FrameStats.fromIntervals(
        [...steady(90, 16.7), ...steady(10, 33.4)],
        refreshHz: 60,
      );

      expect(stats.jankRatio, closeTo(0.1, 0.001));
      expect(stats.isSmooth(), isFalse);
    });

    test('percentiles come from the ordered intervals', () {
      // 1..100, so the p50 is the 50th and the p95 the 95th.
      final stats = FrameStats.fromIntervals(
        [for (var i = 100; i >= 1; i--) i.toDouble()],
        refreshHz: 60,
      );

      expect(stats.p50Ms, 50);
      expect(stats.p95Ms, 95);
      expect(stats.worstMs, 100);
    });

    test('an empty run says so rather than claiming a perfect one', () {
      final stats = FrameStats.fromIntervals([], refreshHz: 60);

      expect(stats.frames, 0);
      expect(stats.isSmooth(), isFalse, reason: 'nothing was measured');
      expect(stats.describe(), 'no frames recorded');
    });

    test('describe carries the numbers a report would quote', () {
      final stats = FrameStats.fromIntervals(
        [...steady(99, 16.7), 33.4],
        refreshHz: 60,
      );

      expect(stats.describe(), contains('100 frames @ 60Hz'));
      expect(stats.describe(), contains('budget 16.7ms'));
      expect(stats.describe(), contains('worst 33.4'));
      expect(stats.describe(), contains('janky 1 (1.0%)'));
    });
  });

  group('the wire format', () {
    test('a native renderer sends intervals and the arithmetic happens here', () {
      final stats = FrameStats.fromJson({
        'intervalsMs': [16.7, 16.7, 33.4],
        'refreshHz': 60.0,
      })!;

      expect(stats.frames, 3);
      expect(stats.jankFrames, 1);
    });

    test('a summary already computed round trips', () {
      final original = FrameStats.fromIntervals(
        [...steady(50, 8.3), 20.0],
        refreshHz: 120,
      );
      final restored = FrameStats.fromJson(original.toJson())!;

      expect(restored.frames, original.frames);
      expect(restored.refreshHz, original.refreshHz);
      expect(restored.worstMs, original.worstMs);
      expect(restored.jankFrames, original.jankFrames);
    });

    test('a null payload is null, not an empty run', () {
      expect(FrameStats.fromJson(null), isNull);
    });
  });

  group('FrameProbe.unavailable', () {
    test('answers null, so "not measured" cannot read as "measured zero"', () async {
      await FrameProbe.unavailable.start();

      expect(await FrameProbe.unavailable.stop(), isNull);
    });
  });
}
