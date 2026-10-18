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
}
