@TestOn('browser')
/// What the web renderer says about a press and a drag as they happen: a
/// pointer going down at once (`tapDownEventId`) and a press that is not a
/// tap after all; what a drag carries (`dragFeedback`), and where and how
/// fast it was let go.
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
    raiseAboveHarness(root);
    renderer = WebUIRenderer(root: root, animations: false);
    events = [];
  });
  tearDown(() {
    root.remove();
    final left = web.document.querySelectorAll(
      '.dnn-drag-ghost, .dnn-drag-feedback',
    );
    for (var i = 0; i < left.length; i++) {
      (left.item(i) as web.Element).remove();
    }
  });

  void listen(List<String> ids) {
    for (final id in ids) {
      renderer.onEvent(id, (data) => events.add((id, data)));
    }
  }

  List<String> heard() => [for (final e in events) e.$1];

  web.Element byId(String id) => web.document.getElementById(id)!;
  (double, double) middle(String id) {
    final rect = byId(id).getBoundingClientRect();
    return (rect.left + rect.width / 2, rect.top + rect.height / 2);
  }

  group('a press', () {
    WidgetNode pad() => node('Box', {
      'width': 100.0,
      'height': 60.0,
      'id': 'pad',
      'tapEventId': 'tap',
      'tapDownEventId': 'down',
    });

    test('is told as the pointer goes down, before the tap', () async {
      listen(['down', 'down_cancel', 'tap']);
      await renderer.render(pad());
      final (x, y) = middle('pad');

      byId('pad').dispatchEvent(pointer('pointerdown', x, y));
      expect(heard(), ['down']);
      expect(events.single.$2['x'], closeTo(50, 1));

      byId('pad').dispatchEvent(pointer('pointerup', x, y));
      byId('pad').dispatchEvent(clickAt(x, y));
      expect(heard(), ['down', 'tap']);
    });

    test(
      'that wanders too far is cancelled, and its click is no tap',
      () async {
        listen(['down', 'down_cancel', 'tap']);
        await renderer.render(pad());
        final (x, y) = middle('pad');

        byId('pad').dispatchEvent(pointer('pointerdown', x - 40, y));
        byId('pad').dispatchEvent(pointer('pointermove', x + 40, y));
        expect(heard(), ['down', 'down_cancel']);

        byId('pad').dispatchEvent(pointer('pointerup', x + 40, y));
        byId('pad').dispatchEvent(clickAt(x + 40, y));
        expect(heard(), ['down', 'down_cancel']);
      },
    );

    test('let go off the box is cancelled', () async {
      listen(['down', 'down_cancel', 'tap']);
      await renderer.render(pad());
      final (x, y) = middle('pad');

      byId('pad').dispatchEvent(pointer('pointerdown', x, y));
      byId('pad').dispatchEvent(pointer('pointerup', x, y + 500));
      expect(heard(), ['down', 'down_cancel']);
    });

    test('taken by the browser is cancelled', () async {
      listen(['down', 'down_cancel', 'tap']);
      await renderer.render(pad());
      final (x, y) = middle('pad');

      byId('pad').dispatchEvent(pointer('pointerdown', x, y, kind: 'touch'));
      byId('pad').dispatchEvent(pointer('pointercancel', x, y, kind: 'touch'));
      expect(heard(), ['down', 'down_cancel']);
    });
  });

  group('a drag', () {
    WidgetNode board({Map<String, dynamic>? feedback}) => UIBuilder.column(
      crossAxisAlignment: 'start',
      children: [
        node('Box', {
          'width': 100.0,
          'height': 60.0,
          'id': 'source',
          'dragData': 'card-7',
          'dragEventId': 'drag',
          'dragFeedback': ?feedback,
        }),
        node('Box', {
          'width': 100.0,
          'height': 60.0,
          'id': 'target',
          'dropEventId': 'drop',
        }),
      ],
    );

    test(
      'carries the feedback it was given, at the feedback\'s own size',
      () async {
        await renderer.render(
          board(feedback: UIBuilder.text('lifted').toJson()),
        );
        final (sx, sy) = middle('source');
        byId('source').dispatchEvent(pointer('pointerdown', sx, sy));
        byId('source').dispatchEvent(pointer('pointermove', sx + 10, sy + 10));

        final carried = web.document.querySelector('.dnn-drag-feedback');
        expect(carried, isNotNull);
        expect(carried!.textContent, 'lifted');
        expect(web.document.querySelector('.dnn-drag-ghost'), isNull);
        // Not stretched to the box it came from.
        expect(
          (carried as web.HTMLElement).style.getPropertyValue('width'),
          isEmpty,
        );
        web.document.dispatchEvent(pointer('pointerup', sx + 10, sy + 10));
        expect(web.document.querySelector('.dnn-drag-feedback'), isNull);
      },
    );

    test('ends saying where the picture was, and how fast it went', () async {
      listen(['drag_start', 'drag_end', 'drop']);
      await renderer.render(board());
      final source = byId('source').getBoundingClientRect();
      final (sx, sy) = middle('source');
      final (tx, ty) = middle('target');

      byId('source').dispatchEvent(pointer('pointerdown', sx, sy));
      byId('source').dispatchEvent(pointer('pointermove', sx + 10, sy + 10));
      await settle(20);
      web.document.dispatchEvent(pointer('pointermove', tx, ty));
      web.document.dispatchEvent(pointer('pointerup', tx, ty));

      final end = events.firstWhere((e) => e.$1 == 'drag_end').$2;
      final drop = events.firstWhere((e) => e.$1 == 'drop').$2;
      // Held 10 right of the middle and 10 down, where it was taken.
      expect(end['x'], tx - (sx + 10 - source.left));
      expect(end['y'], ty - (sy + 10 - source.top));
      expect(drop['x'], end['x']);
      // Moving down the page when it was let go.
      expect(end['vy'], greaterThan(0));
    });

    test('let go after standing still, it was not moving', () async {
      listen(['drag_end']);
      await renderer.render(board());
      final (sx, sy) = middle('source');

      byId('source').dispatchEvent(pointer('pointerdown', sx, sy));
      byId('source').dispatchEvent(pointer('pointermove', sx + 10, sy + 10));
      web.document.dispatchEvent(pointer('pointermove', sx + 60, sy + 10));
      await settle(160);
      web.document.dispatchEvent(pointer('pointerup', sx + 60, sy + 10));

      expect(events.single.$2['vx'], 0);
      expect(events.single.$2['vy'], 0);
    });
  });
}
