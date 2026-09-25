/// Minimal timing helper for the render benchmarks.
///
/// Not a test: these report numbers rather than assert on them, because the
/// numbers depend on the machine. Run them before and after a change and
/// compare the two reports - `BASELINE.md` next door holds one such run and
/// says which machine it came from.
///
/// What *is* asserted, because it survives a change of machine, lives in
/// `scaling_test.dart` (the shape of the curve) and
/// `../web_ui/render_cost_test.dart` (patching beats rebuilding, a tick's
/// renders are coalesced).
///
/// Every report also prints one `BENCH_JSON {...}` line, so a CI run can keep
/// its numbers as an artifact instead of losing them with the log.
library;

import 'dart:convert';

/// Runs [body] [iterations] times after [warmup] untimed runs, and reports.
class Bench {
  Bench({this.iterations = 200, this.warmup = 20});

  final int iterations;
  final int warmup;
  final List<_Result> results = [];

  void run(String name, void Function() body) {
    for (var i = 0; i < warmup; i++) {
      body();
    }

    final samples = <int>[];
    final stopwatch = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      stopwatch
        ..reset()
        ..start();
      body();
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    results.add(_Result(name, samples));
  }

  /// Like [run], for a body that has to be awaited.
  Future<void> runAsync(String name, Future<void> Function() body) async {
    for (var i = 0; i < warmup; i++) {
      await body();
    }

    final samples = <int>[];
    final stopwatch = Stopwatch();
    for (var i = 0; i < iterations; i++) {
      stopwatch
        ..reset()
        ..start();
      await body();
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    results.add(_Result(name, samples));
  }

  /// The run as data: what was measured, how often, and what it cost.
  Map<String, Object?> toJson(String title) => {
        'title': title,
        'iterations': iterations,
        'warmup': warmup,
        'results': [
          for (final result in results)
            {
              'name': result.name,
              'medianMicros': result.median,
              'p95Micros': result.p95,
            },
        ],
      };

  /// Prints one line per case: median and 95th percentile per run.
  void report(String title) {
    final width = results.fold<int>(
      0,
      (widest, r) => r.name.length > widest ? r.name.length : widest,
    );
    // ignore: avoid_print
    print('\n=== $title (${iterations}x) ===');
    for (final result in results) {
      // ignore: avoid_print
      print(
        '${result.name.padRight(width)}  '
        'median ${_ms(result.median)}  p95 ${_ms(result.p95)}',
      );
    }
    // One machine-readable line per report, so a CI run can keep its numbers
    // as an artifact instead of losing them with the log.
    // ignore: avoid_print
    print('BENCH_JSON ${jsonEncode(toJson(title))}');
  }

  static String _ms(int micros) =>
      '${(micros / 1000).toStringAsFixed(3).padLeft(7)} ms';
}

class _Result {
  _Result(this.name, this.samples);

  final String name;
  final List<int> samples;

  int get median => samples[samples.length ~/ 2];
  int get p95 => samples[(samples.length * 95) ~/ 100];
}
