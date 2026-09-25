/// A golden comparator that forgives antialiasing and nothing else.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [LocalFileComparator] that treats two rasterisations of the same frame as
/// the same frame.
///
/// `matchesGoldenFile` compares byte for byte, which asks the wrong question of
/// a picture: the golden was rasterised once, on one machine, by one engine
/// build, and every later run is a different one. What drifts between them is
/// the coverage of a glyph's edge - the counter golden's floating action button
/// comes out two parts in 255 lighter on two of its pixels under Flutter 3.47.5
/// than under the 3.47.2 it was generated with on the same machine, which is
/// 0.0007% of the frame and not a fact about this project.
///
/// So the two things that would make it a fact are checked instead, and either
/// one is still a failure:
///
///  * **how far** a pixel moved. Antialiasing nudges a channel; a widget that
///    moved, changed colour or stopped being drawn replaces one. A drift of
///    more than [maxChannelDelta] is the second kind.
///  * **how much** of the frame moved. An edge is a handful of pixels; a
///    regression is a shape. More than [maxDrift] of the frame fails, as does a
///    frame that is not even the same size.
///
/// Both bounds are asserted in `test/gallery/tolerant_golden_comparator_test`,
/// which drives this class with frames built to sit either side of them.
class AntiAliasTolerantComparator extends LocalFileComparator {
  AntiAliasTolerantComparator(super.testFile);

  /// The most one channel of one pixel may drift and still be an edge.
  static const int maxChannelDelta = 4;

  /// The share of the frame allowed to drift at all - 0.01%, which is 27 of the
  /// counter golden's 270,000 pixels against the 2 that actually do.
  static const double maxDrift = 0.0001;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final master = Uint8List.fromList(await getGoldenBytes(golden));
    if (await isEdgeDrift(imageBytes, master)) return true;

    // Not forgivable, so hand it back to the strict comparison - which writes
    // the masked and isolated diffs that say what actually moved.
    final result = await GoldenFileComparator.compareLists(imageBytes, master);
    if (result.passed) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }

  /// Whether [test] differs from [master] only as two rasterisations of one
  /// frame differ.
  @visibleForTesting
  Future<bool> isEdgeDrift(Uint8List test, Uint8List master) async {
    final a = await _decode(test);
    final b = await _decode(master);
    if (a == null || b == null) return false;
    if (a.width != b.width || a.height != b.height) return false;

    final total = a.width * a.height;
    var drifted = 0;
    for (var pixel = 0; pixel < total; pixel++) {
      final offset = pixel * 4;
      var worst = 0;
      for (var channel = 0; channel < 4; channel++) {
        final delta =
            (a.bytes.getUint8(offset + channel) -
                    b.bytes.getUint8(offset + channel))
                .abs();
        if (delta > worst) worst = delta;
      }
      if (worst == 0) continue;
      if (worst > maxChannelDelta) return false;
      drifted++;
    }
    return drifted <= total * maxDrift;
  }

  /// The raw RGBA of a PNG, or null if it does not decode.
  Future<_Frame?> _decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final bytes = await image.toByteData();
    final width = image.width;
    final height = image.height;
    image.dispose();
    return bytes == null ? null : _Frame(width, height, bytes);
  }
}

/// One decoded frame: its size, and its pixels as RGBA bytes.
class _Frame {
  const _Frame(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final ByteData bytes;
}
