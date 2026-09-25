/// A dialog's actions stay in reach of a long body.
///
/// Confirm and Cancel scrolling away below the fold only shows up with real
/// content in the dialog, which is why it sat written down rather than found.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());
  tearDown(() => renderer.dispose());

  /// A dialog whose body is far taller than the surface can show.
  WidgetNode longDialog({List<WidgetNode> actions = const []}) =>
      UIBuilder.overlay(
        child: UIBuilder.column(children: [UIBuilder.text('Behind')]),
        overlays: [
          UIBuilder.dialog(
            title: 'Long',
            content: [
              for (var i = 0; i < 40; i++) UIBuilder.text('Line $i'),
            ],
            actions: actions,
          ),
        ],
      );

  Future<void> show(WidgetTester tester, WidgetNode tree) async {
    await renderer.render(tree);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: renderer.build)));
    await tester.pumpAndSettle();
  }

  testWidgets('they stay on screen when the content overflows', (tester) async {
    await show(
      tester,
      longDialog(actions: [
        UIBuilder.button(label: 'Cancel', eventId: 'cancel'),
        UIBuilder.button(label: 'Confirm', eventId: 'confirm'),
      ]),
    );

    expect(find.text('Confirm'), findsOneWidget);
    final actions = tester.getRect(find.text('Confirm'));
    final screen = tester.getRect(find.byType(MaterialApp));

    // Inside the viewport, not pushed below it by forty lines of content.
    expect(actions.bottom, lessThanOrEqualTo(screen.bottom));
    expect(actions.top, greaterThanOrEqualTo(screen.top));
  });

  testWidgets('and they do not move when the body is scrolled', (tester) async {
    await show(
      tester,
      longDialog(actions: [
        UIBuilder.button(label: 'Confirm', eventId: 'confirm'),
      ]),
    );
    final before = tester.getRect(find.text('Confirm'));

    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('Confirm')),
      before,
      reason: 'pinned, not carried along by the scroll',
    );
  });

  testWidgets('a dialog with no actions scrolls all of itself', (tester) async {
    await show(tester, longDialog());

    // Nothing to pin, so nothing changes for the dialogs that had no actions.
    expect(find.text('Line 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
