/// A windowed list whose rows say no height of their own lays them out at
/// their own heights in the Flutter renderer, and says what they came to.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('rows are their own heights, and the heights are sent', (
    tester,
  ) async {
    final renderer = FlutterUIRenderer();
    final heard = <Map<String, dynamic>>[];
    renderer.onEvent('m', heard.add);
    renderer.onEvent('r', (_) {});
    await renderer.render(
      WidgetNode(
        type: 'LazyList',
        props: {
          'id': 'list',
          'itemCount': 100,
          'extents': [56.0, 56.0, 56.0],
          'startOffset': 0.0,
          'totalExtent': 5600.0,
          'startIndex': 0,
          'rangeEventId': 'r',
          'measureEventId': 'm',
        },
        children: [
          for (final h in [80.0, 40.0, 56.0])
            UIBuilder.box(height: h, child: UIBuilder.text('row $h')),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: renderer.build)));
    await tester.pump();

    expect(tester.getTopLeft(find.text('row 40.0')).dy, 80);
    expect(tester.getTopLeft(find.text('row 56.0')).dy, 120);
    expect(heard, [
      {'start': 0, 'heights': [80.0, 40.0, 56.0]},
    ]);
  });

  testWidgets('the row on screen stays put when the heights above change', (
    tester,
  ) async {
    final renderer = FlutterUIRenderer();
    renderer.onEvent('m', (_) {});
    renderer.onEvent('r', (_) {});
    WidgetNode list(double startOffset) => WidgetNode(
      type: 'LazyList',
      props: {
        'id': 'list',
        'itemCount': 100,
        'extents': [for (var i = 0; i < 10; i++) 50.0],
        'startOffset': startOffset,
        'totalExtent': 5000.0 + startOffset,
        'startIndex': 10,
        'rangeEventId': 'r',
        'measureEventId': 'm',
      },
      children: [
        for (var i = 10; i < 20; i++)
          UIBuilder.box(height: 50, child: UIBuilder.text('row $i')),
      ],
    );
    await renderer.render(list(500));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: renderer.build)));
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(520);
    await tester.pump();
    final before = tester.getTopLeft(find.text('row 12')).dy;

    // The rows above the window turned out 100 taller than guessed.
    await renderer.render(list(600));
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(find.text('row 12')).dy, closeTo(before, 1));
  });
}
