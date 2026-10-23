/// Widget tests for a box that animates its padding and its alignment in the
/// Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:dart_not_native/widgets.dart' as w;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());

  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
  }

  WidgetNode padded(double inset, {int? animateMs = 200}) => UIBuilder.box(
    padding: [inset, 0, 0, 0],
    animateMs: animateMs,
    child: UIBuilder.text('child'),
  );

  WidgetNode aligned(List<double> alignment) => UIBuilder.box(
    width: 300,
    height: 100,
    alignment: alignment,
    animateMs: 200,
    child: UIBuilder.text('child'),
  );

  testWidgets('padding travels over the time given', (tester) async {
    await show(tester, padded(0));
    final from = tester.getTopLeft(find.text('child')).dx;
    await show(tester, padded(100));
    await tester.pump(const Duration(milliseconds: 100));

    final midway = tester.getTopLeft(find.text('child')).dx - from;
    expect(midway, greaterThan(5));
    expect(midway, lessThan(95));

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('child')).dx - from, 100);
  });

  testWidgets('a bounce falls back on its way', (tester) async {
    WidgetNode wide(double width) => WidgetNode(
      type: 'Box',
      props: {
        'width': width,
        'height': 20.0,
        'color': '#e91e63',
        'animateMs': 1000,
        'curve': w.Curves.bounceOut.name,
      },
      children: [UIBuilder.text('bounced')],
    );
    await show(tester, UIBuilder.center(child: wide(0)));
    await show(tester, UIBuilder.center(child: wide(300)));
    double width() => tester
        .getSize(
          find
              .ancestor(of: find.text('bounced'), matching: find.byType(Container))
              .first,
        )
        .width;
    final seen = <double>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(width());
    }
    var falls = 0;
    for (var i = 1; i < seen.length; i++) {
      if (seen[i] < seen[i - 1] - 0.5) falls++;
    }
    expect(falls, greaterThan(2), reason: '$seen');
    await tester.pumpAndSettle();
    expect(width(), 300);
  });

  testWidgets('without a time it lands at once', (tester) async {
    await show(tester, padded(0, animateMs: null));
    final from = tester.getTopLeft(find.text('child')).dx;
    await show(tester, padded(100, animateMs: null));

    expect(tester.getTopLeft(find.text('child')).dx - from, 100);
  });

  testWidgets('an alignment travels too', (tester) async {
    await show(tester, aligned([-1, 0]));
    final from = tester.getTopLeft(find.text('child')).dx;
    await show(tester, aligned([1, 0]));
    await tester.pump(const Duration(milliseconds: 100));

    final midway = tester.getTopLeft(find.text('child')).dx - from;
    expect(midway, greaterThan(5));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('child')).dx - from, greaterThan(midway));
  });

  testWidgets('a whole turn goes round, though it ends where it began', (
    tester,
  ) async {
    WidgetNode turned(double angle) => UIBuilder.box(
      width: 100,
      height: 20,
      transform: {'rotate': angle},
      animateMs: angle == 0 ? 0 : 1000,
      curve: 'linear',
      child: UIBuilder.text('child'),
    );
    await show(tester, turned(0));
    final from = tester.getTopLeft(find.text('child'));
    await show(tester, turned(2 * 3.141592653589793));
    await tester.pump(const Duration(milliseconds: 500));
    // Half way round, the text's first corner is at the far side.
    final midway = tester.getTopLeft(find.text('child'));
    expect((midway - from).distance, greaterThan(20));
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(find.text('child'));
    expect((end - from).distance, lessThan(0.5));
  });
}
