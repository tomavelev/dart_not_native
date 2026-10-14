/// Widget test for a box that moves to the size its child comes to
/// (`animateSize`), in the Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a box whose child grows moves to the new size', (tester) async {
    final renderer = FlutterUIRenderer();
    WidgetNode sized(double inner) => UIBuilder.box(
      animateSize: true,
      animateMs: 300,
      clip: true,
      id: 'outer',
      child: UIBuilder.box(width: 50, height: inner),
    );
    Future<void> show(WidgetNode node) async {
      await renderer.render(node);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: Builder(builder: renderer.build),
          ),
        ),
      );
    }

    await show(sized(20));
    final outer = find.byType(AnimatedSize);
    expect(tester.getSize(outer).height, 20);

    await show(sized(120));
    await tester.pump(const Duration(milliseconds: 100));
    final between = tester.getSize(outer).height;
    expect(between, greaterThan(20));
    expect(between, lessThan(120));

    await tester.pumpAndSettle();
    expect(tester.getSize(outer).height, 120);
  });

  testWidgets('and says so when it is there', (tester) async {
    final renderer = FlutterUIRenderer();
    var ended = 0;
    renderer.onEvent('ended', (_) => ended++);
    WidgetNode sized(double inner) => WidgetNode(
      type: 'Box',
      props: {'animateSize': true, 'animateMs': 200, 'sizeEndEventId': 'ended'},
      children: [UIBuilder.box(width: 50, height: inner)],
    );
    Future<void> show(WidgetNode node) async {
      await renderer.render(node);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: Builder(builder: renderer.build),
          ),
        ),
      );
    }

    await show(sized(20));
    await show(sized(120));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ended, 0);
    await tester.pumpAndSettle();
    expect(ended, 1);
  });
}
