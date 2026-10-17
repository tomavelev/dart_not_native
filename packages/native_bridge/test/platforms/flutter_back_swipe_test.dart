/// Widget tests for a swipe back in the Flutter renderer on iOS: the page
/// follows the finger over the page beneath, and is taken off or put back.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;
  final phases = <String>[];

  setUp(() {
    renderer = FlutterUIRenderer();
    phases.clear();
  });
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  WidgetNode page(String name, {bool swiping = false}) {
    final root = UIBuilder.scaffold(body: UIBuilder.text(name));
    return WidgetNode(
      type: root.type,
      props: {
        ...root.props,
        RootProps.backSwipeEventId: 'back',
        if (swiping) RootProps.beneath: UIBuilder.text('beneath').toJson(),
      },
      children: root.children,
    );
  }

  Future<void> mount(WidgetTester tester) async {
    renderer.onEvent('back', (data) {
      final phase = '${data['phase']}';
      phases.add(phase);
      return renderer.render(switch (phase) {
        'start' => page('top', swiping: true),
        'commit' => UIBuilder.scaffold(body: UIBuilder.text('beneath')),
        _ => page('top'),
      });
    });
    await renderer.render(page('top'));
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
  }

  testWidgets('the page follows the finger over the one beneath', (
    tester,
  ) async {
    await mount(tester);
    final finger = await tester.startGesture(const Offset(5, 300));
    await finger.moveBy(const Offset(40, 0));
    await tester.pump();
    await finger.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(phases, ['start']);
    expect(find.text('beneath'), findsOneWidget);
    expect(tester.getTopLeft(find.text('top')).dx, greaterThan(60));
    await finger.up();
    await tester.pumpAndSettle();
    expect(phases, ['start', 'cancel']);
    expect(find.text('beneath'), findsNothing);
  }, variant: ios);

  testWidgets('past half way it is taken off', (tester) async {
    await mount(tester);
    final width = tester.getSize(find.byType(MaterialApp)).width;
    final finger = await tester.startGesture(const Offset(5, 300));
    await finger.moveBy(const Offset(40, 0));
    await tester.pump();
    await finger.moveBy(Offset(width * 0.6, 0));
    await tester.pump();
    await finger.up();
    await tester.pumpAndSettle();
    expect(phases, ['start', 'commit']);
    expect(find.text('top'), findsNothing);
    expect(tester.getTopLeft(find.text('beneath')).dx, lessThan(60));
  }, variant: ios);

  testWidgets('is not offered off iOS', (tester) async {
    await mount(tester);
    await tester.dragFrom(const Offset(5, 300), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(phases, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
