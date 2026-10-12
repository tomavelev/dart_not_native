/// Widget tests for a box that animates its padding and its alignment in the
/// Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
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
}
