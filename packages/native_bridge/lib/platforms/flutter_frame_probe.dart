/// The frame probe of the Flutter renderer.
library;

import 'package:flutter/scheduler.dart';

import '../src/frame_probe.dart';
import '../src/frame_stats.dart';

/// Records Flutter's own frame timings.
///
/// Correct only where Flutter is what draws - the Flutter-hosted target. On the
/// native-views target the same callback would report an idle engine behind the
/// platform's views, which is why that path uses [NativeFrameProbe] instead.
///
/// `FrameTiming.totalSpan` is the whole frame, build through raster, which is
/// the span a viewer feels.
class FlutterFrameProbe implements FrameProbe {
  final List<double> _intervalsMs = [];
  TimingsCallback? _callback;

  @override
  Future<void> start() async {
    await stop();
    _intervalsMs.clear();
    void record(List<FrameTiming> timings) {
      for (final timing in timings) {
        _intervalsMs.add(timing.totalSpan.inMicroseconds / 1000);
      }
    }

    _callback = record;
    SchedulerBinding.instance.addTimingsCallback(record);
  }

  @override
  Future<FrameStats?> stop() async {
    final callback = _callback;
    if (callback == null) return null;
    SchedulerBinding.instance.removeTimingsCallback(callback);
    _callback = null;
    return FrameStats.fromIntervals(
      _intervalsMs,
      refreshHz: _refreshHz(),
    );
  }

  /// The display's refresh rate, which sets the budget. 60Hz is the fallback
  /// where the platform will not say - a test binding, or a headless host.
  double _refreshHz() {
    final displays = SchedulerBinding.instance.platformDispatcher.displays;
    if (displays.isEmpty) return 60;
    final rate = displays.first.refreshRate;
    return rate > 0 ? rate : 60;
  }
}
