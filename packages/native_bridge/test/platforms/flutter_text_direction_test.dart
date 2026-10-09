/// The Flutter renderer turns the screen round when the tree's root says it
/// reads right to left, and leaves alone what names a side outright.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());
  tearDown(() => renderer.dispose());

  Future<void> show(
    WidgetTester tester,
    WidgetNode node, {
    bool rtl = false,
    TextDirection host = TextDirection.ltr,
  }) async {
    await renderer.render(UIBuilder.withTextDirection(node, rtl ? 'rtl' : null));
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: host,
          child: Builder(builder: renderer.build),
        ),
      ),
    );
  }

  WidgetNode screen() => WidgetNode(
    type: 'Scaffold',
    props: const {},
    children: [
      WidgetNode(
        type: 'AppBar',
        props: const {
          'title': 'Inbox',
          'leading': 'back',
          'leadingEventId': 'back',
        },
        children: [
          WidgetNode(
            type: 'IconButton',
            props: const {'icon': 'search', 'eventId': 'search'},
          ),
        ],
      ),
      UIBuilder.row(
        mainAxisSize: 'max',
        children: [
          UIBuilder.text('first'),
          UIBuilder.expanded(child: UIBuilder.text('middle')),
          UIBuilder.text('last'),
        ],
      ),
    ],
  );

  testWidgets('a tree that states no direction reads left to right', (
    tester,
  ) async {
    await show(tester, screen());

    expect(
      Directionality.of(tester.element(find.text('first'))),
      TextDirection.ltr,
    );
    expect(
      tester.getCenter(find.text('first')).dx,
      lessThan(tester.getCenter(find.text('last')).dx),
    );
    expect(tester.getCenter(find.byType(BackButtonIcon)).dx, lessThan(100));
  });

  testWidgets('rtl on the root runs a row from the right', (tester) async {
    await show(tester, screen(), rtl: true);

    expect(
      Directionality.of(tester.element(find.text('first'))),
      TextDirection.rtl,
    );
    expect(
      tester.getCenter(find.text('first')).dx,
      greaterThan(tester.getCenter(find.text('last')).dx),
    );
    expect(tester.getTopRight(find.text('first')).dx, 800);
  });

  testWidgets('and puts the app bar\'s leading on the right, actions left', (
    tester,
  ) async {
    await show(tester, screen(), rtl: true);

    expect(tester.getCenter(find.byType(BackButtonIcon)).dx, greaterThan(700));
    final action = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.search),
    );
    expect(tester.getCenter(action).dx, lessThan(100));
  });

  testWidgets('the direction can change from one render to the next', (
    tester,
  ) async {
    await show(tester, screen());
    final before = tester.getCenter(find.byType(BackButtonIcon)).dx;

    await show(tester, screen(), rtl: true);

    expect(
      tester.getCenter(find.byType(BackButtonIcon)).dx,
      greaterThan(before + 600),
    );
  });

  // The direction is the tree's to say: the same tree must draw the same way
  // inside a Flutter app that happens to be running in Arabic.
  testWidgets('a host that reads right to left does not turn an ltr tree', (
    tester,
  ) async {
    await show(tester, screen(), host: TextDirection.rtl);

    expect(
      tester.getCenter(find.text('first')).dx,
      lessThan(tester.getCenter(find.text('last')).dx),
    );
  });

  group('what names a side stays on that side', () {
    WidgetNode box(Map<String, dynamic> props, WidgetNode child) =>
        WidgetNode(type: 'Box', props: props, children: [child]);

    testWidgets('padding is left, top, right, bottom', (tester) async {
      await show(
        tester,
        box(const {
          'padding': [40.0, 0.0, 0.0, 0.0],
          'alignment': [-1.0, -1.0],
          'width': 300.0,
          'height': 100.0,
        }, UIBuilder.text('x')),
        rtl: true,
      );

      final frame = tester.getTopLeft(find.byType(Container).first).dx;
      expect(tester.getTopLeft(find.text('x')).dx, frame + 40);
    });

    testWidgets('a Positioned left is the left', (tester) async {
      await show(
        tester,
        WidgetNode(
          type: 'Stack',
          props: const {'fit': 'expand'},
          children: [
            WidgetNode(
              type: 'Positioned',
              props: const {'left': 12.0, 'top': 0.0},
              children: [UIBuilder.text('pinned')],
            ),
          ],
        ),
        rtl: true,
      );

      final stack = tester.getTopLeft(find.byType(Stack).last).dx;
      expect(tester.getTopLeft(find.text('pinned')).dx, stack + 12);
    });

    testWidgets('textAlign left is left, and no textAlign is the start', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          crossAxisAlignment: 'stretch',
          children: [
            WidgetNode(
              type: 'Text',
              props: const {'content': 'said', 'textAlign': 'left'},
            ),
            UIBuilder.text('unsaid'),
          ],
        ),
        rtl: true,
      );

      expect(tester.widget<Text>(find.text('said')).textAlign, TextAlign.left);
      // Nothing stated: Flutter starts it where the direction says, which the
      // text's own right edge at the screen's right edge shows.
      expect(tester.widget<Text>(find.text('unsaid')).textAlign, isNull);
    });
  });

  testWidgets('a stack that states no alignment starts at the top start', (
    tester,
  ) async {
    await show(
      tester,
      WidgetNode(
        type: 'Stack',
        props: const {},
        children: [
          WidgetNode(
            type: 'Box',
            props: const {'width': 300.0, 'height': 50.0},
          ),
          UIBuilder.text('s'),
        ],
      ),
      rtl: true,
    );

    final stack = find.byType(Stack).last;
    expect(tester.getTopRight(find.text('s')).dx, tester.getTopRight(stack).dx);
  });
}
