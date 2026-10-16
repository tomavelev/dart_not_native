@TestOn('browser')
/// What the web renderer does with the moves the widget layer now sends: a
/// route's own transition (`page`, `picture`), a hero's arc and shuttle,
/// sticky boxes stacking, and a transform that is a whole matrix.
library;

import 'dart:js_interop';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root);
  });
  tearDown(() {
    root.remove();
    final left = web.document.querySelectorAll(
      '.dnn-hero-flight, .dnn-page-leaving',
    );
    for (var i = 0; i < left.length; i++) {
      (left.item(i) as web.Element).remove();
    }
  });

  WidgetNode screen(String label) => UIBuilder.box(
    width: 200,
    height: 200,
    color: '#ffffff',
    child: UIBuilder.text(label),
  );

  web.HTMLElement? leaving() =>
      web.document.querySelector('.dnn-page-leaving') as web.HTMLElement?;

  group('a route of its own', () {
    test('moves the new page from where it starts, over the old one', () async {
      await renderer.render(screen('one'));
      await renderer.render(
        UIBuilder.withPageTransition(screen('two'), {
          'kind': 'push',
          'ms': 400,
          'page': {'opacity': 0.0, 'dx': 1.0},
        }),
      );

      // The old page lies still beneath the new one.
      expect(leaving(), isNotNull);
      expect(leaving()!.getAnimations().toDart, isEmpty);
      final page = root.firstElementChild!;
      final run = page.getAnimations().toDart.single..pause();
      run.currentTime = 0.toJS;
      final style = web.window.getComputedStyle(page);
      expect(style.opacity, '0');
      expect(
        page.getBoundingClientRect().left,
        closeTo(root.getBoundingClientRect().left + 200, 1),
      );
      expect(
        int.parse(root.style.zIndex),
        greaterThan(int.parse(leaving()!.style.zIndex)),
      );
    });

    test('moves the old page\'s picture away over the new one', () async {
      await renderer.render(screen('one'));
      await renderer.render(
        UIBuilder.withPageTransition(screen('two'), {
          'kind': 'pop',
          'ms': 400,
          'picture': {'scale': 0.5, 'curve': 'easeIn'},
        }),
      );

      final run = leaving()!.getAnimations().toDart.single;
      final timing = run.effect!.getComputedTiming();
      expect(timing.easing, 'ease-in');
      expect(root.firstElementChild!.getAnimations().toDart, isEmpty);
    });

    test('an empty one does not move at all', () async {
      await renderer.render(screen('one'));
      await renderer.render(
        UIBuilder.withPageTransition(screen('two'), {
          'kind': 'push',
          'ms': 400,
          'page': <String, dynamic>{},
        }),
      );
      final run = root.firstElementChild!.getAnimations().toDart.single
        ..pause();
      run.currentTime = 0.toJS;
      expect(web.window.getComputedStyle(root.firstElementChild!).opacity, '1');
    });
  });

  group('a hero', () {
    WidgetNode page(
      String label, {
      required double down,
      double across = 0,
      bool arc = false,
      WidgetNode? shuttle,
    }) => UIBuilder.column(
      crossAxisAlignment: 'start',
      children: [
        UIBuilder.sizedBox(height: down),
        UIBuilder.box(
          hero: 'picture',
          heroArc: arc,
          heroShuttle: shuttle,
          width: 40,
          height: 40,
          margin: [across, 0, 0, 0],
          color: '#3366ff',
          child: UIBuilder.text(label),
        ),
      ],
    );

    web.HTMLElement flight() =>
        web.document.querySelector('.dnn-hero-flight')! as web.HTMLElement;

    test('flies what its shuttle draws, in its place', () async {
      await renderer.render(page('one', down: 0));
      await renderer.render(
        UIBuilder.withPageTransition(
          page('two', down: 300, shuttle: UIBuilder.text('in the air')),
          {'kind': 'push', 'ms': 400},
        ),
      );
      expect(flight().textContent, 'in the air');
    });

    test('along an arc, it is off the straight line half way', () async {
      Future<web.DOMRect> halfWay({
        required bool arc,
        double across = 0,
      }) async {
        await renderer.render(page('one', down: 0));
        await renderer.render(
          UIBuilder.withPageTransition(
            page('two', down: 300, across: across, arc: arc),
            {'kind': 'push', 'ms': 400},
          ),
        );
        final flying = flight();
        final run = flying.getAnimations().toDart.single..pause();
        run.currentTime = 200.toJS;
        final at = flying.getBoundingClientRect();
        // Everything to its end - the page's slide too - before the next.
        for (final any in web.document.getAnimations().toDart) {
          any.finish();
        }
        await settle(20);
        return at;
      }

      final straight = await halfWay(arc: false);
      final arc = await halfWay(arc: true);
      // Straight down is along an axis, where the arc is a line too.
      expect(arc.left, closeTo(straight.left, 1));
      expect(arc.top, closeTo(straight.top, 1));

      // Across as well as down, it swings off the line.
      final line = await halfWay(arc: false, across: 200);
      final swung = await halfWay(arc: true, across: 200);
      expect((swung.left - line.left).abs(), greaterThan(10));
    });
  });

  test('sticky boxes in one scroller stack, each under the last', () async {
    WidgetNode header(String label) =>
        UIBuilder.box(sticky: true, height: 30, child: UIBuilder.text(label));
    await renderer.render(
      UIBuilder.box(
        height: 200,
        child: node(
          'Scroll',
          {'direction': 'vertical'},
          [
            UIBuilder.column(
              children: [
                header('first'),
                UIBuilder.sizedBox(height: 300),
                header('second'),
                UIBuilder.sizedBox(height: 600),
              ],
            ),
          ],
        ),
      ),
    );
    final stuck = root.querySelectorAll('[data-sticky]');
    expect(stuck.length, 2);
    expect((stuck.item(0)! as web.HTMLElement).style.top, '0px');
    expect((stuck.item(1)! as web.HTMLElement).style.top, '30px');
  });

  test('a whole matrix is a matrix3d, about the point it says', () async {
    await renderer.render(
      UIBuilder.box(
        width: 100,
        height: 50,
        transform: {
          'matrix': [1, 0, 0, 0, 0.5, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
          'origin': [-1, -1, 0, 0],
        },
      ),
    );
    final box = root.querySelector('[data-type="Box"]')! as web.HTMLElement;
    expect(box.style.transform, startsWith('matrix3d(1, 0, 0, 0, 0.5'));
    expect(box.style.getPropertyValue('transform-origin'), contains('0%'));
  });
}
