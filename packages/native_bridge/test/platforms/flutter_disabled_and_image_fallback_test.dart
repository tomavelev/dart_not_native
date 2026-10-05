/// Two props the Flutter renderer has to answer for: `disabled` on the three
/// checkable controls, and the fallback child of an `Image`.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;
  late List<String> events;

  setUp(() {
    renderer = FlutterUIRenderer();
    events = [];
    renderer.onEvent('e', (_) => events.add('e'));
  });
  tearDown(() => renderer.dispose());

  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
  }

  WidgetNode node(String type, Map<String, dynamic> props) =>
      WidgetNode(type: type, props: {'eventId': 'e', ...props});

  group('disabled', () {
    testWidgets('a checkbox takes no tap and is Flutter\'s disabled one', (
      tester,
    ) async {
      await show(
        tester,
        node('Checkbox', {'checked': true, 'disabled': true, 'label': 'Agree'}),
      );

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
      await tester.tap(find.byType(Checkbox));
      expect(events, isEmpty);
      // The label goes grey with it.
      final label = tester.widget<Text>(find.text('Agree'));
      expect(label.style?.color, isNotNull);
    });

    testWidgets('a switch takes no tap', (tester) async {
      await show(tester, node('Toggle', {'enabled': false, 'disabled': true}));

      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await tester.tap(find.byType(Switch));
      expect(events, isEmpty);
    });

    testWidgets('a radio takes no tap', (tester) async {
      await show(
        tester,
        node('Radio', {'value': 'a', 'selected': false, 'disabled': true}),
      );

      expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
      await tester.tap(find.byType(InkWell));
      expect(events, isEmpty);
    });

    testWidgets('and each is the same control again once it is enabled', (
      tester,
    ) async {
      await show(tester, node('Checkbox', {'checked': false, 'disabled': true}));
      final before = tester.element(find.byType(Checkbox));

      await show(tester, node('Checkbox', {'checked': false}));

      expect(tester.element(find.byType(Checkbox)), same(before));
      await tester.tap(find.byType(Checkbox));
      expect(events, ['e']);
    });
  });

  group('an image\'s fallback child', () {
    // Centred, so the image is offered room rather than told to fill the
    // screen.
    WidgetNode image({WidgetNode? fallback}) => UIBuilder.center(
      child: UIBuilder.image(
        // Not an asset this test bundles, so it fails to load - which a
        // widget test can rely on where it cannot rely on the network.
        src: 'assets/not_there.png',
        alt: 'Avatar of Sam',
        width: 48,
        height: 48,
        fallback: fallback,
      ),
    );

    testWidgets('is drawn instead of the alt text when loading fails', (
      tester,
    ) async {
      await show(tester, image(fallback: UIBuilder.text('SK')));
      await tester.pumpAndSettle();

      expect(find.text('SK'), findsOneWidget);
      expect(find.text('Avatar of Sam'), findsNothing);
      // In the room the image stated for itself.
      final room = find.ancestor(
        of: find.text('SK'),
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.width == 48,
        ),
      );
      expect(tester.getSize(room), const Size(48, 48));
    });

    testWidgets('is what shows while the image is still loading', (
      tester,
    ) async {
      await show(tester, image(fallback: UIBuilder.text('SK')));
      // One frame in: nothing has loaded or failed yet.
      expect(find.text('SK'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('an image without one shows its alt text, as before', (
      tester,
    ) async {
      await show(tester, image());
      await tester.pumpAndSettle();

      expect(find.text('Avatar of Sam'), findsOneWidget);
    });

    testWidgets('the alt text is still what a screen reader is told', (
      tester,
    ) async {
      await show(tester, image(fallback: UIBuilder.text('SK')));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Avatar of Sam'), findsWidgets);
    });
  });
}
