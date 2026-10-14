/// Widget test for a box that stays at the top of its scroller (`sticky`)
/// in the Flutter renderer: the scroller is built of slivers, the box a
/// pinned header.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a sticky box stays at the top once scrolled past', (
    tester,
  ) async {
    final renderer = FlutterUIRenderer();
    await renderer.render(
      UIBuilder.scroll(
        child: UIBuilder.column(
          children: [
            UIBuilder.box(height: 300, color: '#eeeeee'),
            WidgetNode(
              type: 'Box',
              props: const {'sticky': true, 'height': 40, 'color': '#3f51b5'},
              children: [UIBuilder.text('Section')],
            ),
            UIBuilder.box(height: 2000, color: '#ffffff'),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(height: 500, child: Builder(builder: renderer.build)),
      ),
    );
    expect(find.byType(PinnedHeaderSliver), findsOneWidget);
    expect(tester.getTopLeft(find.text('Section')).dy, closeTo(300, 13));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Section')).dy, lessThan(13));
  });
}
