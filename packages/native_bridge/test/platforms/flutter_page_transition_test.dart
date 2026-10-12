/// Widget tests for a page transition in the Flutter renderer: both pages
/// are on screen while one gives way to the other.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());

  WidgetNode page(String name, {String? kind, int ms = 200}) =>
      UIBuilder.withPageTransition(
        UIBuilder.scaffold(body: UIBuilder.text(name)),
        kind == null ? null : {'kind': kind, 'ms': ms},
      );

  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
  }

  testWidgets('another tree is simply shown', (tester) async {
    await show(tester, page('one'));
    await show(tester, page('two'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('a pushed page comes in over the old one', (tester) async {
    await show(tester, page('one'));
    await show(tester, page('two', kind: 'push'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    final moving = tester.getTopLeft(find.text('two')).dx;

    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(
      tester.getTopLeft(find.text('two')).dx,
      lessThan(moving),
      reason: 'it slid in from the end of the screen',
    );
  });

  testWidgets('a transition said on a tree that was replaced before it was '
      'built is still shown', (tester) async {
    await show(tester, page('one'));
    await renderer.render(page('two', kind: 'push'));
    await show(tester, page('two'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('a rebuild of the same tree is not another page', (tester) async {
    await show(tester, page('one'));
    final two = page('two', kind: 'push');
    await show(tester, two);
    await tester.pumpAndSettle();
    // Built again, from the tree it already has.
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('two'), findsOneWidget);
    expect(find.text('one'), findsNothing);
  });

  testWidgets('a page takes the time it was given', (tester) async {
    await show(tester, page('one'));
    await show(tester, page('two', kind: 'fade', ms: 1000));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('one'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('one'), findsNothing);
  });

  testWidgets('the page that leaves takes no taps', (tester) async {
    final taps = <String>[];
    renderer.onEvent('old', (_) => taps.add('old'));
    await show(
      tester,
      UIBuilder.scaffold(body: UIBuilder.button(label: 'Old', eventId: 'old')),
    );
    await show(tester, page('two', kind: 'fade', ms: 1000));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Old'), warnIfMissed: false);
    expect(taps, isEmpty);
    await tester.pumpAndSettle();
  });
}
