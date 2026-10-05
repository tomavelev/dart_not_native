@TestOn('browser')
/// The box: size, space, paint and touch around one child.
///
/// Everything a box's props say is an inline style or an attribute, so that is
/// what is asserted - and because a box is patched rather than rebuilt, each
/// thing is also checked to go away again when the props stop saying it.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<(String, Map<String, dynamic>)> events;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    events = [];
  });
  tearDown(() => root.remove());

  void listen(List<String> ids) {
    for (final id in ids) {
      renderer.onEvent(id, (data) => events.add((id, data)));
    }
  }

  /// The events so far, each as its id and what it carried.
  List<String> log() => [for (final event in events) '${event.$1} ${event.$2}'];

  web.HTMLElement box() =>
      root.querySelector('[data-type="Box"]')! as web.HTMLElement;
  String style(String property) => box().style.getPropertyValue(property);

  /// A box pinned to a known place in the window, so points can be computed.
  WidgetNode placed(Map<String, dynamic> props, {String? id}) => node('Box', {
    'width': 100.0,
    'height': 60.0,
    'id': ?id,
    ...props,
  });

  group('size and space', () {
    test('a stated size and its bounds are written in pixels', () async {
      await renderer.render(
        UIBuilder.box(
          width: 120,
          height: 40,
          minWidth: 10,
          maxWidth: 200,
          minHeight: 5,
          maxHeight: 90,
        ),
      );

      expect(style('width'), '120px');
      expect(style('height'), '40px');
      expect(style('min-width'), '10px');
      expect(style('max-width'), '200px');
      expect(style('min-height'), '5px');
      expect(style('max-height'), '90px');
      // A stated size is the size, not a suggestion a crowded row may shrink.
      expect(style('flex-shrink'), '0');
    });

    test('padding and margin arrive as left, top, right, bottom', () async {
      await renderer.render(
        UIBuilder.box(padding: [1, 2, 3, 4], margin: [5, 6, 7, 8]),
      );

      // CSS starts at the top.
      expect(style('padding'), '2px 3px 4px 1px');
      expect(style('margin'), '6px 7px 8px 5px');
    });

    test('expand fills by class, with the margins taken off', () async {
      await renderer.render(
        UIBuilder.box(expand: 'both', margin: [4, 2, 6, 8]),
      );

      expect(box().classList.contains('dnn-fill-w'), isTrue);
      expect(box().classList.contains('dnn-fill-h'), isTrue);
      expect(style('--dnn-mx'), '10px');
      expect(style('--dnn-my'), '10px');
    });

    test('a ratio with nothing to derive from takes the width offered',
        () async {
      await renderer.render(UIBuilder.box(aspectRatio: 2));

      expect(style('aspect-ratio'), startsWith('2'));
      expect(box().classList.contains('dnn-fill-w'), isTrue);
    });

    test('an alignment places the child, snapping to the nearest point',
        () async {
      await renderer.render(
        UIBuilder.box(alignment: [1, -0.2], child: UIBuilder.text('x')),
      );

      // Across, the side is named: an alignment's x is physical, and a grid's
      // `end` would be the left in a screen that reads from the right.
      expect(style('justify-items'), 'right');
      expect(style('align-items'), 'center');
    });
  });

  group('paint', () {
    test('an eight-digit colour is alpha first, and becomes rgba', () async {
      await renderer.render(UIBuilder.box(color: '#40ff0000'));

      expect(style('background-color'), startsWith('rgba(255, 0, 0, 0.25'));
      // Mostly see-through: the text is really on whatever is behind it.
      expect(style('color'), isEmpty);
    });

    test('text over an opaque fill reads against the fill', () async {
      await renderer.render(UIBuilder.box(color: '#102030'));

      expect(style('background-color'), 'rgb(16, 32, 48)');
      expect(style('color'), 'rgb(255, 255, 255)');
    });

    test('border, corners and shadow', () async {
      await renderer.render(
        UIBuilder.box(
          borderWidth: 2,
          borderColor: '#ff112233',
          borderRadii: [1, 2, 3, 4],
          shadow: {'color': '#40000000', 'blur': 6, 'dx': 1, 'dy': 2},
        ),
      );

      expect(style('border'), '2px solid rgb(17, 34, 51)');
      expect(style('border-radius'), '1px 2px 3px 4px');
      expect(style('box-shadow'), 'rgba(0, 0, 0, 0.25) 1px 2px 6px');
    });

    test('a circle outranks the corner radius', () async {
      await renderer.render(UIBuilder.box(shape: 'circle', borderRadius: 4));

      expect(style('border-radius'), '50%');
    });

    test('a linear gradient runs corner to corner by name', () async {
      await renderer.render(
        UIBuilder.box(
          gradient: {
            'type': 'linear',
            'colors': ['#ff0000', '#800000ff'],
            'stops': [0.0, 1.0],
            'begin': [-1, -1],
            'end': [1, 1],
          },
        ),
      );

      final image = style('background-image');
      expect(image, startsWith('linear-gradient(to right bottom'));
      expect(image, contains('rgb(255, 0, 0) 0%'));
      expect(image, contains('rgba(0, 0, 255, 0.5'));
    });

    test('a radial gradient is centred where it begins', () async {
      await renderer.render(
        UIBuilder.box(
          gradient: {
            'type': 'radial',
            'colors': ['#ffffff', '#000000'],
            'begin': [0, -1],
          },
        ),
      );

      expect(style('background-image'), contains('radial-gradient('));
      expect(style('background-image'), contains('at 50% 0%'));
    });

    test('clip, opacity and transform', () async {
      await renderer.render(
        UIBuilder.box(
          clip: true,
          opacity: 0.5,
          transform: {'rotate': 1.5, 'scale': 2, 'dx': 3, 'dy': 4},
        ),
      );

      expect(style('overflow'), 'hidden');
      expect(style('opacity'), '0.5');
      expect(
        style('transform'),
        'translate(3px, 4px) rotate(1.5rad) scale(2)',
      );
    });

    test('tooltip, name and ignoring the pointer', () async {
      await renderer.render(
        UIBuilder.box(
          tooltip: 'Tip',
          semanticLabel: 'A tile',
          ignorePointer: true,
        ),
      );

      expect(box().getAttribute('title'), 'Tip');
      expect(box().getAttribute('aria-label'), 'A tile');
      expect(style('pointer-events'), 'none');
    });
  });

  group('patching', () {
    test('a change of props restyles the same element', () async {
      await renderer.render(
        UIBuilder.box(width: 50, color: '#ff0000', borderRadius: 8),
      );
      final before = box();

      await renderer.render(UIBuilder.box(width: 80, color: '#00ff00'));

      expect(box(), same(before));
      expect(style('width'), '80px');
      expect(style('background-color'), 'rgb(0, 255, 0)');
      // What the new props no longer say is taken back, not left behind.
      expect(style('border-radius'), isEmpty);
    });

    test('animateMs names what moves, so the patch transitions', () async {
      await renderer.render(
        UIBuilder.box(width: 50, opacity: 1, animateMs: 250, curve: 'linear'),
      );

      final transition = style('transition');
      expect(transition, contains('width 250ms linear'));
      expect(transition, contains('opacity 250ms linear'));
      expect(transition, contains('transform 250ms linear'));
      expect(transition, contains('background-color 250ms linear'));

      await renderer.render(UIBuilder.box(width: 50, opacity: 1));
      expect(style('transition'), isEmpty);
    });

    test('the child survives its box being restyled', () async {
      WidgetNode tree(String color) => UIBuilder.box(
        color: color,
        child: UIBuilder.textField(hint: 'Name', eventId: 'name'),
      );
      await renderer.render(tree('#ffffff'));
      final field = root.querySelector('input')! as web.HTMLInputElement
        ..focus();

      await renderer.render(tree('#eeeeee'));

      expect(web.document.activeElement, same(field));
    });
  });

  group('taps', () {
    test('a tap reports where in the box it landed', () async {
      listen(['tap']);
      await renderer.render(placed({'tapEventId': 'tap'}));
      final rect = box().getBoundingClientRect();

      box().dispatchEvent(clickAt(rect.left + 30, rect.top + 20));

      expect(events.single.$1, 'tap');
      expect(events.single.$2['x'], closeTo(30, 1));
      expect(events.single.$2['y'], closeTo(20, 1));
    });

    test('a tappable box is a button the keyboard can press', () async {
      listen(['tap']);
      await renderer.render(placed({'tapEventId': 'tap'}));

      expect(box().getAttribute('role'), 'button');
      expect(box().getAttribute('tabindex'), '0');

      box().dispatchEvent(enterKey());
      box().dispatchEvent(
        web.KeyboardEvent(
          'keydown',
          web.KeyboardEventInit(key: ' ', cancelable: true),
        ),
      );

      // With no pointer, the press is said to land in the middle.
      expect(events, hasLength(2));
      expect(events.first.$2, {'x': 50.0, 'y': 30.0});
    });

    test('a box that stops being tappable stops being a button', () async {
      listen(['tap']);
      await renderer.render(placed({'tapEventId': 'tap'}));
      await renderer.render(placed({}));

      expect(box().hasAttribute('role'), isFalse);
      expect(box().hasAttribute('tabindex'), isFalse);
      box().click();
      expect(events, isEmpty);
    });

    test('the event id is read when the tap arrives, not when it was built',
        () async {
      listen(['first', 'second']);
      await renderer.render(placed({'tapEventId': 'first'}));
      await renderer.render(placed({'tapEventId': 'second'}));

      box().click();

      expect(events.single.$1, 'second');
    });

    test('a button inside a tappable box keeps its own tap', () async {
      listen(['tap', 'inner']);
      await renderer.render(
        node('Box', {'tapEventId': 'tap'}, [
          UIBuilder.button(label: 'Inner', eventId: 'inner', id: 'inner'),
        ]),
      );

      click('inner');

      expect(events.map((e) => e.$1), ['inner']);
    });

    test('two taps in quick succession are a double tap, not two taps',
        () async {
      listen(['tap', 'double']);
      await renderer.render(
        placed({'tapEventId': 'tap', 'doubleTapEventId': 'double'}),
      );

      box().click();
      box().click();
      await settle(400);

      expect(events.map((e) => e.$1), ['double']);
    });

    test('one tap still arrives, once the second has had its chance',
        () async {
      listen(['tap', 'double']);
      await renderer.render(
        placed({'tapEventId': 'tap', 'doubleTapEventId': 'double'}),
      );

      box().click();
      expect(events, isEmpty);
      await settle(400);

      expect(events.map((e) => e.$1), ['tap']);
    });

    test('holding still is a long press, and the click after it is not a tap',
        () async {
      listen(['tap', 'long']);
      await renderer.render(
        placed({'tapEventId': 'tap', 'longPressEventId': 'long'}),
      );
      final rect = box().getBoundingClientRect();

      box().dispatchEvent(pointer('pointerdown', rect.left + 10, rect.top + 5));
      await settle(600);
      box().dispatchEvent(pointer('pointerup', rect.left + 10, rect.top + 5));
      box().dispatchEvent(clickAt(rect.left + 10, rect.top + 5));

      expect(events.map((e) => e.$1), ['long']);
      expect(events.single.$2['x'], closeTo(10, 1));
      expect(events.single.$2['y'], closeTo(5, 1));
    });
  });

  group('panning', () {
    test('start, updates with movement, and an end', () async {
      listen(['pan_start', 'pan_update', 'pan_end']);
      await renderer.render(placed({'panEventId': 'pan'}));
      final rect = box().getBoundingClientRect();
      final x = rect.left + 10, y = rect.top + 10;

      box().dispatchEvent(pointer('pointerdown', x, y, kind: 'touch'));
      box().dispatchEvent(pointer('pointermove', x + 20, y, kind: 'touch'));
      box().dispatchEvent(pointer('pointermove', x + 30, y + 5, kind: 'touch'));
      box().dispatchEvent(pointer('pointerup', x + 30, y + 5, kind: 'touch'));

      expect(events.map((e) => e.$1), [
        'pan_start',
        'pan_update',
        'pan_update',
        'pan_end',
      ]);
      // It began where the finger went down.
      expect(events[0].$2['x'], closeTo(10, 1));
      // Each update is the movement since the one before, so they add up to
      // the whole distance.
      expect(events[1].$2['dx'], closeTo(20, 1));
      expect(events[2].$2['dx'], closeTo(10, 1));
      expect(events[2].$2['dy'], closeTo(5, 1));
      expect(events[2].$2['x'], closeTo(40, 1));
      expect(events[3].$2.keys, containsAll(['x', 'y', 'vx', 'vy']));
    });

    test('a pointer that barely moves is not a pan', () async {
      listen(['pan_start', 'pan_update', 'pan_end']);
      await renderer.render(placed({'panEventId': 'pan'}));
      final rect = box().getBoundingClientRect();

      box().dispatchEvent(pointer('pointerdown', rect.left + 5, rect.top + 5));
      box().dispatchEvent(pointer('pointermove', rect.left + 6, rect.top + 6));
      box().dispatchEvent(pointer('pointerup', rect.left + 6, rect.top + 6));

      expect(events, isEmpty);
    });

    test('a pannable box keeps the browser from scrolling with it', () async {
      await renderer.render(placed({'panEventId': 'pan'}));

      expect(box().classList.contains('dnn-box--pan'), isTrue);
    });
  });

  group('drag and drop', () {
    // The drop target is whatever the document says is under the pointer.
    setUp(() => raiseAboveHarness(root));

    WidgetNode board() => UIBuilder.column(
      crossAxisAlignment: 'start',
      children: [
        placed({'dragData': 'card-7'}, id: 'source'),
        placed({'dropEventId': 'drop'}, id: 'target'),
      ],
    );

    web.Element byId(String id) => web.document.getElementById(id)!;
    (double, double) middle(String id) {
      final rect = byId(id).getBoundingClientRect();
      return (rect.left + rect.width / 2, rect.top + rect.height / 2);
    }

    test('a mouse drags as soon as it moves, and drops what it carried',
        () async {
      listen(['drop', 'drop_hover']);
      await renderer.render(board());
      final (sx, sy) = middle('source');
      final (tx, ty) = middle('target');

      byId('source').dispatchEvent(pointer('pointerdown', sx, sy));
      byId('source').dispatchEvent(pointer('pointermove', sx + 10, sy + 10));
      // A copy follows the pointer, outside the app's own root.
      expect(web.document.querySelector('.dnn-drag-ghost'), isNotNull);
      expect(root.querySelector('.dnn-drag-ghost'), isNull);

      web.document.dispatchEvent(pointer('pointermove', tx, ty));
      expect(log().last, 'drop_hover {over: true}');

      web.document.dispatchEvent(pointer('pointerup', tx, ty));

      expect(events.map((e) => e.$1), ['drop_hover', 'drop_hover', 'drop']);
      expect(events[1].$2, {'over': false});
      expect(events.last.$2, {'data': 'card-7'});
      expect(web.document.querySelector('.dnn-drag-ghost'), isNull);
    });

    test('a finger picks up by holding, then drags the same way', () async {
      listen(['drop', 'drop_hover']);
      await renderer.render(board());
      final (sx, sy) = middle('source');
      final (tx, ty) = middle('target');

      byId('source').dispatchEvent(
        pointer('pointerdown', sx, sy, kind: 'touch'),
      );
      expect(web.document.querySelector('.dnn-drag-ghost'), isNull);
      await settle(600);
      expect(web.document.querySelector('.dnn-drag-ghost'), isNotNull);

      web.document.dispatchEvent(pointer('pointermove', tx, ty, kind: 'touch'));
      web.document.dispatchEvent(pointer('pointerup', tx, ty, kind: 'touch'));

      expect(log().last, 'drop {data: card-7}');
    });

    test('leaving a target says so, and a drop on nothing drops nothing',
        () async {
      listen(['drop', 'drop_hover']);
      await renderer.render(board());
      final (sx, sy) = middle('source');
      final (tx, ty) = middle('target');

      byId('source').dispatchEvent(pointer('pointerdown', sx, sy));
      byId('source').dispatchEvent(pointer('pointermove', sx + 10, sy));
      web.document.dispatchEvent(pointer('pointermove', tx, ty));
      web.document.dispatchEvent(pointer('pointermove', tx + 400, ty));
      web.document.dispatchEvent(pointer('pointerup', tx + 400, ty));

      expect(log(), ['drop_hover {over: true}', 'drop_hover {over: false}']);
    });

    test('a cancelled drag puts everything back', () async {
      listen(['drop', 'drop_hover']);
      await renderer.render(board());
      final (sx, sy) = middle('source');
      final (tx, ty) = middle('target');

      byId('source').dispatchEvent(pointer('pointerdown', sx, sy));
      byId('source').dispatchEvent(pointer('pointermove', sx + 10, sy));
      web.document.dispatchEvent(pointer('pointermove', tx, ty));
      web.document.dispatchEvent(pointer('pointercancel', tx, ty));

      expect(events.map((e) => e.$1), ['drop_hover', 'drop_hover']);
      expect(web.document.querySelector('.dnn-drag-ghost'), isNull);
      expect(byId('source').classList.contains('dnn-box--dragging'), isFalse);
    });
  });

  group('measuring', () {
    test('the size is reported once laid out, and again only when it changes',
        () async {
      listen(['size']);
      await renderer.render(placed({'sizeEventId': 'size'}));
      await settle();

      expect(events.single.$2, {'width': 100.0, 'height': 60.0});

      // A render that leaves the size alone reports nothing.
      await renderer.render(placed({'sizeEventId': 'size', 'opacity': 0.5}));
      await settle();
      expect(events, hasLength(1));

      await renderer.render(placed({'sizeEventId': 'size', 'width': 140.0}));
      await settle();
      expect(events.last.$2, {'width': 140.0, 'height': 60.0});
    });
  });
}
