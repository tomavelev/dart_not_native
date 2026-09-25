/// Recording how smoothly a screen actually drew.
///
/// The benchmarks in `test/benchmark` measure the Dart side - how long a tree
/// takes to build and reconcile - which is the part that runs anywhere. What
/// they cannot answer is the question `TODO.md` §1.4 asks: does a 10,000-row
/// list scroll at the display's refresh rate on a real device? Only the thing
/// doing the drawing knows that, so each renderer reports its own frame
/// intervals and [FrameStats] does the arithmetic.
///
/// A probe is off until it is started, and costs nothing until then.
library;

import 'frame_stats.dart';

/// Records the frames a renderer presents, between [start] and [stop].
///
/// ```dart
/// final probe = renderer.frameProbe;
/// await probe.start();
/// // ... scroll the list ...
/// print((await probe.stop())?.describe());
/// ```
///
/// A renderer with no way to see its own frames returns [unavailable], whose
/// [stop] answers null - so calling code reads "not measured here" rather than
/// a plausible zero.
abstract class FrameProbe {
  /// Begins recording, discarding anything a previous run left.
  Future<void> start();

  /// Stops recording and summarises what was seen, or null if this target
  /// cannot measure its own frames.
  Future<FrameStats?> stop();

  /// A probe for a target that cannot see its frames.
  static const FrameProbe unavailable = _UnavailableProbe();
}

/// A renderer that can measure its own frames.
///
/// Separate from `NativeUIRenderer` on purpose: a renderer is useful without
/// this, and a host or a test double should not have to answer for a
/// measurement it never takes. `NativeUIApp.frameProbe` checks for it and hands
/// back [FrameProbe.unavailable] when it is not there.
abstract class HasFrameProbe {
  FrameProbe get frameProbe;
}

class _UnavailableProbe implements FrameProbe {
  const _UnavailableProbe();

  @override
  Future<void> start() async {}

  @override
  Future<FrameStats?> stop() async => null;
}
