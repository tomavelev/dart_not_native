/// Tests for Flutter slots: the registry, the node the Flutter renderer
/// builds, and the layer that paints the widgets under the native views.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/flutter_slot.dart';
import 'package:dart_not_native/platforms/android_renderer.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A widget with State, to see whether the State survives.
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => taps++),
    child: Text('taps: $taps', textDirection: TextDirection.ltr),
  );
}

void main() {
  setUp(FlutterSlots.instance.clear);
  tearDown(FlutterSlots.instance.clear);

  group('FlutterSlots', () {
    late FlutterSlots slots;
    late int changes;

    setUp(() {
      slots = FlutterSlots();
      changes = 0;
      slots.addListener(() => changes++);
    });

    Object builder() => () {};

    test('holds a builder per slot and says when one changes', () {
      final first = builder();
      slots.register('ad', first);
      expect(slots.builderOf('ad'), same(first));
      expect(slots.isRegistered('ad'), isTrue);
      expect(slots.slotIds, ['ad']);
      expect(changes, 1);

      // The same builder again is no change; a new one is.
      slots.register('ad', first);
      expect(changes, 1);
      slots.register('ad', builder());
      expect(changes, 2);
    });

    test('keeps the latest rectangle and says when it moves', () {
      const rect = FlutterSlotRect(x: 1, y: 2, width: 3, height: 4);
      expect(slots.rectOf('ad'), isNull);

      slots.setRect('ad', rect);
      slots.setRect(
        'ad',
        const FlutterSlotRect(x: 1, y: 2, width: 3, height: 4),
      );
      expect(slots.rectOf('ad'), rect);
      expect(changes, 1);

      slots.setRect(
        'ad',
        const FlutterSlotRect(x: 1, y: 9, width: 3, height: 4, visible: false),
      );
      expect(slots.rectOf('ad')!.y, 9);
      expect(slots.rectOf('ad')!.visible, isFalse);
      expect(changes, 2);
    });

    test('reads the payload of a slotRect event', () {
      expect(
        slots.reportRect({
          'slotId': 'ad',
          'x': 10,
          'y': 20.5,
          'width': 320,
          'height': 50,
          'visible': false,
        }),
        isTrue,
      );
      expect(
        slots.rectOf('ad'),
        const FlutterSlotRect(
          x: 10,
          y: 20.5,
          width: 320,
          height: 50,
          visible: false,
        ),
      );

      // Half a rectangle is no rectangle.
      expect(slots.reportRect({'slotId': 'ad', 'x': 1, 'y': 2}), isFalse);
      expect(
        slots.reportRect({'x': 1, 'y': 2, 'width': 3, 'height': 4}),
        isFalse,
      );
      expect(slots.rectOf('ad')!.x, 10);
    });

    test('a slot the latest tree no longer holds is dropped', () {
      final renderer = Object();
      WidgetNode tree(List<String> ids) => UIBuilder.column(
        children: [
          for (final id in ids) UIBuilder.flutterSlot(slotId: id, height: 50),
        ],
      );
      slots
        ..register('ad', builder())
        ..register('chart', builder())
        ..setRect('ad', const FlutterSlotRect(x: 0, y: 0, width: 1, height: 1));

      slots.sync(renderer, tree(['ad', 'chart']));
      expect(slots.slotIds, ['ad', 'chart']);

      slots.sync(renderer, tree(['chart']));
      expect(slots.slotIds, ['chart']);
      expect(slots.rectOf('ad'), isNull);

      slots.sync(renderer, tree([]));
      expect(slots.slotIds, isEmpty);
    });

    test('a slot registered for a render still on its way is kept', () {
      final renderer = Object();
      slots.register('ad', builder());

      slots.sync(renderer, UIBuilder.text('no slots yet'));

      expect(slots.isRegistered('ad'), isTrue);
    });

    test('one renderer does not drop the slots of another', () {
      final first = Object();
      final second = Object();
      slots
        ..register('a', builder())
        ..register('b', builder());
      slots.sync(first, UIBuilder.flutterSlot(slotId: 'a', height: 1));
      slots.sync(second, UIBuilder.flutterSlot(slotId: 'b', height: 1));

      slots.sync(second, UIBuilder.text('empty'));
      expect(slots.slotIds, ['a']);

      slots.release(first);
      expect(slots.slotIds, isEmpty);
    });

    test('unregister drops the builder and the rectangle', () {
      slots
        ..register('ad', builder())
        ..setRect('ad', const FlutterSlotRect(x: 0, y: 0, width: 1, height: 1));
      changes = 0;

      slots.unregister('ad');
      slots.unregister('ad');

      expect(slots.isRegistered('ad'), isFalse);
      expect(slots.rectOf('ad'), isNull);
      expect(changes, 1);
    });

    test('finds the slot ids anywhere in a tree', () {
      final tree = UIBuilder.scaffold(
        body: UIBuilder.column(
          children: [
            UIBuilder.flutterSlot(slotId: 'top', height: 50),
            UIBuilder.box(
              child: UIBuilder.flutterSlot(slotId: 'deep', height: 50),
            ),
          ],
        ),
      );

      expect(FlutterSlots.slotIdsIn(tree), {'top', 'deep'});
    });
  });

  group('flutterSlotNode', () {
    test('registers the builder and returns the node', () {
      Widget build(BuildContext context) => const SizedBox();
      final fallback = UIBuilder.text('No ads here');

      final node = flutterSlotNode(
        slotId: 'ad',
        height: 50,
        width: 320,
        builder: build,
        fallback: fallback,
      );

      expect(FlutterSlots.instance.builderOf('ad'), same(build));
      expect(node.type, 'FlutterSlot');
      expect(node.props, {
        'slotId': 'ad',
        'height': 50.0,
        'width': 320.0,
        'id': 'slot_ad',
      });
      expect(node.children, [fallback]);
    });
  });

  group('the Flutter renderer', () {
    late FlutterUIRenderer renderer;

    setUp(() => renderer = FlutterUIRenderer());
    tearDown(() => renderer.dispose());

    Future<void> show(WidgetTester tester, WidgetNode node) async {
      await renderer.render(node);
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: renderer.build)),
      );
    }

    testWidgets('builds the registered widget where the node is, at its size', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: flutterSlotNode(
            slotId: 'ad',
            height: 50,
            width: 320,
            builder: (_) => const Placeholder(),
            fallback: UIBuilder.text('fallback'),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Placeholder)), const Size(320, 50));
      expect(find.text('fallback'), findsNothing);
    });

    testWidgets('fills the width it is offered when it states none', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: flutterSlotNode(
            slotId: 'ad',
            height: 50,
            builder: (_) => const Placeholder(),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Placeholder)), const Size(800, 50));
    });

    testWidgets('draws the fallback when nothing is registered', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.flutterSlot(
          slotId: 'nobody',
          height: 50,
          fallback: UIBuilder.text('fallback'),
        ),
      );

      expect(find.text('fallback'), findsOneWidget);
    });

    testWidgets('the widget keeps its State across renders, and its builder '
        'goes when the node does', (tester) async {
      WidgetNode tree(String label) => UIBuilder.column(
        children: [
          UIBuilder.text(label),
          flutterSlotNode(
            slotId: 'counter',
            height: 50,
            builder: (_) => const _Counter(),
          ),
        ],
      );
      await show(tester, tree('one'));
      await tester.tap(find.text('taps: 0'));
      await tester.pump();

      await show(tester, tree('two'));
      expect(find.text('taps: 1'), findsOneWidget);

      await show(tester, UIBuilder.text('no slot'));
      expect(FlutterSlots.instance.isRegistered('counter'), isFalse);
    });
  });

  group('FlutterSlotLayer', () {
    late FlutterSlots slots;
    late int tapsBehind;

    setUp(() {
      slots = FlutterSlots();
      tapsBehind = 0;
    });

    /// The layer over something tappable, the way it sits over the host's
    /// background.
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapsBehind++,
            ),
            FlutterSlotLayer(slots: slots),
          ],
        ),
      ),
    );

    testWidgets('paints each slot at the rectangle reported for it', (
      tester,
    ) async {
      slots
        ..register('a', (BuildContext _) => const Placeholder())
        ..register('b', (BuildContext _) => const _Counter());
      await pump(tester);
      // Nowhere to put either yet.
      expect(find.byType(Placeholder), findsNothing);
      expect(find.byType(_Counter), findsNothing);

      slots.reportRect({
        'slotId': 'a',
        'x': 10,
        'y': 20,
        'width': 300,
        'height': 50,
      });
      await tester.pump();

      expect(
        tester.getRect(find.byType(Placeholder)),
        const Rect.fromLTWH(10, 20, 300, 50),
      );
      expect(find.byType(_Counter), findsNothing);
      expect(
        find.ancestor(
          of: find.byType(Placeholder),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('a slot keeps its State while its rectangle moves and other '
        'slots come and go', (tester) async {
      slots
        ..register('counter', (BuildContext _) => const _Counter())
        ..setRect(
          'counter',
          const FlutterSlotRect(x: 0, y: 0, width: 200, height: 50),
        );
      await pump(tester);
      await tester.tap(find.text('taps: 0'));
      await tester.pump();

      slots
        ..register('first', (BuildContext _) => const Placeholder())
        ..setRect(
          'first',
          const FlutterSlotRect(x: 0, y: 300, width: 10, height: 10),
        )
        ..setRect(
          'counter',
          const FlutterSlotRect(x: 40, y: 100, width: 200, height: 50),
        )
        // A new closure, as every build of the app's tree registers.
        ..register('counter', (BuildContext _) => const _Counter());
      await tester.pump();

      expect(find.text('taps: 1'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(_Counter)), const Offset(40, 100));
    });

    testWidgets('hidden is neither painted nor hit, and keeps its State', (
      tester,
    ) async {
      slots
        ..register('counter', (BuildContext _) => const _Counter())
        ..setRect(
          'counter',
          const FlutterSlotRect(x: 0, y: 0, width: 200, height: 50),
        );
      await pump(tester);
      await tester.tap(find.text('taps: 0'));
      await tester.pump();

      slots.setRect(
        'counter',
        const FlutterSlotRect(
          x: 0,
          y: 0,
          width: 200,
          height: 50,
          visible: false,
        ),
      );
      await tester.pump();
      expect(find.text('taps: 1'), findsNothing);
      await tester.tapAt(const Offset(20, 20));
      expect(tapsBehind, 1);

      slots.setRect(
        'counter',
        const FlutterSlotRect(x: 0, y: 0, width: 200, height: 50),
      );
      await tester.pump();
      expect(find.text('taps: 1'), findsOneWidget);
    });

    testWidgets('takes touches inside a slot and lets the rest through', (
      tester,
    ) async {
      slots
        ..register('counter', (BuildContext _) => const _Counter())
        ..setRect(
          'counter',
          const FlutterSlotRect(x: 100, y: 100, width: 200, height: 50),
        );
      await pump(tester);

      await tester.tapAt(const Offset(150, 120));
      await tester.pump();
      expect(find.text('taps: 1'), findsOneWidget);
      expect(tapsBehind, 0);

      await tester.tapAt(const Offset(500, 400));
      expect(tapsBehind, 1);
    });

    testWidgets('a slot that leaves the registry leaves the layer', (
      tester,
    ) async {
      slots
        ..register('a', (BuildContext _) => const Placeholder())
        ..setRect(
          'a',
          const FlutterSlotRect(x: 0, y: 0, width: 10, height: 10),
        );
      await pump(tester);
      expect(find.byType(Placeholder), findsOneWidget);

      slots.unregister('a');
      await tester.pump();
      expect(find.byType(Placeholder), findsNothing);
    });

    testWidgets('a builder registered in the middle of a frame repaints after '
        'it', (tester) async {
      slots.setRect(
        'late',
        const FlutterSlotRect(x: 0, y: 0, width: 10, height: 10),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              FlutterSlotLayer(slots: slots),
              // Registers while the frame is building, the way an app's first
              // build does.
              Builder(
                builder: (_) {
                  slots.register(
                    'late',
                    (BuildContext _) => const Placeholder(),
                  );
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.pump();
      expect(find.byType(Placeholder), findsOneWidget);
    });
  });

  group('the native renderers', () {
    const channel = MethodChannel('com.programtom.dart_not_native/renderer');

    /// Delivers what the native half would send for [eventId].
    Future<Object?> fromNative(
      WidgetTester tester,
      String eventId,
      Map<String, Object?> data,
    ) async {
      Object? answer;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('event', {'eventId': eventId, 'data': data}),
        ),
        (reply) => answer = channel.codec.decodeEnvelope(reply!),
      );
      return answer;
    }

    testWidgets('a slotRect event reaches the registry, not the app', (
      tester,
    ) async {
      AndroidNativeRenderer();

      final answer = await fromNative(tester, RendererEvents.slotRect, {
        'slotId': 'ad',
        'x': 0,
        'y': 540,
        'width': 360,
        'height': 50,
        'visible': true,
      });

      expect(answer, {'success': true});
      expect(
        FlutterSlots.instance.rectOf('ad'),
        const FlutterSlotRect(x: 0, y: 540, width: 360, height: 50),
      );
    });

    testWidgets('the renderer\'s own events reach a handler, and are not an '
        'error without one', (tester) async {
      final renderer = AndroidNativeRenderer();
      final heard = <Map<String, dynamic>>[];

      final unheard = await fromNative(tester, RendererEvents.viewport, {
        'width': 360,
      });
      expect(unheard, {'success': true, 'handled': false});

      renderer.onEvent(RendererEvents.viewport, heard.add);
      final answer = await fromNative(tester, RendererEvents.viewport, {
        'width': 360,
      });
      expect(answer, {'success': true});
      expect(heard.single, {'width': 360});

      // An ordinary event nobody handles is still reported as one.
      final missing = await fromNative(tester, 'tap_7', {});
      expect((missing! as Map)['success'], isFalse);
    });

    testWidgets('a render drops the slots its tree no longer holds', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final renderer = AndroidNativeRenderer(batched: false);

      await renderer.render(
        flutterSlotNode(
          slotId: 'ad',
          height: 50,
          builder: (_) => const SizedBox(),
        ),
      );
      expect(FlutterSlots.instance.isRegistered('ad'), isTrue);

      await renderer.render(UIBuilder.text('no slot'));
      expect(FlutterSlots.instance.isRegistered('ad'), isFalse);
    });
  });
}
