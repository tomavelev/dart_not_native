/// The frame probe of the Android and iOS renderers, over their method channel.
library;

import 'package:flutter/services.dart';

import '../src/frame_probe.dart';
import '../src/frame_stats.dart';

/// Asks the native renderer to record the frames it presents.
///
/// The native halves watch the display itself - a `CADisplayLink` on iOS, the
/// `Choreographer` on Android - because on this target Flutter is only hosting
/// the engine: the views on screen are the platform's, and Flutter's own frame
/// timings would measure an empty screen.
class NativeFrameProbe implements FrameProbe {
  const NativeFrameProbe(this.channel);

  final MethodChannel channel;

  @override
  Future<void> start() => channel.invokeMethod('startFrameProbe');

  @override
  Future<FrameStats?> stop() async {
    final result = await channel.invokeMethod('stopFrameProbe');
    return FrameStats.fromJson(result as Map<dynamic, dynamic>?);
  }
}
