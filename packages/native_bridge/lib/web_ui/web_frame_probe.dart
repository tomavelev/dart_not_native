/// The frame probe of the web renderer.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/frame_probe.dart';
import '../src/frame_stats.dart';

/// Records the browser's frame callbacks.
///
/// `requestAnimationFrame` fires once per presented frame, so the gaps between
/// its timestamps are the frame intervals - the same quantity the native probes
/// report, measured the way the platform offers.
class WebFrameProbe implements FrameProbe {
  WebFrameProbe({web.Window? window}) : _window = window ?? web.window;

  final web.Window _window;
  final List<double> _intervalsMs = [];
  double? _previous;
  int? _handle;

  @override
  Future<void> start() async {
    await stop();
    _intervalsMs.clear();
    _previous = null;
    _schedule();
  }

  void _schedule() {
    _handle = _window.requestAnimationFrame(
      ((JSNumber timestamp) {
        final now = timestamp.toDartDouble;
        final previous = _previous;
        if (previous != null) _intervalsMs.add(now - previous);
        _previous = now;
        _schedule();
      }).toJS,
    );
  }

  @override
  Future<FrameStats?> stop() async {
    final handle = _handle;
    if (handle == null) return null;
    _window.cancelAnimationFrame(handle);
    _handle = null;
    return FrameStats.fromIntervals(_intervalsMs, refreshHz: _refreshHz());
  }

  /// The display's refresh rate, inferred from the frames just recorded: the
  /// browser exposes no such number, but it paces rAF to the display, so the
  /// fastest interval seen is one frame's length. Falls back to 60Hz before
  /// enough frames have been seen to tell.
  double _refreshHz() {
    if (_intervalsMs.length < 4) return 60;
    final fastest = _intervalsMs.reduce((a, b) => a < b ? a : b);
    if (fastest <= 0) return 60;
    // Snapped to the rates displays actually run at, so a 16.4ms sample does
    // not read as a 61Hz budget that every other frame then misses.
    const rates = [60.0, 90.0, 120.0, 144.0];
    final measured = 1000 / fastest;
    var closest = rates.first;
    for (final rate in rates) {
      if ((rate - measured).abs() < (closest - measured).abs()) closest = rate;
    }
    return closest;
  }
}
