/// Widget tests for a drawer in the Flutter renderer: a sheet with a side is
/// a panel the height of the screen at that edge, a swipe towards the edge
/// closes it, and a drag in from a scaffold's edge asks for it to open.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;
  final reasons = <Object?>[];

  setUp(() {
    renderer = FlutterUIRenderer();
    reasons.clear();
    renderer.onEvent('closed', (data) => reasons.add(data['reason']));
  });

  Future<void> show(WidgetTester tester, {required String side}) async {
    await renderer.render(
      UIBuilder.overlay(
        child: UIBuilder.text('page'),
        overlays: [
          UIBuilder.bottomSheet(
            content: [UIBuilder.text('Menu')],
            side: side,
            width: 250,
            dismissEventId: 'closed',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a start drawer stands against the left edge, the height of '
      'the screen', (tester) async {
    await show(tester, side: 'start');
    final screen = tester.getSize(find.byType(MaterialApp));
    final panel = tester.getRect(
      find
          .ancestor(of: find.text('Menu'), matching: find.byType(Material))
          .first,
    );
    expect(panel.left, 0);
    expect(panel.width, 250);
    expect(panel.height, screen.height);
  });

  testWidgets('an end drawer stands against the right', (tester) async {
    await show(tester, side: 'end');
    final screen = tester.getSize(find.byType(MaterialApp));
    final panel = tester.getRect(
      find
          .ancestor(of: find.text('Menu'), matching: find.byType(Material))
          .first,
    );
    expect(panel.right, screen.width);
  });

  testWidgets('a swipe towards its edge closes it', (tester) async {
    await show(tester, side: 'start');
    await tester.drag(find.text('Menu'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(reasons, ['swipe']);
  });

  group('a drag in from the edge', () {
    final opened = <String>[];

    Future<void> scaffold(WidgetTester tester, {bool rtl = false}) async {
      opened.clear();
      renderer
        ..onEvent('start', (_) => opened.add('start'))
        ..onEvent('end', (_) => opened.add('end'))
        ..onEvent('tapped', (_) => opened.add('tapped'));
      await renderer.render(
        UIBuilder.withTextDirection(
          UIBuilder.scaffold(
            body: UIBuilder.column(
              crossAxisAlignment: 'stretch',
              children: [UIBuilder.button(label: 'tap me', eventId: 'tapped')],
            ),
            drawerEdgeEventId: 'start',
            endDrawerEdgeEventId: 'end',
          ),
          rtl ? 'rtl' : 'ltr',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: renderer.build)),
      );
    }

    testWidgets('asks for the drawer at that edge', (tester) async {
      await scaffold(tester);
      final width = tester.getSize(find.byType(MaterialApp)).width;
      await tester.dragFrom(const Offset(5, 300), const Offset(120, 0));
      await tester.dragFrom(Offset(width - 5, 300), const Offset(-120, 0));
      await tester.dragFrom(const Offset(100, 300), const Offset(120, 0));
      expect(opened, ['start', 'end']);
    });

    testWidgets('the start is on the right in a screen read from it', (
      tester,
    ) async {
      await scaffold(tester, rtl: true);
      final width = tester.getSize(find.byType(MaterialApp)).width;
      await tester.dragFrom(Offset(width - 5, 300), const Offset(-120, 0));
      expect(opened, ['start']);
    });

    testWidgets('a tap by the edge still reaches what is there', (
      tester,
    ) async {
      await scaffold(tester);
      final button = tester.getRect(find.text('tap me'));
      await tester.tapAt(Offset(5, button.center.dy));
      expect(opened, ['tapped']);
    });
  });

  group('a drawer swiped open', () {
    final closed = <Object?>[];

    // A plain scaffold until the drawer comes, as an app's tree is.
    WidgetNode frame({bool open = false}) {
      final scaffold = UIBuilder.scaffold(
        body: UIBuilder.text('page'),
        drawerEdgeEventId: 'open',
      );
      if (!open) return scaffold;
      return UIBuilder.overlay(
        child: scaffold,
        overlays: [
          UIBuilder.bottomSheet(
            content: [UIBuilder.text('Menu')],
            side: 'start',
            width: 200,
            dismissEventId: 'shut',
          ),
        ],
      );
    }

    Future<TestGesture> pullTo(WidgetTester tester, double x) async {
      closed.clear();
      renderer
        ..onEvent('open', (_) => renderer.render(frame(open: true)))
        ..onEvent('shut', (data) => closed.add(data['reason']));
      await renderer.render(frame());
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              renderer.onTreeChanged = () => setState(() {});
              return renderer.build(context);
            },
          ),
        ),
      );
      final finger = await tester.startGesture(const Offset(5, 300));
      await finger.moveBy(const Offset(30, 0));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.moveTo(Offset(x, 300));
      await tester.pump();
      return finger;
    }

    double out(WidgetTester tester) => tester
        .getRect(
          find
              .ancestor(of: find.text('Menu'), matching: find.byType(Material))
              .first,
        )
        .right;

    testWidgets('follows the finger, and shuts let go short of half way', (
      tester,
    ) async {
      final finger = await pullTo(tester, 70);
      // Out as far as the finger has come since the drawer was asked for.
      expect(out(tester), closeTo(65, 20));
      await tester.pump(const Duration(milliseconds: 100));
      await finger.up();
      await tester.pumpAndSettle();
      expect(closed, ['swipe']);
    });

    testWidgets('stays open let go past half way', (tester) async {
      final finger = await pullTo(tester, 170);
      await tester.pump(const Duration(milliseconds: 100));
      await finger.up();
      await tester.pumpAndSettle();
      expect(closed, isEmpty);
      expect(out(tester), closeTo(200, 1));
    });
  });
}
