/// A box that follows a scroller (`scrollLink`) is built again each frame the
/// scroller moves, from its table, in the Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a header shrinks and fades in step with the drag', (
    tester,
  ) async {
    final renderer = FlutterUIRenderer();
    final header = WidgetNode(
      type: 'Box',
      props: {
        'height': 120.0,
        'expand': 'width',
        'color': '#2196f3',
        'scrollLink': {
          'source': 'scroll0',
          'at': [0.0, 64.0],
          'height': [120.0, 56.0],
          'opacity': [0.2, 1.0],
          'color': ['#ff000000', '#ff0000ff'],
        },
      },
      children: [UIBuilder.text('title')],
    );
    final list = WidgetNode(
      type: 'Scroll',
      props: {'scrollEventId': 'cb:list', 'scrollLinkSource': 'scroll0'},
      children: [
        UIBuilder.column(
          children: [
            for (var i = 0; i < 60; i++) UIBuilder.text('row $i'),
          ],
        ),
      ],
    );
    await renderer.render(
      UIBuilder.column(
        children: [
          header,
          UIBuilder.expanded(child: list),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: renderer.build)));

    double height() => tester.getSize(find.ancestor(
          of: find.text('title'),
          matching: find.byType(Container),
        ).first).height;
    expect(height(), 120);

    // Half way along the table, held there by the finger.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row 10')),
    );
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -32));
    await tester.pump();
    final scrolled = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(scrolled, greaterThan(10));
    expect(height(), closeTo(120 - 64 * (scrolled.clamp(0, 64) / 64), 1));

    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(height(), 56);
    final painted = tester
        .widgetList<Container>(find.ancestor(
          of: find.text('title'),
          matching: find.byType(Container),
        ))
        .map((c) => c.color ?? (c.decoration as BoxDecoration?)?.color)
        .whereType<Color>();
    expect(painted, contains(const Color(0xFF0000FF)));
    await gesture.up();
  });

  testWidgets('a floating box goes as the list goes down, and comes back '
      'as soon as it comes up', (tester) async {
    final renderer = FlutterUIRenderer();
    final bar = WidgetNode(
      type: 'Box',
      props: {
        'height': 56.0,
        'expand': 'width',
        'scrollFloat': {'source': 'scroll0', 'extent': 56.0},
      },
      children: [UIBuilder.text('bar')],
    );
    final list = WidgetNode(
      type: 'Scroll',
      props: {'scrollEventId': 'cb:list', 'scrollLinkSource': 'scroll0'},
      children: [
        UIBuilder.column(
          children: [for (var i = 0; i < 60; i++) UIBuilder.text('row $i')],
        ),
      ],
    );
    await renderer.render(
      UIBuilder.column(children: [bar, UIBuilder.expanded(child: list)]),
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: renderer.build)));
    double top() => tester.getTopLeft(find.text('bar')).dy;
    final start = top();
    final gesture = await tester.startGesture(tester.getCenter(find.text('row 10')));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(top(), closeTo(start - 56, 1));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(top(), closeTo(start - 26, 1));
    await gesture.up();
  });
}
