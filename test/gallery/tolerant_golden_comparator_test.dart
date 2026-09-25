/// What the tolerant golden comparator forgives, and what it does not.
///
/// The counter golden is compared with a tolerance, so the tolerance is worth
/// an assertion of its own: these drive [AntiAliasTolerantComparator] with
/// frames built to sit either side of each bound, rather than trusting that a
/// number in a doc comment means what it says.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tolerant_golden_comparator.dart';

/// A frame of [width] x [height], grey, as PNG bytes.
///
/// [drift] pixels have [delta] added to each of their channels, which is how a
/// rasteriser's disagreement about an edge looks: a few pixels, slightly off.
Future<Uint8List> frame({
  int width = 100,
  int height = 100,
  int drift = 0,
  int delta = 0,
}) async {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final moved = i < drift;
    for (var c = 0; c < 3; c++) {
      pixels[i * 4 + c] = 128 + (moved ? delta : 0);
    }
    pixels[i * 4 + 3] = 255;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final image = (await codec.getNextFrame()).image;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return png!.buffer.asUint8List();
}

void main() {
  late Directory dir;
  late AntiAliasTolerantComparator comparator;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tolerant_golden');
    comparator = AntiAliasTolerantComparator(
      Uri.file('${dir.path}${Platform.pathSeparator}a_test.dart'),
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Compares [test] against [master] through the real on-disk path.
  Future<bool> compare(Uint8List test, Uint8List master) async {
    File('${dir.path}${Platform.pathSeparator}master.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(master);
    return comparator.compare(test, Uri.parse('master.png'));
  }

  // 10,000 pixels a side of the bounds: 0.01% is one pixel, and a channel may
  // move 4.
  test('a frame identical to the golden passes', () async {
    expect(await compare(await frame(), await frame()), isTrue);
  });

  test('one edge pixel nudged is the drift this exists for', () async {
    final drifted = await frame(drift: 1, delta: 2);
    expect(await compare(drifted, await frame()), isTrue);
  });

  test('a channel moved further than an edge ever moves fails', () async {
    // One pixel only - well inside the share of the frame allowed - but moved
    // 40, which is a pixel replaced rather than resampled.
    final replaced = await frame(drift: 1, delta: 40);
    final master = await frame();
    await expectLater(() => compare(replaced, master), throwsA(isFlutterError));
  });

  test('a nudge across more of the frame than an edge covers fails', () async {
    // Each pixel moves 1, which on its own is forgiven; 200 of 10,000 is 2% of
    // the frame, which is a shape rather than an edge.
    final washed = await frame(drift: 200, delta: 1);
    final master = await frame();
    await expectLater(() => compare(washed, master), throwsA(isFlutterError));
  });

  test('a frame that is not even the same size fails', () async {
    final wider = await frame(width: 120);
    final master = await frame();
    await expectLater(() => compare(wider, master), throwsA(isFlutterError));
  });
}
