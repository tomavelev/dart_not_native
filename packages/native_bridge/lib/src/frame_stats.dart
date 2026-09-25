/// What a run of frames says about smoothness.
///
/// The renderers can each report the intervals between the frames they
/// presented; this turns a list of those into the few numbers worth quoting.
/// It is deliberately plain Dart, so the arithmetic behind a claim like "the
/// list scrolls at the display's refresh rate" is testable without a device.
library;

/// The frame intervals of one recording, summarised.
///
/// [intervalsMs] are the gaps between consecutive presented frames, so a run at
/// 60Hz reads as a series of ~16.7ms. A frame the renderer missed shows up as one
/// long interval rather than a missing entry, which is why [jankFrames] counts
/// intervals over budget rather than comparing a frame count against elapsed
/// time.
class FrameStats {
  FrameStats._({
    required this.frames,
    required this.refreshHz,
    required this.meanMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.worstMs,
    required this.jankFrames,
  });

  /// Summarises [intervalsMs], measured on a display running at [refreshHz].
  ///
  /// [toleranceMs] is the slack allowed before an interval counts as janky: a
  /// frame presented a fraction late is the timer's rounding, not a stutter.
  factory FrameStats.fromIntervals(
    List<double> intervalsMs, {
    required double refreshHz,
    double toleranceMs = 1.0,
  }) {
    if (intervalsMs.isEmpty || refreshHz <= 0) {
      return FrameStats._(
        frames: 0,
        refreshHz: refreshHz,
        meanMs: 0,
        p50Ms: 0,
        p95Ms: 0,
        worstMs: 0,
        jankFrames: 0,
      );
    }
    final sorted = [...intervalsMs]..sort();
    final budget = 1000 / refreshHz;
    return FrameStats._(
      frames: sorted.length,
      refreshHz: refreshHz,
      meanMs: sorted.reduce((a, b) => a + b) / sorted.length,
      p50Ms: _percentile(sorted, 0.50),
      p95Ms: _percentile(sorted, 0.95),
      worstMs: sorted.last,
      jankFrames: sorted.where((ms) => ms > budget + toleranceMs).length,
    );
  }

  /// The [fraction] percentile of [sorted], by nearest rank.
  static double _percentile(List<double> sorted, double fraction) {
    final rank = (fraction * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  /// How many intervals were recorded. One fewer than the frames presented,
  /// since an interval needs two of them.
  final int frames;

  /// The display's refresh rate, which sets the budget every frame is measured
  /// against - 16.7ms at 60Hz, 8.3ms at 120Hz.
  final double refreshHz;

  final double meanMs;
  final double p50Ms;
  final double p95Ms;

  /// The longest interval: the worst stutter the run contained.
  final double worstMs;

  /// Intervals that ran over budget - the frames a viewer would see as a
  /// stutter.
  final int jankFrames;

  /// One frame's share of the display's time.
  double get budgetMs => refreshHz <= 0 ? 0 : 1000 / refreshHz;

  /// The share of frames that missed the budget, 0 to 1.
  double get jankRatio => frames == 0 ? 0 : jankFrames / frames;

  /// Whether the run held the display's refresh rate.
  ///
  /// Not "no frame was ever late": a scroll that drops one frame in two hundred
  /// is smooth to a viewer, and a threshold that admits nothing would make the
  /// measurement unusable on a debug build. [maxJankRatio] is where the line
  /// sits, defaulting to 1%.
  bool isSmooth({double maxJankRatio = 0.01}) =>
      frames > 0 && jankRatio <= maxJankRatio;

  /// A line fit for a log or a commit message.
  String describe() {
    if (frames == 0) return 'no frames recorded';
    String ms(double value) => value.toStringAsFixed(1);
    return '$frames frames @ ${refreshHz.toStringAsFixed(0)}Hz '
        '(budget ${ms(budgetMs)}ms): '
        'mean ${ms(meanMs)}, p50 ${ms(p50Ms)}, p95 ${ms(p95Ms)}, '
        'worst ${ms(worstMs)}, '
        'janky $jankFrames (${(jankRatio * 100).toStringAsFixed(1)}%)';
  }

  Map<String, Object?> toJson() => {
        'frames': frames,
        'refreshHz': refreshHz,
        'meanMs': meanMs,
        'p50Ms': p50Ms,
        'p95Ms': p95Ms,
        'worstMs': worstMs,
        'jankFrames': jankFrames,
      };

  /// Reads the summary a native renderer sent back.
  static FrameStats? fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return null;
    final intervals = json['intervalsMs'];
    if (intervals is List) {
      return FrameStats.fromIntervals(
        intervals.map((value) => (value as num).toDouble()).toList(),
        refreshHz: (json['refreshHz'] as num?)?.toDouble() ?? 60,
      );
    }
    return FrameStats._(
      frames: (json['frames'] as num?)?.toInt() ?? 0,
      refreshHz: (json['refreshHz'] as num?)?.toDouble() ?? 60,
      meanMs: (json['meanMs'] as num?)?.toDouble() ?? 0,
      p50Ms: (json['p50Ms'] as num?)?.toDouble() ?? 0,
      p95Ms: (json['p95Ms'] as num?)?.toDouble() ?? 0,
      worstMs: (json['worstMs'] as num?)?.toDouble() ?? 0,
      jankFrames: (json['jankFrames'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => 'FrameStats(${describe()})';
}
