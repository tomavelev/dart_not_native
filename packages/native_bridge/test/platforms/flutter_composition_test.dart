/// Widget tests for the Flutter renderer's free-form nodes - boxes, layers,
/// scrollers, icons, canvases, pickers, bottom bars - and for the props the
/// older nodes gained with them.
///
/// Nodes that fire events are written out as [WidgetNode]s with the event ids
/// in their props, which is what a renderer is handed; the builders that
/// allocate those ids need an app around them, and nothing here is about that.
library;

import 'dart:ui' as ui;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// An app that listens to the renderer's own events and to nothing else.
class _ListeningApp extends NativeUIApp {
  _ListeningApp(this.listenTo);

  final List<String> listenTo;
  final List<(String, Map<String, dynamic>)> heard = [];

  @override
  void init() {
    for (final eventId in listenTo) {
      on(eventId, (data) => heard.add((eventId, data)));
    }
  }

  @override
  WidgetNode build() => UIBuilder.text('listening');
}

void main() {
  late FlutterUIRenderer renderer;
  late List<(String, Map<String, dynamic>)> events;

  setUp(() {
    renderer = FlutterUIRenderer();
    events = [];
  });
  tearDown(() => renderer.dispose());

  /// Records every event sent to [eventId].
  void listen(String eventId) =>
      renderer.onEvent(eventId, (data) => events.add((eventId, data)));

  /// Renders [node] on its own inside a Material app.
  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
  }

  /// Matches one recorded event. Spelled out because a record holding a map
  /// is only equal to itself.
  Matcher event(String eventId, Map<String, dynamic> data) =>
      isA<(String, Map<String, dynamic>)>()
          .having((e) => e.$1, 'event id', eventId)
          .having((e) => e.$2, 'data', data);

  WidgetNode box(Map<String, dynamic> props, [WidgetNode? child]) =>
      WidgetNode(type: 'Box', props: props, children: [?child]);

  group('colours', () {
    testWidgets('six digits are opaque and eight carry their alpha', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.text('opaque', color: '#336699'),
            UIBuilder.text('faint', color: '#80336699'),
          ],
        ),
      );

      expect(
        tester.widget<Text>(find.text('opaque')).style!.color,
        const Color(0xff336699),
      );
      expect(
        tester.widget<Text>(find.text('faint')).style!.color,
        const Color(0x80336699),
      );
    });
  });

  group('box', () {
    testWidgets('is the size it states and paints what it states', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.box(
            width: 120,
            height: 80,
            color: '#80ff0000',
            borderWidth: 2,
            borderColor: '#00ff00',
            borderRadius: 12,
            shadow: {'color': '#40000000', 'blur': 6, 'dx': 1, 'dy': 2},
            clip: true,
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      expect(tester.getSize(find.byType(Container)), const Size(120, 80));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0x80ff0000));
      expect(decoration.border!.top.color, const Color(0xff00ff00));
      expect(decoration.border!.top.width, 2);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      expect(decoration.boxShadow!.single.blurRadius, 6);
      expect(decoration.boxShadow!.single.offset, const Offset(1, 2));
      expect(container.clipBehavior, Clip.antiAlias);
    });

    testWidgets('hugs its child, inside its padding and margin', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.box(
            color: '#eeeeee',
            padding: [4, 6, 8, 10],
            margin: [1, 2, 3, 4],
            child: UIBuilder.box(width: 50, height: 20),
          ),
        ),
      );

      // 50 + 4 + 8 wide, 20 + 6 + 10 tall: the margin is outside the paint.
      expect(tester.getSize(find.byType(Container).first), const Size(62, 36));
      expect(
        tester.widget<Padding>(find.byType(Padding).first).padding,
        const EdgeInsets.fromLTRB(1, 2, 3, 4),
      );
    });

    testWidgets('min and max bound it, and expand fills the axis asked', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.box(
            expand: 'width',
            minHeight: 40,
            maxHeight: 60,
            color: '#eeeeee',
            child: UIBuilder.box(height: 10, width: 10),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Container).first), const Size(800, 40));
    });

    testWidgets('expand in a parent with no bound hugs instead of throwing', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.scroll(
          child: UIBuilder.box(
            expand: 'both',
            color: '#eeeeee',
            child: UIBuilder.box(height: 30, width: 10),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Container).first), const Size(800, 30));
    });

    testWidgets('an aspect ratio derives the free axis', (tester) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.box(width: 200, aspectRatio: 2, color: '#000000'),
        ),
      );

      expect(tester.getSize(find.byType(AspectRatio)), const Size(200, 100));
      expect(tester.getSize(find.byType(Container)), const Size(200, 100));
    });

    testWidgets('alignment places a child smaller than the box', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.box(
            width: 100,
            height: 100,
            alignment: [1, 1],
            child: UIBuilder.box(width: 10, height: 10, color: '#ff0000'),
          ),
        ),
      );

      final outer = tester.getRect(find.byType(Container).first);
      final inner = tester.getRect(find.byType(Container).last);
      expect(inner.size, const Size(10, 10));
      expect(inner.bottomRight, outer.bottomRight);
    });

    testWidgets('a circle, a gradient and corners of their own', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.box(
              width: 40,
              height: 40,
              shape: 'circle',
              gradient: {
                'type': 'linear',
                'colors': ['#ff0000', '#800000ff'],
                'stops': [0.0, 1.0],
                'begin': [-1, -1],
                'end': [1, 1],
              },
            ),
            UIBuilder.box(
              width: 40,
              height: 40,
              borderRadii: [1, 2, 3, 4],
              gradient: {
                'type': 'radial',
                'colors': ['#ffffff', '#000000'],
                'begin': [0, 0],
                'end': [1, 0],
              },
            ),
          ],
        ),
      );

      final boxes = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration! as BoxDecoration)
          .toList();
      expect(boxes[0].shape, BoxShape.circle);
      final linear = boxes[0].gradient! as LinearGradient;
      expect(linear.colors, const [Color(0xffff0000), Color(0x800000ff)]);
      expect(linear.begin, Alignment.topLeft);
      expect(linear.end, Alignment.bottomRight);
      expect(linear.stops, [0.0, 1.0]);
      expect(
        boxes[1].borderRadius,
        const BorderRadius.only(
          topLeft: Radius.circular(1),
          topRight: Radius.circular(2),
          bottomRight: Radius.circular(3),
          bottomLeft: Radius.circular(4),
        ),
      );
      final radial = boxes[1].gradient! as RadialGradient;
      expect(radial.center, Alignment.center);
      expect(radial.radius, 0.5);
    });

    testWidgets('opacity and transform wrap the box', (tester) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.box(
            width: 100,
            height: 100,
            opacity: 0.25,
            transform: {'rotate': 0.0, 'scale': 2.0, 'dx': 10.0, 'dy': 0.0},
          ),
        ),
      );

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.25);
      // Scaled about the centre and moved 10 to the right: 200 wide, and its
      // centre 10 right of the screen's.
      final rect = tester.getRect(find.byType(Container));
      expect(rect.size, const Size(200, 200));
      expect(rect.center, const Offset(410, 300));
    });

    testWidgets('animateMs moves there instead of landing at once', (
      tester,
    ) async {
      WidgetNode at(double size, double opacity, double scale) =>
          UIBuilder.center(
            child: UIBuilder.box(
              width: size,
              height: size,
              color: '#ff0000',
              opacity: opacity,
              transform: {'scale': scale},
              animateMs: 200,
              curve: 'linear',
            ),
          );
      await show(tester, at(100, 1, 1));
      expect(find.byType(AnimatedContainer), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsOneWidget);

      await renderer.render(at(200, 0, 3));
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: renderer.build)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Half way, on a linear curve: 150 across, drawn at twice the size.
      final container = find.byType(AnimatedContainer);
      expect(tester.getSize(container).width, 150);
      expect(tester.getRect(container).width, 300);
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(AnimatedOpacity),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        closeTo(0.5, 0.001),
      );

      await tester.pumpAndSettle();
      expect(tester.getRect(container).width, 600);
    });

    testWidgets('taps report the point in the box\'s own pixels', (
      tester,
    ) async {
      ['t', 'd', 'l'].forEach(listen);
      await show(
        tester,
        UIBuilder.center(
          child: box({
            'width': 100,
            'height': 100,
            'tapEventId': 't',
            'doubleTapEventId': 'd',
            'longPressEventId': 'l',
          }),
        ),
      );
      final origin = tester.getTopLeft(find.byType(GestureDetector));

      await tester.tapAt(origin + const Offset(10, 20));
      await tester.pump(kDoubleTapTimeout);
      expect(events.single.$1, 't');
      expect(events.single.$2, {'x': 10.0, 'y': 20.0});

      events.clear();
      await tester.tapAt(origin + const Offset(30, 40));
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(origin + const Offset(30, 40));
      await tester.pump(kDoubleTapTimeout);
      expect(events.single.$1, 'd');
      expect(events.single.$2, {'x': 30.0, 'y': 40.0});

      events.clear();
      await tester.longPressAt(origin + const Offset(50, 60));
      expect(events.single.$1, 'l');
      expect(events.single.$2, {'x': 50.0, 'y': 60.0});
    });

    testWidgets('a pan reports where, how far and how fast', (tester) async {
      ['p_start', 'p_update', 'p_end'].forEach(listen);
      await show(
        tester,
        UIBuilder.center(
          child: box({'width': 200, 'height': 200, 'panEventId': 'p'}),
        ),
      );
      final origin = tester.getTopLeft(find.byType(GestureDetector));

      final gesture = await tester.startGesture(origin + const Offset(20, 20));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(10, 5));
      await gesture.up();

      expect(events.first.$1, 'p_start');
      expect(events.first.$2.keys, ['x', 'y', 'dx', 'dy', 'vx', 'vy']);
      final updates = events.where((e) => e.$1 == 'p_update').toList();
      expect(updates, isNotEmpty);
      // The movements add up to the distance moved since the pan started,
      // and the last one is where the pointer is.
      expect(updates.last.$2['x'], 60.0);
      expect(updates.last.$2['y'], 25.0);
      expect(updates.last.$2['dx'], 10.0);
      expect(updates.last.$2['dy'], 5.0);
      expect(events.last.$1, 'p_end');
      expect(events.last.$2['x'], 60.0);
      expect(events.last.$2['vx'], isA<double>());
    });

    testWidgets('a ripple is an InkWell on a Material inside the paint', (
      tester,
    ) async {
      listen('t');
      await show(
        tester,
        UIBuilder.center(
          child: box({
            'width': 100,
            'height': 100,
            'color': '#2196f3',
            'borderRadius': 8,
            'ripple': true,
            'tapEventId': 't',
          }, UIBuilder.text('Tap')),
        ),
      );

      final inkWell = find.byType(InkWell);
      expect(inkWell, findsOneWidget);
      expect(
        find.ancestor(of: inkWell, matching: find.byType(Container)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Container),
          matching: find.byType(Material),
        ),
        findsOneWidget,
      );

      await tester.tapAt(
        tester.getTopLeft(find.byType(Container)) + const Offset(25, 75),
      );
      await tester.pumpAndSettle();
      expect(events.single.$2, {'x': 25.0, 'y': 75.0});
    });

    testWidgets('a dragged box drops its string on a box that takes drops', (
      tester,
    ) async {
      ['drop', 'drop_hover'].forEach(listen);
      await show(
        tester,
        UIBuilder.column(
          children: [
            box({
              'width': 60,
              'height': 60,
              'color': '#ff0000',
              'dragData': 'card-7',
            }),
            UIBuilder.sizedBox(height: 100),
            box({
              'width': 200,
              'height': 200,
              'color': '#00ff00',
              'dropEventId': 'drop',
            }),
          ],
        ),
      );

      // A finger picks a box up after a long press.
      expect(find.byType(LongPressDraggable<String>), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LongPressDraggable<String>)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(find.byType(DragTarget<String>)));
      await tester.pump();
      expect(events.single, event('drop_hover', {'over': true}));

      await gesture.up();
      await tester.pump();
      expect(events.map((e) => e.$1), ['drop_hover', 'drop_hover', 'drop']);
      expect(events[1].$2, {'over': false});
      expect(events.last.$2, {'data': 'card-7'});
    });

    testWidgets('a mouse picks a box up at once', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await show(tester, box({'width': 60, 'height': 60, 'dragData': 'x'}));
      debugDefaultTargetPlatformOverride = null;

      expect(find.byType(LongPressDraggable<String>), findsNothing);
      expect(find.byType(Draggable<String>), findsOneWidget);
    });

    testWidgets('its size is reported after layout, once per size', (
      tester,
    ) async {
      listen('s');
      WidgetNode sized(double width) => UIBuilder.center(
        child: box({'width': width, 'height': 50, 'sizeEventId': 's'}),
      );
      await show(tester, sized(120));
      await tester.pump();
      expect(events.single.$2, {'width': 120.0, 'height': 50.0});

      // The same tree again is the same size: nothing to say.
      await show(tester, sized(120));
      await tester.pump();
      expect(events, hasLength(1));

      await show(tester, sized(90));
      await tester.pump();
      expect(events.last.$2, {'width': 90.0, 'height': 50.0});
      expect(events, hasLength(2));
    });

    testWidgets('tooltip, semantic label and ignorePointer wrap it', (
      tester,
    ) async {
      listen('t');
      await show(
        tester,
        UIBuilder.center(
          child: box({
            'width': 50,
            'height': 50,
            'tooltip': 'More',
            'semanticLabel': 'A tile',
            'ignorePointer': true,
            'tapEventId': 't',
          }),
        ),
      );

      expect(find.byTooltip('More'), findsOneWidget);
      expect(find.bySemanticsLabel('A tile'), findsOneWidget);
      await tester.tap(find.byType(GestureDetector), warnIfMissed: false);
      await tester.pump(kDoubleTapTimeout);
      expect(events, isEmpty);
    });

    testWidgets('text and icons read over a fill the app chose', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.box(
          color: '#000000',
          child: UIBuilder.row(
            children: [
              UIBuilder.text('Label'),
              UIBuilder.icon(codepoint: 0xe145),
            ],
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.text('Label')).style!.color,
        const Color(0xffffffff),
      );
      expect(
        tester.widget<Icon>(find.byType(Icon)).color,
        const Color(0xffffffff),
      );
    });
  });

  group('stack', () {
    testWidgets('pins its positioned children and aligns the rest', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.stack(
            alignment: [1, 1],
            clip: false,
            children: [
              UIBuilder.box(width: 200, height: 100, color: '#eeeeee'),
              UIBuilder.box(width: 10, height: 10, color: '#ff0000'),
              UIBuilder.positioned(
                left: 5,
                top: 7,
                width: 20,
                height: 30,
                child: UIBuilder.text('pinned'),
              ),
              UIBuilder.positioned(fill: true, child: UIBuilder.text('fill')),
            ],
          ),
        ),
      );

      final stack = tester.widget<Stack>(find.byType(Stack).last);
      expect(stack.alignment, Alignment.bottomRight);
      expect(stack.clipBehavior, Clip.none);
      final origin = tester.getTopLeft(find.byType(Stack).last);
      expect(tester.getSize(find.byType(Stack).last), const Size(200, 100));
      expect(
        tester.getRect(find.text('pinned')),
        (origin + const Offset(5, 7)) & const Size(20, 30),
      );
      expect(tester.getSize(find.text('fill')), const Size(200, 100));
      expect(
        tester.getBottomRight(find.byType(Container).last),
        origin + const Offset(200, 100),
      );
    });

    testWidgets('fit expand makes the unpinned children fill it', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.box(
            width: 300,
            height: 200,
            child: UIBuilder.stack(
              fit: 'expand',
              children: [UIBuilder.box(color: '#ff0000')],
            ),
          ),
        ),
      );

      expect(
        tester.widget<Stack>(find.byType(Stack).last).fit,
        StackFit.expand,
      );
      expect(tester.getSize(find.byType(Container).last), const Size(300, 200));
    });

    testWidgets('a positioned outside a stack is its child', (tester) async {
      await show(
        tester,
        UIBuilder.positioned(left: 5, child: UIBuilder.text('loose')),
      );

      expect(find.text('loose'), findsOneWidget);
      expect(find.byType(Positioned), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('scroll', () {
    testWidgets('scrolls its child along the axis it names', (tester) async {
      await show(
        tester,
        UIBuilder.scroll(
          axis: 'horizontal',
          reverse: true,
          padding: [1, 2, 3, 4],
          child: UIBuilder.box(width: 2000, height: 50),
        ),
      );

      final view = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(view.scrollDirection, Axis.horizontal);
      expect(view.reverse, isTrue);
      expect(view.padding, const EdgeInsets.fromLTRB(1, 2, 3, 4));
    });

    testWidgets('shrinkWrap is as long as its child and does not scroll', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.scroll(
          child: UIBuilder.column(
            children: [
              UIBuilder.scroll(
                shrinkWrap: true,
                child: UIBuilder.box(width: 100, height: 900),
              ),
            ],
          ),
        ),
      );

      final inner = find.byType(SingleChildScrollView).last;
      expect(tester.getSize(inner).height, 900);
      expect(
        tester.widget<SingleChildScrollView>(inner).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
    });

    testWidgets('keeps its offset while the app re-renders around it', (
      tester,
    ) async {
      WidgetNode tree(String label) => UIBuilder.scroll(
        child: UIBuilder.column(
          children: [
            UIBuilder.text(label),
            UIBuilder.box(width: 100, height: 3000),
          ],
        ),
      );
      await show(tester, tree('one'));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pump();
      await show(tester, tree('two'));

      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        400,
      );
    });

    testWidgets('scrollOffset is applied once per scrollVersion', (
      tester,
    ) async {
      WidgetNode tree(double offset, int version) => UIBuilder.scroll(
        scrollOffset: offset,
        scrollVersion: version,
        child: UIBuilder.box(width: 100, height: 3000),
      );
      double pixels() => tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;

      // The first render starts there.
      await show(tester, tree(250, 1));
      expect(pixels(), 250);

      // The same version again does not drag the user back.
      await tester.drag(find.byType(Scrollable), const Offset(0, -100));
      await tester.pump();
      await show(tester, tree(250, 1));
      await tester.pump();
      expect(pixels(), 350);

      // A new version does, and an offset past the end stops at the end.
      await show(tester, tree(100, 2));
      await tester.pump();
      expect(pixels(), 100);
      await show(tester, tree(99999, 3));
      await tester.pump();
      expect(pixels(), 2400);
    });

    testWidgets('reports where it has been scrolled to, when it comes to '
        'rest and not once a frame', (tester) async {
      listen('at');
      await show(
        tester,
        WidgetNode(
          type: 'Scroll',
          props: {'scrollEventId': 'at'},
          children: [UIBuilder.box(width: 100, height: 3000)],
        ),
      );

      // Six frames of one drag, 16ms apart: within the 100ms a report is
      // held back for, so the moves send one and the stop sends the last.
      final gesture = await tester.startGesture(const Offset(400, 400));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(events.length, lessThan(6));
      final (id, last) = events.last;
      expect(id, 'at');
      expect(
        last['offset'],
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      );
      expect(last['offset'], greaterThan(0));
      expect(last['maxExtent'], 2400);
      expect(last['viewport'], 600);
    });

    testWidgets('a pull fires the refresh, and the spinner stays until the '
        'tree says it is over', (tester) async {
      listen('r');
      WidgetNode tree({required bool refreshing}) => WidgetNode(
        type: 'Scroll',
        props: {'refreshEventId': 'r', 'refreshing': refreshing},
        children: [UIBuilder.box(width: 100, height: 50)],
      );
      await show(tester, tree(refreshing: false));

      // Shorter than the screen, and still pullable.
      await tester.drag(find.byType(Scrollable), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(events.single.$1, 'r');
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      await show(tester, tree(refreshing: true));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      expect(events, hasLength(1));

      await show(tester, tree(refreshing: false));
      await tester.pumpAndSettle();
      expect(find.byType(RefreshProgressIndicator), findsNothing);
    });

    testWidgets(
      'a refresh the app started shows the spinner and fires nothing',
      (tester) async {
        listen('r');
        await show(
          tester,
          const WidgetNode(
            type: 'Scroll',
            props: {'refreshEventId': 'r', 'refreshing': true},
            children: [
              WidgetNode(type: 'SizedBox', props: {'height': 50}),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(RefreshProgressIndicator), findsOneWidget);
        expect(events, isEmpty);

        await show(
          tester,
          const WidgetNode(
            type: 'Scroll',
            props: {'refreshEventId': 'r', 'refreshing': false},
            children: [
              WidgetNode(type: 'SizedBox', props: {'height': 50}),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RefreshProgressIndicator), findsNothing);
      },
    );
  });

  group('icon', () {
    testWidgets('is the glyph at its codepoint, Material Icons by default', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.row(
          children: [
            UIBuilder.icon(
              codepoint: 0xe145,
              size: 32,
              color: '#80ff0000',
              semanticLabel: 'Add',
            ),
            UIBuilder.icon(codepoint: 0xf101, fontFamily: 'Brands'),
          ],
        ),
      );

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(icons[0].icon!.codePoint, 0xe145);
      expect(icons[0].icon!.fontFamily, 'MaterialIcons');
      expect(icons[0].size, 32);
      expect(icons[0].color, const Color(0x80ff0000));
      expect(icons[0].semanticLabel, 'Add');
      expect(icons[1].icon!.fontFamily, 'Brands');
      // No colour of its own: the surrounding IconTheme's.
      expect(icons[1].color, isNull);
    });
  });

  group('canvas', () {
    /// Paints [node] and returns the pixels of its surface.
    Future<ui.Image> paint(WidgetTester tester, WidgetNode node) async {
      await show(tester, UIBuilder.center(child: node));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(
              of: find.byType(CustomPaint).last,
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      late ui.Image image;
      await tester.runAsync(() async => image = await boundary.toImage());
      return image;
    }

    Future<Color> pixel(
      WidgetTester tester,
      ui.Image image,
      int x,
      int y,
    ) async {
      late ByteData data;
      await tester.runAsync(() async => data = (await image.toByteData())!);
      final i = (y * image.width + x) * 4;
      return Color.fromARGB(
        data.getUint8(i + 3),
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    }

    testWidgets('replays shapes, transforms, clips and paths', (tester) async {
      final image = await paint(
        tester,
        UIBuilder.canvas(
          width: 100,
          height: 100,
          paints: [
            {'color': '#ff0000'},
            {'color': '#0000ff', 'style': 'stroke', 'strokeWidth': 4},
            {'color': '#00ff00'},
          ],
          commands: [
            ['rect', 0, 0, 20, 20, 0],
            ['circle', 50, 50, 10, 2],
            ['line', 0, 90, 100, 90, 1],
            ['save'],
            ['translate', 60, 0],
            ['scale', 2, 2],
            ['rect', 0, 0, 10, 10, 2],
            ['restore'],
            // Back where it was: this lands at the origin's row, not at 60.
            ['rect', 30, 0, 5, 5, 0],
            ['save'],
            ['clipRect', 0, 30, 10, 10],
            ['rect', 0, 30, 40, 10, 0],
            ['restore'],
            [
              'path',
              [
                ['M', 80, 40],
                ['L', 100, 40],
                ['L', 100, 60],
                ['Z'],
              ],
              2,
            ],
            // More restores than saves change nothing.
            ['restore'],
            ['restore'],
            ['hologram', 1, 2, 3],
          ],
        ),
      );

      const red = Color(0xffff0000);
      const green = Color(0xff00ff00);
      const none = Color(0x00000000);
      expect(await pixel(tester, image, 10, 10), red);
      expect(await pixel(tester, image, 50, 50), green);
      expect(await pixel(tester, image, 50, 90), const Color(0xff0000ff));
      // Translated by 60 and doubled: 20 across from x = 60.
      expect(await pixel(tester, image, 75, 15), green);
      expect(await pixel(tester, image, 85, 15), none);
      expect(await pixel(tester, image, 32, 2), red);
      // Clipped to ten pixels of a forty pixel rectangle.
      expect(await pixel(tester, image, 5, 35), red);
      expect(await pixel(tester, image, 20, 35), none);
      expect(await pixel(tester, image, 95, 45), green);
      expect(tester.takeException(), isNull);
    });

    testWidgets('text is drawn from its top left, aligned about x or within '
        'maxWidth', (tester) async {
      final image = await paint(
        tester,
        UIBuilder.canvas(
          width: 100,
          height: 100,
          commands: [
            // The test font draws every glyph as a filled square of its size.
            [
              'text',
              'XX',
              50,
              0,
              {'size': 10, 'color': '#ff0000', 'align': 'center'},
            ],
            [
              'text',
              'X',
              100,
              20,
              {'size': 10, 'color': '#ff0000', 'align': 'right'},
            ],
            [
              'text',
              'X',
              0,
              40,
              {
                'size': 10,
                'color': '#ff0000',
                'align': 'right',
                'maxWidth': 50,
              },
            ],
            [
              'text',
              'X',
              10,
              60,
              {'size': 10, 'color': '#ff0000'},
            ],
          ],
        ),
      );

      bool inked(Color c) => c.a > 0;
      // Centred on x = 50: from 40 to 60.
      expect(inked(await pixel(tester, image, 42, 5)), isTrue);
      expect(inked(await pixel(tester, image, 58, 5)), isTrue);
      expect(inked(await pixel(tester, image, 35, 5)), isFalse);
      // Ending at x = 100.
      expect(inked(await pixel(tester, image, 95, 25)), isTrue);
      expect(inked(await pixel(tester, image, 85, 25)), isFalse);
      // Right-aligned in a box 50 wide starting at 0.
      expect(inked(await pixel(tester, image, 45, 45)), isTrue);
      expect(inked(await pixel(tester, image, 5, 45)), isFalse);
      // From its top left.
      expect(inked(await pixel(tester, image, 15, 65)), isTrue);
      expect(inked(await pixel(tester, image, 5, 65)), isFalse);
    });

    testWidgets('repaints when the commands change and not otherwise', (
      tester,
    ) async {
      final first = UIBuilder.canvas(
        width: 50,
        height: 50,
        commands: [
          ['rect', 0, 0, 10, 10, 0],
        ],
      );
      await show(tester, first);
      final before = tester.widget<CustomPaint>(find.byType(CustomPaint).last);

      // The same tree built again is the same picture.
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: renderer.build)),
      );
      final same = tester.widget<CustomPaint>(find.byType(CustomPaint).last);
      expect(same.painter!.shouldRepaint(before.painter!), isFalse);

      await show(
        tester,
        UIBuilder.canvas(
          width: 50,
          height: 50,
          commands: [
            ['rect', 0, 0, 20, 20, 0],
          ],
        ),
      );
      final after = tester.widget<CustomPaint>(find.byType(CustomPaint).last);
      expect(after.painter!.shouldRepaint(before.painter!), isTrue);
    });

    testWidgets(
      'carries a box\'s size and touch, and draws its child over it',
      (tester) async {
        ['t', 's'].forEach(listen);
        await show(
          tester,
          UIBuilder.center(
            child: WidgetNode(
              type: 'Canvas',
              props: const {
                'width': 80,
                'aspectRatio': 2,
                'tapEventId': 't',
                'sizeEventId': 's',
                'paints': [],
                'commands': [],
              },
              children: [UIBuilder.text('over')],
            ),
          ),
        );
        await tester.pump();

        expect(
          tester.getSize(find.byType(CustomPaint).last),
          const Size(80, 40),
        );
        expect(
          find.descendant(
            of: find.byType(CustomPaint).last,
            matching: find.text('over'),
          ),
          findsOneWidget,
        );
        expect(events.single, event('s', {'width': 80.0, 'height': 40.0}));
        await tester.tapAt(
          tester.getTopLeft(find.byType(CustomPaint).last) + const Offset(8, 9),
        );
        expect(events.last, event('t', {'x': 8.0, 'y': 9.0}));
      },
    );
  });

  group('dropdown', () {
    testWidgets('shows the selection and reports the index chosen', (
      tester,
    ) async {
      listen('d');
      await show(
        tester,
        UIBuilder.dropdown(
          items: ['Red', 'Green', 'Blue'],
          selectedIndex: 1,
          eventId: 'd',
          label: 'Colour',
          error: 'Pick another',
        ),
      );

      expect(find.text('Green'), findsOneWidget);
      expect(find.text('Colour'), findsOneWidget);
      expect(find.text('Pick another'), findsOneWidget);
      final decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      expect(decorator.decoration.border, isA<OutlineInputBorder>());

      await tester.tap(find.text('Green'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blue').last);
      await tester.pumpAndSettle();
      expect(events.single, event('d', {'index': 2}));
      // The selection is the tree's: until it says otherwise, it has not moved.
      expect(find.text('Green'), findsOneWidget);
    });

    testWidgets('no selection shows the hint, and disabled does not open', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.dropdown(
          items: ['Red', 'Green'],
          selectedIndex: null,
          hint: 'Choose',
          enabled: false,
          outlined: false,
        ),
      );

      expect(find.text('Choose'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<InputDecorator>(find.byType(InputDecorator))
            .decoration
            .border,
        isA<UnderlineInputBorder>(),
      );
    });

    testWidgets('an index outside the list is no selection', (tester) async {
      await show(
        tester,
        UIBuilder.dropdown(items: ['Red'], selectedIndex: 5, eventId: 'd'),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Red'), findsNothing);
    });
  });

  group('pickers', () {
    WidgetNode over(WidgetNode picker) =>
        UIBuilder.overlay(child: UIBuilder.text('Screen'), overlays: [picker]);

    const date = WidgetNode(
      type: 'DatePicker',
      props: {
        'initial': '2024-03-15',
        'first': '2024-01-01',
        'last': '2024-12-31',
        'eventId': 'picked',
        'dismissEventId': 'dismissed',
        'title': 'Departure',
        'confirmLabel': 'Choose',
        'cancelLabel': 'Never mind',
        'id': 'date',
      },
    );

    testWidgets('a date picker is Flutter\'s dialog, in the tree while open', (
      tester,
    ) async {
      ['picked', 'dismissed'].forEach(listen);
      await show(tester, over(date));
      await tester.pump();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(find.text('Departure'), findsOneWidget);
      expect(find.text('Screen'), findsOneWidget);

      await tester.tap(find.text('20'));
      await tester.pump();
      await tester.tap(find.text('Choose'));
      await tester.pump();
      expect(events.single, event('picked', {'value': '2024-03-20'}));
      // Choosing only says so. The picker goes when the app removes it.
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await show(tester, over(UIBuilder.text('gone')));
      await tester.pump();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.text('Screen'), findsOneWidget);
    });

    testWidgets('cancel and a tap on the scrim send the dismiss event', (
      tester,
    ) async {
      ['picked', 'dismissed'].forEach(listen);
      await show(tester, over(date));
      await tester.pump();

      await tester.tap(find.text('Never mind'));
      await tester.pump();
      expect(events.single.$1, 'dismissed');

      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(events.map((e) => e.$1), ['dismissed', 'dismissed']);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('a date outside its range still gets a picker', (tester) async {
      await show(
        tester,
        over(
          const WidgetNode(
            type: 'DatePicker',
            props: {
              'initial': '2030-01-01',
              'first': '2024-12-31',
              'last': '2024-01-01',
              'eventId': 'picked',
              'id': 'date',
            },
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('a time picker reports the hour and minute', (tester) async {
      ['picked', 'dismissed'].forEach(listen);
      await show(
        tester,
        over(
          const WidgetNode(
            type: 'TimePicker',
            props: {
              'hour': 14,
              'minute': 5,
              'eventId': 'picked',
              'dismissEventId': 'dismissed',
              'use24Hour': true,
              'confirmLabel': 'Set',
              'id': 'time',
            },
          ),
        ),
      );
      await tester.pump();

      final dialog = tester.widget<TimePickerDialog>(
        find.byType(TimePickerDialog),
      );
      expect(dialog.initialTime, const TimeOfDay(hour: 14, minute: 5));
      expect(
        MediaQuery.of(
          tester.element(find.byType(TimePickerDialog)),
        ).alwaysUse24HourFormat,
        isTrue,
      );

      await tester.tap(find.text('Set'));
      await tester.pump();
      expect(events.single, event('picked', {'hour': 14, 'minute': 5}));
    });
  });

  group('scaffold', () {
    testWidgets('finds the bottom bar by type and pins it', (tester) async {
      listen('nav');
      await show(
        tester,
        UIBuilder.scaffold(
          backgroundColor: '#80112233',
          body: UIBuilder.text('Body'),
          bottomBar: UIBuilder.bottomBar(
            child: UIBuilder.bottomNavigation(
              eventId: 'nav',
              selectedIndex: 1,
              items: [
                (label: 'Home', icon: 0xe318, selectedIcon: 0xe319),
                (label: 'Search', icon: 0xe567, selectedIcon: null),
              ],
            ),
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0x80112233));
      // In the wrapper that measures it for a snackbar to sit above.
      expect(
        find.descendant(
          of: find.byWidget(scaffold.bottomNavigationBar!),
          matching: find.byType(NavigationBar),
        ),
        findsOneWidget,
      );
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);
      expect(tester.getBottomLeft(find.byType(NavigationBar)).dy, 600);

      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(events.single, event('nav', {'index': 0}));
    });

    testWidgets('a bottom bar holding anything else sits above the inset', (
      tester,
    ) async {
      await renderer.render(
        UIBuilder.scaffold(
          body: UIBuilder.text('Body'),
          bottomBar: UIBuilder.bottomBar(
            child: UIBuilder.box(height: 40, child: UIBuilder.text('Bar')),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              padding: EdgeInsets.only(bottom: 20),
            ),
            child: Builder(builder: renderer.build),
          ),
        ),
      );

      expect(tester.getBottomLeft(find.text('Bar')).dy, lessThanOrEqualTo(580));
    });

    testWidgets('a body that does not scroll gets exactly the height left', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.scaffold(
          appBar: UIBuilder.appBar(title: 'Fixed'),
          bodyScrolls: false,
          body: UIBuilder.column(
            children: [
              UIBuilder.text('Top'),
              UIBuilder.expanded(
                child: UIBuilder.scroll(
                  child: UIBuilder.box(width: 100, height: 3000),
                ),
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // One scroller - the tree's own - and it ends where the screen does.
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.getBottomLeft(find.byType(SingleChildScrollView)).dy, 600);
    });

    testWidgets('a body that scrolls is still wrapped in a scroll view', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: UIBuilder.text('Body')));

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets(
      'safeArea keeps the body out of the insets unless told not to',
      (tester) async {
        Future<double> bodyTop({required bool safeArea}) async {
          await renderer.render(
            UIBuilder.scaffold(
              safeArea: safeArea,
              bodyScrolls: false,
              body: UIBuilder.text('Body'),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(800, 600),
                  padding: EdgeInsets.only(top: 30),
                ),
                child: Builder(builder: renderer.build),
              ),
            ),
          );
          return tester.getTopLeft(find.text('Body')).dy;
        }

        expect(await bodyTop(safeArea: true), 30);
        expect(await bodyTop(safeArea: false), 0);
      },
    );
  });

  group('app bar', () {
    testWidgets('leading fires its event, drawn the way it was named', (
      tester,
    ) async {
      listen('lead');
      for (final (kind, icon) in [
        ('back', BackButtonIcon),
        ('close', Icon),
        ('menu', Icon),
      ]) {
        await show(
          tester,
          UIBuilder.scaffold(
            appBar: UIBuilder.appBar(
              title: 'Inbox',
              leading: kind,
              leadingEventId: 'lead',
            ),
            body: UIBuilder.text('Body'),
          ),
        );
        final leading = tester.widget<AppBar>(find.byType(AppBar)).leading!;
        expect(
          find.descendant(
            of: find.byWidget(leading),
            matching: find.byType(icon),
          ),
          findsOneWidget,
          reason: kind,
        );
        await tester.tap(find.byWidget(leading));
      }
      expect(events.map((e) => e.$1), ['lead', 'lead', 'lead']);
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });

    testWidgets('a title node replaces the title, and the rest are actions', (
      tester,
    ) async {
      listen('search');
      await show(
        tester,
        UIBuilder.scaffold(
          appBar: UIBuilder.appBar(
            title: 'Plain',
            titleNode: UIBuilder.row(
              children: [
                UIBuilder.icon(codepoint: 0xe318),
                UIBuilder.text('Rich'),
              ],
            ),
            actions: [
              UIBuilder.iconButton(
                icon: 'search',
                tooltip: 'Search',
                eventId: 'search',
              ),
            ],
            centerTitle: true,
            backgroundColor: '#000000',
            elevation: 6,
          ),
          body: UIBuilder.text('Body'),
        ),
      );

      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(find.text('Plain'), findsNothing);
      expect(find.widgetWithText(AppBar, 'Rich'), findsOneWidget);
      expect(bar.actions, hasLength(1));
      expect(bar.centerTitle, isTrue);
      expect(bar.elevation, 6);
      expect(bar.backgroundColor, const Color(0xff000000));
      // No foreground stated: one that reads over the background, for the
      // bar's own widgets and for the text and icon the tree put in it.
      expect(bar.foregroundColor, const Color(0xffffffff));
      expect(
        tester.widget<Text>(find.text('Rich')).style!.color,
        const Color(0xffffffff),
      );
      expect(
        tester
            .widget<Icon>(
              find.byIcon(const IconData(0xe318, fontFamily: 'MaterialIcons')),
            )
            .color,
        const Color(0xffffffff),
      );

      await tester.tap(find.byTooltip('Search'));
      expect(events.single.$1, 'search');
    });

    testWidgets('a stated foreground wins', (tester) async {
      await show(
        tester,
        UIBuilder.scaffold(
          appBar: UIBuilder.appBar(
            title: 'Inbox',
            backgroundColor: '#000000',
            foregroundColor: '#ffeb3b',
          ),
          body: UIBuilder.text('Body'),
        ),
      );

      expect(
        tester.widget<AppBar>(find.byType(AppBar)).foregroundColor,
        const Color(0xffffeb3b),
      );
    });
  });

  group('bottom navigation', () {
    testWidgets('a rail lays the destinations down the leading edge', (
      tester,
    ) async {
      listen('nav');
      await show(
        tester,
        UIBuilder.bottomNavigation(
          eventId: 'nav',
          selectedIndex: 0,
          rail: true,
          items: [
            (label: 'Home', icon: 0xe318, selectedIcon: null),
            (label: 'Search', icon: 0xe567, selectedIcon: null),
          ],
        ),
      );

      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        0,
      );
      await tester.tap(find.text('Search'));
      expect(events.single, event('nav', {'index': 1}));
    });

    testWidgets('a rail with more destinations than fit scrolls to them', (
      tester,
    ) async {
      // A phone held sideways: seven destinations are taller than the window.
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      listen('nav');
      await show(
        tester,
        UIBuilder.bottomNavigation(
          eventId: 'nav',
          selectedIndex: 0,
          rail: true,
          items: [
            for (var i = 0; i < 7; i++)
              (label: 'Item $i', icon: 0xe318, selectedIcon: null),
          ],
        ),
      );

      // No overflow reported, and the last one can be brought up and tapped.
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Item 6'));
      await tester.pump();
      await tester.tap(find.text('Item 6'));
      expect(events.single, event('nav', {'index': 6}));
    });

    testWidgets('fewer than two destinations draw nothing, not an assertion', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.bottomNavigation(
          eventId: 'nav',
          selectedIndex: 0,
          items: [(label: 'Home', icon: 0xe318, selectedIcon: null)],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('layout props', () {
    testWidgets('a column takes a size, a gap and the wider distributions', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.column(
          mainAxisAlignment: 'spaceEvenly',
          mainAxisSize: 'min',
          spacing: 12,
          children: [UIBuilder.text('a'), UIBuilder.text('b')],
        ),
      );
      var column = tester.widget<Column>(find.byType(Column));
      expect(column.mainAxisAlignment, MainAxisAlignment.spaceEvenly);
      // Asked to hug, even though it was asked to distribute.
      expect(column.mainAxisSize, MainAxisSize.min);
      expect(column.spacing, 12);

      await show(
        tester,
        UIBuilder.column(
          mainAxisAlignment: 'spaceAround',
          mainAxisSize: 'max',
          children: [UIBuilder.text('a')],
        ),
      );
      column = tester.widget<Column>(find.byType(Column));
      expect(column.mainAxisAlignment, MainAxisAlignment.spaceAround);
      expect(column.mainAxisSize, MainAxisSize.max);
    });

    testWidgets('a row takes a cross axis alignment and a size', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.row(
          crossAxisAlignment: 'end',
          mainAxisSize: 'min',
          mainAxisAlignment: 'spaceEvenly',
          children: [
            UIBuilder.expanded(fit: 'loose', child: UIBuilder.text('a')),
            UIBuilder.text('b'),
          ],
        ),
      );

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.crossAxisAlignment, CrossAxisAlignment.end);
      expect(row.mainAxisSize, MainAxisSize.min);
      expect(row.mainAxisAlignment, MainAxisAlignment.spaceEvenly);
      // Loose is Flexible: the child may be smaller than its share.
      expect(find.byType(Expanded), findsNothing);
      expect(tester.widget<Flexible>(find.byType(Flexible)).fit, FlexFit.loose);
    });

    testWidgets('a row that stretches is a real Row', (tester) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.box(
            height: 80,
            child: UIBuilder.row(
              crossAxisAlignment: 'stretch',
              children: [UIBuilder.box(width: 10, color: '#ff0000')],
            ),
          ),
        ),
      );

      expect(find.byType(Row), findsOneWidget);
      expect(tester.getSize(find.byType(Container).last), const Size(10, 80));
    });

    testWidgets('a row asked for max is a real Row, as wide as it is allowed', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.row(
            mainAxisSize: 'max',
            mainAxisAlignment: 'end',
            children: [UIBuilder.text('a')],
          ),
        ),
      );

      expect(find.byType(Wrap), findsNothing);
      expect(tester.getSize(find.byType(Row)).width, 800);
      expect(tester.getTopRight(find.text('a')).dx, 800);
    });

    // What two migrated apps reported: with no Expanded in it the row was a
    // Wrap, a Wrap is as wide as its children, and so the two ends of a
    // spaceBetween row sat side by side in the middle of the screen.
    testWidgets('spaceBetween puts the ends at the edges with no Expanded', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.row(
            mainAxisSize: 'max',
            mainAxisAlignment: 'spaceBetween',
            children: [UIBuilder.text('a'), UIBuilder.text('b')],
          ),
        ),
      );

      expect(tester.getTopLeft(find.text('a')).dx, 0);
      expect(tester.getTopRight(find.text('b')).dx, 800);
    });

    testWidgets('a row that asks for nothing still reflows', (tester) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.row(
            children: [UIBuilder.text('a'), UIBuilder.text('b')],
          ),
        ),
      );

      expect(find.byType(Row), findsNothing);
      // As wide as its children, which is what a Wrap is.
      expect(tester.getSize(find.byType(Wrap)).width, lessThan(800));
    });

    testWidgets('a wrap aligns along and across its lines', (tester) async {
      await show(
        tester,
        UIBuilder.wrap(
          alignment: 'spaceBetween',
          crossAxisAlignment: 'end',
          children: [UIBuilder.text('a'), UIBuilder.text('b')],
        ),
      );

      final wrap = tester.widget<Wrap>(find.byType(Wrap));
      expect(wrap.alignment, WrapAlignment.spaceBetween);
      expect(wrap.crossAxisAlignment, WrapCrossAlignment.end);
    });
  });

  group('button props', () {
    testWidgets('outlined and tonal are Material\'s own', (tester) async {
      await show(
        tester,
        UIBuilder.column(
          children: [
            UIBuilder.button(
              label: 'Outlined',
              eventId: 'o',
              variant: 'outlined',
            ),
            UIBuilder.button(label: 'Tonal', eventId: 't', variant: 'tonal'),
          ],
        ),
      );

      expect(find.widgetWithText(OutlinedButton, 'Outlined'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Tonal'), findsOneWidget);
      final outlined = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      // The primary's colour, where 'secondary' draws the secondary's.
      expect(
        outlined.style!.foregroundColor!.resolve({}),
        const Color(0xff1976d2),
      );
    });

    testWidgets('an icon, a foreground and expand', (tester) async {
      await show(
        tester,
        UIBuilder.center(
          child: UIBuilder.button(
            label: 'Send',
            eventId: 's',
            iconCodepoint: 0xe571,
            foregroundColor: '#ffeb3b',
            expand: true,
          ),
        ),
      );

      final button = find.byType(ElevatedButton);
      expect(
        find.descendant(of: button, matching: find.byType(Icon)),
        findsOneWidget,
      );
      expect(tester.widget<Icon>(find.byType(Icon)).icon!.codePoint, 0xe571);
      expect(
        tester
            .widget<ElevatedButton>(button)
            .style!
            .foregroundColor!
            .resolve({}),
        const Color(0xffffeb3b),
      );
      expect(tester.getSize(button).width, 800);
    });

    testWidgets('an icon button takes a colour, a size and disabled', (
      tester,
    ) async {
      listen('i');
      await show(
        tester,
        UIBuilder.iconButton(
          icon: 'rocket_launch',
          codepoint: 0xf0562,
          tooltip: 'Launch',
          eventId: 'i',
          color: '#ff0000',
          size: 40,
          disabled: true,
        ),
      );

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.color, const Color(0xffff0000));
      expect(button.iconSize, 40);
      expect(button.onPressed, isNull);
      // A name the renderer has no constant for is drawn from its codepoint.
      expect(tester.widget<Icon>(find.byType(Icon)).icon!.codePoint, 0xf0562);
    });

    testWidgets('a floating action button with a label is extended', (
      tester,
    ) async {
      listen('f');
      await show(
        tester,
        UIBuilder.scaffold(
          body: UIBuilder.text('Body'),
          floatingActionButton: UIBuilder.floatingActionButton(
            tooltip: 'Compose',
            eventId: 'f',
            icon: 'edit',
            label: 'Compose',
          ),
        ),
      );

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.isExtended, isTrue);
      expect(
        find.widgetWithText(FloatingActionButton, 'Compose'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.edit), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      expect(events.single.$1, 'f');
    });
  });

  group('text props', () {
    testWidgets('alignment, spacing, line height, family and italic', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.text(
          'Styled',
          textAlign: 'center',
          letterSpacing: 1.5,
          lineHeight: 1.4,
          fontFamily: 'monospace',
          italic: true,
          fontWeight: 900,
        ),
      );

      final text = tester.widget<Text>(find.text('Styled'));
      expect(text.textAlign, TextAlign.center);
      expect(text.style!.letterSpacing, 1.5);
      expect(text.style!.height, 1.4);
      expect(text.style!.fontFamily, 'monospace');
      expect(text.style!.fontFamilyFallback, contains('Menlo'));
      expect(text.style!.fontStyle, FontStyle.italic);
      expect(text.style!.fontWeight, FontWeight.w900);
    });

    testWidgets('selectable text can be selected', (tester) async {
      await show(tester, UIBuilder.text('Copy me', selectable: true));

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('Copy me'), findsOneWidget);
    });

    testWidgets('spans are runs with their own style', (tester) async {
      await show(
        tester,
        UIBuilder.text(
          'Hello world',
          fontSize: 20,
          spans: [
            {'text': 'Hello '},
            {
              'text': 'world',
              'color': '#80ff0000',
              'fontWeight': 700,
              'italic': true,
              'decoration': 'underline',
            },
          ],
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.style!.fontSize, 20);
      final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.map((s) => s.text), ['Hello ', 'world']);
      expect(spans[0].style!.color, isNull);
      expect(spans[1].style!.color, const Color(0x80ff0000));
      expect(spans[1].style!.fontWeight, FontWeight.w700);
      expect(spans[1].style!.fontStyle, FontStyle.italic);
      expect(spans[1].style!.decoration, TextDecoration.underline);
      expect(find.text('Hello world', findRichText: true), findsOneWidget);
    });
  });

  group('text field props', () {
    WidgetNode field(Map<String, dynamic> props) => WidgetNode(
      type: 'TextField',
      props: {'hint': 'Hint', 'eventId': 'f', ...props},
    );

    testWidgets('keyboard, capitalisation, length, alignment and helper', (
      tester,
    ) async {
      await show(
        tester,
        field({
          'keyboardType': 'email',
          'textCapitalization': 'words',
          'maxLength': 12,
          'textAlign': 'right',
          'helper': 'We never share it',
          'prefixIcon': 0xe158,
        }),
      );

      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.keyboardType, TextInputType.emailAddress);
      expect(input.textCapitalization, TextCapitalization.words);
      expect(input.maxLength, 12);
      expect(input.textAlign, TextAlign.right);
      expect(input.decoration!.helperText, 'We never share it');
      expect((input.decoration!.prefixIcon! as Icon).icon!.codePoint, 0xe158);
    });

    testWidgets('every keyboard name reaches a Flutter keyboard', (
      tester,
    ) async {
      const keyboards = {
        'number': TextInputType.number,
        'decimal': TextInputType.numberWithOptions(decimal: true),
        'phone': TextInputType.phone,
        'url': TextInputType.url,
        'multiline': TextInputType.multiline,
      };
      for (final MapEntry(key: name, value: keyboard) in keyboards.entries) {
        await show(tester, field({'keyboardType': name}));
        expect(
          tester.widget<TextField>(find.byType(TextField)).keyboardType,
          keyboard,
          reason: name,
        );
      }
    });

    testWidgets('a read-only field that is tappable fires its tap', (
      tester,
    ) async {
      listen('f_tap');
      await show(tester, field({'readOnly': true, 'tappable': true}));

      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      await tester.tap(find.byType(TextField));
      expect(events.single.$1, 'f_tap');
    });

    testWidgets('a suffix glyph the app listens to is a button', (
      tester,
    ) async {
      listen('f_suffix');
      await show(tester, field({'suffixIcon': 0xe16a, 'suffixTappable': true}));

      await tester.tap(find.byType(IconButton));
      expect(events.single.$1, 'f_suffix');

      // One it does not listen to is only a glyph.
      await show(tester, field({'suffixIcon': 0xe16a}));
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(Icon), findsOneWidget);
    });
  });

  group('lazy list', () {
    testWidgets('scrollOffset is applied once per scrollVersion', (
      tester,
    ) async {
      WidgetNode tree(double offset, int version) => UIBuilder.scaffold(
        body: WidgetNode(
          type: 'LazyList',
          props: {
            'id': 'rows',
            'itemCount': 100,
            'itemExtent': 50.0,
            'startIndex': 0,
            'rangeEventId': 'range',
            'scrollOffset': offset,
            'scrollVersion': version,
          },
          children: [
            for (var i = 0; i < 100; i++) UIBuilder.text('Row $i', id: 'r$i'),
          ],
        ),
      );
      double pixels() => tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;

      await show(tester, tree(500, 1));
      await tester.pump();
      expect(pixels(), 500);

      await tester.drag(find.byType(Scrollable), const Offset(0, -100));
      await tester.pump();
      await show(tester, tree(500, 1));
      await tester.pump();
      expect(pixels(), 600);

      await show(tester, tree(50, 2));
      await tester.pump();
      await tester.pump();
      expect(pixels(), 50);
    });
  });

  group('renderer events', () {
    Future<_ListeningApp> host(
      WidgetTester tester,
      List<String> listenTo, {
      MediaQueryData media = const MediaQueryData(
        size: Size(800, 600),
        padding: EdgeInsets.fromLTRB(1, 24, 2, 34),
        viewInsets: EdgeInsets.only(bottom: 300),
        devicePixelRatio: 3,
        platformBrightness: Brightness.dark,
        textScaler: TextScaler.linear(1.5),
      ),
    }) async {
      final app = _ListeningApp(listenTo);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: media,
            child: NativeUIAppHost(app: app),
          ),
        ),
      );
      await tester.pump();
      return app;
    }

    testWidgets('the viewport is sent after the first layout', (tester) async {
      final app = await host(tester, [RendererEvents.viewport]);

      expect(
        app.heard.single,
        event(RendererEvents.viewport, {
          'width': 800.0,
          'height': 600.0,
          'paddingTop': 24.0,
          'paddingBottom': 34.0,
          'paddingLeft': 1.0,
          'paddingRight': 2.0,
          'keyboardInset': 300.0,
          'devicePixelRatio': 3.0,
          'textScale': 1.5,
          'dark': true,
        }),
      );
    });

    testWidgets('and again when it changes, but not when it does not', (
      tester,
    ) async {
      final app = _ListeningApp([RendererEvents.viewport]);
      Future<void> pump(Size size) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.fromSize(
                size: size,
                child: NativeUIAppHost(app: app),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pump(const Size(400, 300));
      await pump(const Size(400, 300));
      expect(app.heard, hasLength(1));
      // The room the host was given, not the screen it is on.
      expect(app.heard.single.$2['width'], 400.0);

      await pump(const Size(500, 300));
      expect(app.heard, hasLength(2));
      expect(app.heard.last.$2['width'], 500.0);
    });

    testWidgets('keys are named the way KeyboardEvent.key names them', (
      tester,
    ) async {
      final app = await host(tester, [RendererEvents.key]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);

      expect(app.heard.map((e) => (e.$2['key'], e.$2['down'])), [
        ('ArrowUp', true),
        ('ArrowUp', false),
        ('Enter', true),
        ('Enter', false),
        (' ', true),
        (' ', false),
        ('a', true),
        ('a', false),
        ('Shift', true),
        ('PageDown', true),
      ]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets('the lifecycle is sent as the app comes and goes', (
      tester,
    ) async {
      final app = await host(tester, [RendererEvents.lifecycle]);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }

      // 'hidden' has no word of its own in the protocol: it is 'paused', said
      // once.
      expect(app.heard.map((e) => e.$2['state']), [
        'inactive',
        'paused',
        'resumed',
      ]);
    });

    testWidgets('an app that registered for none of them hears nothing, and '
        'nothing is reported as failing', (tester) async {
      final app = await host(tester, const []);
      final renderer = tester
          .state<NativeUIAppHostState>(find.byType(NativeUIAppHost))
          .renderer;
      expect(renderer.handles(RendererEvents.viewport), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(app.heard, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
