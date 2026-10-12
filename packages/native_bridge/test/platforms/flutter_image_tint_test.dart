/// Widget test for a tinted image in the Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Image> shown(WidgetTester tester, WidgetNode node) async {
    final renderer = FlutterUIRenderer();
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
    return tester.widget<Image>(find.byType(Image));
  }

  testWidgets('a colour is the picture\'s shape filled with it', (tester) async {
    final image = await shown(
      tester,
      UIBuilder.image(src: 'assets/none.png', alt: 'a', color: '#ff0000'),
    );

    expect(image.color, const Color(0xFFFF0000));
    expect(image.colorBlendMode, BlendMode.srcIn);
  });

  testWidgets('no colour, no blend', (tester) async {
    final image = await shown(
      tester,
      UIBuilder.image(src: 'assets/none.png', alt: 'a'),
    );

    expect(image.color, isNull);
    expect(image.colorBlendMode, isNull);
  });
}
