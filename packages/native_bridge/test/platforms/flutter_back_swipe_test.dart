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

  /// A hero that flies with a swipe, [size] square, [down] from the top.
  WidgetNode hero(String label, {required double size, required double down}) {
    final box = UIBuilder.box(
      hero: 'picture',
      width: size,
      height: size,
      color: '#3366ff',
      child: UIBuilder.text(label),
    );
    return UIBuilder.column(
      children: [
        UIBuilder.sizedBox(height: down),
        WidgetNode(
          type: box.type,
          props: {...box.props, 'heroGestures': true},
          children: box.children,
        ),
      ],
    );
  }

  WidgetNode page(
    String name, {
    bool swiping = false,
    bool heroes = false,
  }) {
    final root = UIBuilder.scaffold(
      body: heroes ? hero(name, size: 40, down: 200) : UIBuilder.text(name),
    );
    final beneath = heroes
        ? hero('beneath', size: 100, down: 0)
        : UIBuilder.text('beneath');
    return WidgetNode(
      type: root.type,
      props: {
        ...root.props,
        RootProps.backSwipeEventId: 'back',
        if (swiping) RootProps.beneath: beneath.toJson(),
      },
      children: root.children,
    );
  }

  Future<void> mount(WidgetTester tester, {bool heroes = false}) async {
    renderer.onEvent('back', (data) {
      final phase = '${data['phase']}';
      phases.add(phase);
      return renderer.render(switch (phase) {
        'start' => page('top', swiping: true, heroes: heroes),
        'commit' => UIBuilder.scaffold(body: UIBuilder.text('beneath')),
        _ => page('top', heroes: heroes),
      });
    });
    await renderer.render(page('top', heroes: heroes));
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

  testWidgets('a page in a frame moves alone, the frame staying still', (
    tester,
  ) async {
    WidgetNode framed({bool swiping = false}) {
      final page = UIBuilder.text('inner');
      final root = UIBuilder.scaffold(
        body: UIBuilder.column(
          children: [
            UIBuilder.text('frame'),
            WidgetNode(
              type: page.type,
              props: {...page.props, RootProps.backSwipePage: true},
            ),
          ],
        ),
      );
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

    renderer.onEvent('back', (data) {
      phases.add('${data['phase']}');
      return renderer.render(framed(swiping: data['phase'] == 'start'));
    });
    await renderer.render(framed());
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
    final frameAt = tester.getTopLeft(find.text('frame'));
    final innerAt = tester.getTopLeft(find.text('inner'));
    final finger = await tester.startGesture(Offset(5, innerAt.dy));
    await finger.moveBy(const Offset(40, 0));
    await tester.pump();
    await finger.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(phases, ['start']);
    expect(tester.getTopLeft(find.text('frame')), frameAt);
    expect(tester.getTopLeft(find.text('inner')).dx, greaterThan(60));
    // The page beneath, in the inner page's place and a third behind.
    final beneathAt = tester.getTopLeft(find.text('beneath'));
    expect(beneathAt.dy, innerAt.dy);
    expect(beneathAt.dx, lessThan(innerAt.dx));
    await finger.up();
    await tester.pumpAndSettle();
    expect(phases, ['start', 'cancel']);
    expect(find.text('beneath'), findsNothing);
    expect(tester.getTopLeft(find.text('inner')), innerAt);
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

  testWidgets('a hero that flies with it goes as far as the page has', (
    tester,
  ) async {
    await mount(tester, heroes: true);
    final width = tester.getSize(find.byType(MaterialApp)).width;
    final flight = find.byKey(const ValueKey<String>('hero picture'));
    final from = tester.getRect(find.text('top'));
    final finger = await tester.startGesture(const Offset(5, 300));
    await finger.moveBy(const Offset(40, 0));
    await tester.pump();
    await tester.pump();
    await finger.moveBy(Offset(width / 2 - 40, 0));
    await tester.pump();

    // Half way from the page's 40 square to the 100 square beneath.
    expect(flight, findsOneWidget);
    final half = tester.getRect(flight);
    expect(half.width, closeTo(70, 1));
    expect(half.top, closeTo(from.top / 2, 2));

    await finger.up();
    await tester.pumpAndSettle();
    expect(phases, ['start', 'cancel']);
    expect(flight, findsNothing);
    expect(tester.getRect(find.text('top')), from);
  }, variant: ios);

  testWidgets('is not offered off iOS', (tester) async {
    await mount(tester);
    await tester.dragFrom(const Offset(5, 300), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(phases, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
