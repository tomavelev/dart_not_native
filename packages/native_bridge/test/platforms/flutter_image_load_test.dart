/// Widget test for an image that asked how its load ended, in the Flutter
/// renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;
  late List<String> said;

  setUp(() {
    renderer = FlutterUIRenderer();
    said = [];
    renderer.onEvent('img', (data) => said.add(data['state'] as String));
  });

  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
  }

  testWidgets('an asset that is not there says it failed', (tester) async {
    await show(
      tester,
      UIBuilder.image(src: 'assets/none.png', alt: 'a', eventId: 'img'),
    );
    await tester.pumpAndSettle();

    expect(said, contains('failed'));
    expect(said, isNot(contains('loaded')));
  });

  testWidgets('and its stand-in is what shows', (tester) async {
    await show(
      tester,
      UIBuilder.image(
        src: 'assets/none.png',
        alt: 'a',
        eventId: 'img',
        fallback: UIBuilder.text('no picture'),
      ),
    );
    await tester.pumpAndSettle();

    expect(said, contains('failed'));
    expect(find.text('no picture'), findsOneWidget);
  });

  testWidgets('an image that did not ask is not answered', (tester) async {
    await show(tester, UIBuilder.image(src: 'assets/none.png', alt: 'a'));
    await tester.pumpAndSettle();

    expect(said, isEmpty);
  });
}
