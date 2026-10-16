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

    test('moves the page beneath as well: under, as one is pushed over it',
        () async {
      await renderer.render(screen('one'));
      await renderer.render(
        UIBuilder.withPageTransition(screen('two'), {
          'kind': 'push',
          'ms': 400,
          'page': {'dx': 1.0},
          'picture': {'dx': -0.5},
        }),
      );
      final picture = leaving()!.getAnimations().toDart.single..pause();
      picture.currentTime = 399.toJS;
      // Half its own width, to the start.
      final box = root.getBoundingClientRect();
      expect(
        leaving()!.getBoundingClientRect().left,
        closeTo(box.left - box.width / 2, 5),
      );
      expect(root.firstElementChild!.getAnimations().toDart, hasLength(1));
      expect(
        int.parse(root.style.zIndex),
        greaterThan(int.parse(leaving()!.style.zIndex)),
      );
    });

    test('and out from under, as the one over it is popped', () async {
      await renderer.render(screen('one'));
      await renderer.render(
        UIBuilder.withPageTransition(screen('two'), {
          'kind': 'pop',
          'ms': 400,
          'picture': {'opacity': 0.0},
          'page': {'dx': -0.5},
        }),
      );
      final page = root.firstElementChild!;
      final run = page.getAnimations().toDart.single..pause();
      run.currentTime = 0.toJS;
      expect(
        page.getBoundingClientRect().left,
        closeTo(
          root.getBoundingClientRect().left -
              page.getBoundingClientRect().width / 2,
          1,
        ),
      );
      expect(leaving()!.getAnimations().toDart, hasLength(1));
      // The picture leaving stays on top.
      expect(root.style.zIndex, isEmpty);
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

    test('a shuttle is laid out at the size the flight has got to',
        () async {
      await renderer.render(page('one', down: 0));
      await renderer.render(
        UIBuilder.withPageTransition(
          page('two', down: 300, shuttle: UIBuilder.text('in the air')),
          {'kind': 'push', 'ms': 400},
        ),
      );
      final run = flight().getAnimations().toDart.single..pause();
      run.currentTime = 0.toJS;
      // Its own width where it starts: not the end's, stretched.
      expect(flight().getBoundingClientRect().width, closeTo(40, 1));
      expect(web.window.getComputedStyle(flight()).transform, 'none');
    });

    test('what stands in for it shows in its room while it flies', () async {
      await renderer.render(page('one', down: 0));
      final two = page('two', down: 300);
      final hero = two.children!.last;
      await renderer.render(
        UIBuilder.withPageTransition(
          UIBuilder.column(
            crossAxisAlignment: 'start',
            children: [
              two.children!.first,
              UIBuilder.box(
                hero: 'picture',
                heroPlaceholder: UIBuilder.text('waiting'),
                width: 40,
                height: 40,
                child: hero.children!.single,
              ),
            ],
          ),
          {'kind': 'push', 'ms': 400},
        ),
      );
      final standIn =
          root.querySelector('.dnn-hero-placeholder')! as web.HTMLElement;
      expect(standIn.textContent, 'waiting');
      expect(web.window.getComputedStyle(standIn).visibility, 'visible');
      final run = flight().getAnimations().toDart.single..finish();
      await run.finished.toDart;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(root.querySelector('.dnn-hero-placeholder'), isNull);
    });

    test("a box that is only a hero is its child's size, stretched or not",
        () async {
      await renderer.render(page('one', down: 0));
      await renderer.render(
        UIBuilder.withPageTransition(
          UIBuilder.column(
            crossAxisAlignment: 'stretch',
            children: [
              UIBuilder.box(
                hero: 'picture',
                heroPlaceholder: UIBuilder.text('waiting'),
                child: UIBuilder.box(width: 60, height: 50, color: '#3366ff'),
              ),
            ],
          ),
          {'kind': 'push', 'ms': 400},
        ),
      );
      final hero = root.querySelector('[data-hero]')!;
      expect(hero.getBoundingClientRect().width, greaterThan(100));
      final standIn = root.querySelector('.dnn-hero-placeholder')!;
      expect(standIn.getBoundingClientRect().width, closeTo(60, 1));
      expect(standIn.getBoundingClientRect().height, closeTo(50, 1));
      final run = flight().getAnimations().toDart.single..finish();
      await run.finished.toDart;
      expect(
        flight().getBoundingClientRect().width,
        closeTo(60, 1),
        reason: 'it lands on the child, not the stretched box',
      );
    });

    test('the hero it leaves shows its own stand-in in the old page',
        () async {
      await renderer.render(
        UIBuilder.column(
          crossAxisAlignment: 'start',
          children: [
            UIBuilder.box(
              hero: 'picture',
              heroPlaceholder: UIBuilder.text('left behind'),
              width: 40,
              height: 40,
              child: UIBuilder.text('one'),
            ),
          ],
        ),
      );
      await renderer.render(
        UIBuilder.withPageTransition(
          page('two', down: 300),
          {'kind': 'push', 'ms': 400},
        ),
      );
      final standIn =
          leaving()!.querySelector('.dnn-hero-placeholder')! as web.HTMLElement;
      expect(standIn.textContent, 'left behind');
      expect(web.window.getComputedStyle(standIn).visibility, 'visible');
      expect(standIn.getBoundingClientRect().height, closeTo(40, 1));
      expect(
        root.querySelector('.dnn-hero-placeholder'),
        isNull,
        reason: 'the arriving hero said nothing stands in for it',
      );
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
