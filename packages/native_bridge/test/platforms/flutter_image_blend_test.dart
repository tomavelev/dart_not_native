/// Widget test for an image tint's blend mode in the Flutter renderer.
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

  testWidgets('a tint is blended as the node says', (tester) async {
    final image = await shown(
      tester,
      UIBuilder.image(
        src: 'assets/none.png',
        alt: 'a',
        color: '#2196F3',
        blend: 'multiply',
      ),
    );
    expect(image.colorBlendMode, BlendMode.multiply);
    expect(image.color, const Color(0xFF2196F3));
  });

  testWidgets('and as its own shape when it says nothing', (tester) async {
    final image = await shown(
      tester,
      UIBuilder.image(src: 'assets/none.png', alt: 'a', color: '#2196F3'),
    );
    expect(image.colorBlendMode, BlendMode.srcIn);
  });
}
