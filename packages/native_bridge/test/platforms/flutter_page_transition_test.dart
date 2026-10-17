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

  testWidgets('a reveal shows the share of the page it says', (
    tester,
  ) async {
    await show(tester, page('one'));
    await show(
      tester,
      UIBuilder.withPageTransition(page('two'), {
        'kind': 'push',
        'ms': 400,
        'page': {
          'reveal': 0.25,
          'revealAxis': 'vertical',
          'revealAlign': -1,
        },
      }),
    );
    await tester.pump();
    final clip = tester.widget<ClipRect>(
      find.ancestor(of: find.text('two'), matching: find.byType(ClipRect)).last,
    );
    final shown = clip.clipper!.getClip(const Size(100, 200));
    expect(shown, const Rect.fromLTWH(0, 0, 100, 50));
    await tester.pumpAndSettle();
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

  testWidgets('a route\'s moves move both pages: the one beneath under the '
      'one pushed over it', (tester) async {
    await show(tester, page('one'));
    await show(
      tester,
      UIBuilder.withPageTransition(
        UIBuilder.scaffold(body: UIBuilder.text('two')),
        {
          'kind': 'push',
          'ms': 400,
          'page': {'dx': 1.0},
          'picture': {'dx': -0.5},
        },
      ),
    );
    final width = tester.getSize(find.byType(MaterialApp)).width;
    final oneAt = tester.getTopLeft(find.text('one')).dx;
    final twoAt = tester.getTopLeft(find.text('two')).dx;
    await tester.pump(const Duration(milliseconds: 200));

    // Half way: the old page a quarter of the screen to the start, the new
    // one half the screen short of its place.
    expect(
      tester.getTopLeft(find.text('one')).dx,
      closeTo(oneAt - width / 4, 1),
    );
    expect(
      tester.getTopLeft(find.text('two')).dx,
      closeTo(twoAt - width / 2, 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
  });

  testWidgets('and out from under the one popped off it', (tester) async {
    await show(tester, page('two'));
    await show(
      tester,
      UIBuilder.withPageTransition(
        UIBuilder.scaffold(body: UIBuilder.text('one')),
        {
          'kind': 'pop',
          'ms': 400,
          'picture': {'opacity': 0.0},
          'page': {'dx': -0.5},
        },
      ),
    );
    final width = tester.getSize(find.byType(MaterialApp)).width;
    await tester.pump(const Duration(milliseconds: 200));
    final opacities = tester
        .widgetList<Opacity>(
          find.ancestor(of: find.text('two'), matching: find.byType(Opacity)),
        )
        .map((o) => o.opacity);
    expect(opacities, contains(closeTo(0.5, 1e-6)));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('one')).dx, lessThan(width / 4));
    expect(find.text('two'), findsNothing);
  });
}
