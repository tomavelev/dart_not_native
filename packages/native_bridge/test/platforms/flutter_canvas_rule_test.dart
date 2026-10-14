/// Widget test for a canvas path's even-odd fill and clip in the Flutter
/// renderer, read back by pixel.
library;

import 'dart:ui' as ui;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ring = [
    ['R', 0, 0, 100, 80],
    ['R', 30, 20, 40, 40],
  ];

  /// The picture [commands] draw, as RGBA bytes 100 pixels wide.
  Future<List<int>> drawn(
    WidgetTester tester,
    List<List<Object?>> commands,
  ) async {
    final renderer = FlutterUIRenderer();
    await renderer.render(
      UIBuilder.canvas(
        commands: commands,
        paints: const [
          {'color': '#ff0000'},
        ],
        width: 100,
        height: 80,
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: Builder(builder: renderer.build),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List().toList();
    });
    return bytes!;
  }

  int red(List<int> rgba, int x, int y) => rgba[(y * 100 + x) * 4];

  testWidgets('a path filled even-odd leaves its hole', (tester) async {
    final rgba = await drawn(tester, [
      ['path', ring, 0, 'evenOdd'],
    ]);
    expect(red(rgba, 10, 10), 255);
    expect(red(rgba, 50, 40), 0);
  });

  testWidgets('one filled without it is whole', (tester) async {
    final rgba = await drawn(tester, [
      ['path', ring, 0],
    ]);
    expect(red(rgba, 50, 40), 255);
  });

  testWidgets('a clip by it keeps the frame only', (tester) async {
    final rgba = await drawn(tester, [
      ['save'],
      ['clipPath', ring, 'evenOdd'],
      ['rect', 0, 0, 100, 80, 0],
      ['restore'],
    ]);
    expect(red(rgba, 10, 10), 255);
    expect(red(rgba, 50, 40), 0);
  });
}
