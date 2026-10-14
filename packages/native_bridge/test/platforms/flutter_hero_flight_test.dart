/// Widget test for a hero in the Flutter renderer: a box with the same name
/// on the page left and on the page arrived at flies from the one place to
/// the other.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());

  /// A page with one hero, [size] square, [down] from the top.
  WidgetNode page(String label, {required double size, required double down}) =>
      UIBuilder.column(
        children: [
          UIBuilder.sizedBox(height: down),
          UIBuilder.box(
            hero: 'picture',
            width: size,
            height: size,
            color: '#3366ff',
            child: UIBuilder.text(label),
          ),
        ],
      );

  WidgetNode pushed(WidgetNode tree, {int ms = 400}) =>
      UIBuilder.withPageTransition(tree, {'kind': 'push', 'ms': ms});

  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Builder(builder: renderer.build))),
    );
  }

  final flight = find.byKey(const ValueKey<String>('hero picture'));

  /// How visible the hero of the page with [label] is.
  double shown(WidgetTester tester, String label) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  testWidgets('the hero flies from where the old one stood', (tester) async {
    await show(tester, page('one', size: 40, down: 0));
    final from = tester.getRect(find.text('one').first);
    expect(flight, findsNothing);

    await show(tester, pushed(page('two', size: 120, down: 200)));
    // One frame for the new page to be laid out, one for the copy to appear.
    await tester.pump();
    await tester.pump();

    expect(flight, findsOneWidget);
    final start = tester.getRect(
      find.descendant(of: flight, matching: find.byType(FittedBox)),
    );
    expect(start.left, closeTo(from.left, 1));
    expect(start.top, closeTo(from.top, 1));
    expect(start.width, closeTo(40, 1));
    expect(
      find.descendant(of: flight, matching: find.text('two')),
      findsOneWidget,
      reason: 'the new one flies',
    );
  });

  testWidgets('neither hero is seen while the copy is in the air', (
    tester,
  ) async {
    await show(tester, page('one', size: 40, down: 0));
    await show(tester, pushed(page('two', size: 120, down: 200)));
    await tester.pump();
    await tester.pump();

    expect(shown(tester, 'one'), 0);
    // The copy has the new page's text too; the page's own is the first.
    expect(shown(tester, 'two'), 0);
  });

  testWidgets('it grows on the way, and lands where the new hero stands', (
    tester,
  ) async {
    await show(tester, page('one', size: 40, down: 0));
    await show(tester, pushed(page('two', size: 120, down: 200)));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final midway = tester.getRect(
      find.descendant(of: flight, matching: find.byType(FittedBox)),
    );
    expect(midway.width, inExclusiveRange(40, 120));
    expect(midway.top, greaterThan(0));

    await tester.pumpAndSettle();
    expect(flight, findsNothing);
    expect(find.text('one'), findsNothing);
    expect(shown(tester, 'two'), 1);
    expect(tester.getSize(find.text('two')).width, lessThanOrEqualTo(120));
  });

  testWidgets('a hero with no counterpart does not fly, and is seen', (
    tester,
  ) async {
    await show(tester, UIBuilder.column(children: [UIBuilder.text('plain')]));
    await show(tester, pushed(page('two', size: 120, down: 200)));
    await tester.pump();
    await tester.pump();

    expect(flight, findsNothing);
    expect(shown(tester, 'two'), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('with no page transition nothing flies', (tester) async {
    await show(tester, page('one', size: 40, down: 0));
    await show(tester, page('two', size: 120, down: 200));
    await tester.pump();
    await tester.pump();

    expect(flight, findsNothing);
    expect(shown(tester, 'two'), 1);
  });
}
