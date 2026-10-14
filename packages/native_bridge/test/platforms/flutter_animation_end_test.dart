/// Widget test for a moving node's ask to be told when it has got there
/// (`endEventId`, `endAsk`), in the Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a fade says so once it has got there', (tester) async {
    final renderer = FlutterUIRenderer();
    final said = <int>[];
    renderer.onEvent('end', (data) => said.add(data['ask'] as int));

    WidgetNode fade(double opacity, {int? ask}) => WidgetNode(
      type: 'AnimatedOpacity',
      props: {
        'opacity': opacity,
        'durationMs': 200,
        if (ask != null) 'endEventId': 'end',
        'endAsk': ?ask,
      },
      children: [UIBuilder.text('hi')],
    );

    await renderer.render(fade(1));
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
    await renderer.render(fade(0.2, ask: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(said, isEmpty);
    await tester.pump(const Duration(milliseconds: 150));
    expect(said, [1]);
  });

  testWidgets('a cubic curve is drawn as that cubic', (tester) async {
    final renderer = FlutterUIRenderer();
    await renderer.render(
      const WidgetNode(
        type: 'AnimatedOpacity',
        props: {
          'opacity': 0.5,
          'durationMs': 200,
          'curve': 'cubic(0.4,0.0,0.2,1.0)',
        },
        children: [WidgetNode(type: 'Text', props: {'content': 'hi'})],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
    final fade = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    final cubic = fade.curve as Cubic;
    expect([cubic.a, cubic.b, cubic.c, cubic.d], [0.4, 0.0, 0.2, 1.0]);
  });
}
