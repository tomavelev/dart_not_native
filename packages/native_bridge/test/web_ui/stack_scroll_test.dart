@TestOn('browser')
/// Layers and scrollers: a stack with pinned children, and a scroll viewport
/// that keeps its place while the app re-renders around it.
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
    renderer = WebUIRenderer(root: root, animations: false);
  });
  tearDown(() => root.remove());

  web.HTMLElement of(String type) =>
      root.querySelector('[data-type="$type"]')! as web.HTMLElement;

  group('a stack', () {
    test('places its unpinned children at the alignment', () async {
      await renderer.render(
        UIBuilder.stack(
          alignment: [0, 1],
          children: [UIBuilder.text('a'), UIBuilder.text('b')],
        ),
      );

      final stack = of('Stack');
      expect(stack.className, 'dnn-stack');
      expect(stack.style.getPropertyValue('justify-items'), 'center');
      expect(stack.style.getPropertyValue('align-items'), 'end');
      expect(childTypes(stack), ['Text', 'Text']);
    });

    test('fit: expand stretches them to fill it', () async {
      await renderer.render(
        UIBuilder.stack(fit: 'expand', children: [UIBuilder.text('a')]),
      );

      expect(of('Stack').style.getPropertyValue('justify-items'), 'stretch');
      expect(of('Stack').style.getPropertyValue('align-items'), 'stretch');
    });

    test('clips unless told not to', () async {
      await renderer.render(
        UIBuilder.stack(clip: false, children: [UIBuilder.text('a')]),
      );
      expect(of('Stack').style.getPropertyValue('overflow'), 'visible');

      await renderer.render(UIBuilder.stack(children: [UIBuilder.text('a')]));
      // Back to the stylesheet's own answer, which is to clip.
      expect(of('Stack').style.getPropertyValue('overflow'), isEmpty);
    });

    test('a pinned child carries the edges it names and no others', () async {
      await renderer.render(
        UIBuilder.stack(
          children: [
            UIBuilder.positioned(
              left: 4,
              bottom: 8,
              width: 30,
              child: UIBuilder.text('pin'),
            ),
          ],
        ),
      );

      final style = of('Positioned').style;
      expect(style.getPropertyValue('left'), '4px');
      expect(style.getPropertyValue('bottom'), '8px');
      expect(style.getPropertyValue('width'), '30px');
      expect(style.getPropertyValue('top'), isEmpty);
      expect(style.getPropertyValue('right'), isEmpty);
    });

    test('fill pins all four edges', () async {
      await renderer.render(
        UIBuilder.stack(
          children: [
            UIBuilder.positioned(fill: true, child: UIBuilder.text('pin')),
          ],
        ),
      );

      final style = of('Positioned').style;
      for (final edge in ['left', 'top', 'right', 'bottom']) {
        expect(style.getPropertyValue(edge), '0px', reason: edge);
      }
    });

    test('moving a pinned child moves its element, and keeps what is in it',
        () async {
      WidgetNode at(double left) => UIBuilder.stack(
        children: [
          UIBuilder.positioned(
            left: left,
            top: 0,
            child: UIBuilder.textField(hint: 'Name', eventId: 'name'),
          ),
        ],
      );
      await renderer.render(at(10));
      final pinned = of('Positioned');
      final field = root.querySelector('input')! as web.HTMLInputElement
        ..focus();

      await renderer.render(at(55));

      expect(of('Positioned'), same(pinned));
      expect(pinned.style.getPropertyValue('left'), '55px');
      expect(web.document.activeElement, same(field));
    });
  });

  group('a scroller', () {
    WidgetNode tall({
      List<double>? padding,
      bool refreshing = false,
      String? refreshEventId,
      double? scrollOffset,
      int? scrollVersion,
      bool reverse = false,
      String axis = 'vertical',
      bool shrinkWrap = false,
    }) => node(
      'Scroll',
      {
        if (axis != 'vertical') 'axis': axis,
        'padding': ?padding,
        if (shrinkWrap) 'shrinkWrap': true,
        if (reverse) 'reverse': true,
        'refreshEventId': ?refreshEventId,
        if (refreshEventId != null) 'refreshing': refreshing,
        'scrollOffset': ?scrollOffset,
        if (scrollOffset != null) 'scrollVersion': scrollVersion ?? 0,
      },
      [UIBuilder.sizedBox(height: 2000, width: 2000)],
    );

    /// The stylesheet is not loaded in these tests, so the viewport is given
    /// the two things from it that scrolling needs.
    web.HTMLElement viewport() {
      final element = of('Scroll');
      element.style
        ..height = '200px'
        ..width = '200px'
        ..overflow = 'auto';
      return element;
    }

    test('holds its child in a padded content box', () async {
      await renderer.render(tall(padding: [1, 2, 3, 4]));

      final content = of('Scroll').querySelector('.dnn-scroll__content')!
          as web.HTMLElement;
      expect(content.style.getPropertyValue('padding'), '2px 3px 4px 1px');
      expect(childTypes(content), ['SizedBox']);
    });

    test('axis, reverse and shrinkWrap are classes the stylesheet reads',
        () async {
      await renderer.render(
        tall(axis: 'horizontal', reverse: true, shrinkWrap: true),
      );

      final classes = of('Scroll').classList;
      expect(classes.contains('dnn-scroll--horizontal'), isTrue);
      expect(classes.contains('dnn-scroll--reverse'), isTrue);
      expect(classes.contains('dnn-scroll--shrink'), isTrue);
    });

    test('keeps its offset when its props change', () async {
      await renderer.render(tall(padding: [0, 0, 0, 0]));
      final before = viewport()..scrollTop = 340;

      await renderer.render(tall(padding: [8, 8, 8, 8]));

      expect(of('Scroll'), same(before));
      expect(before.scrollTop, 340);
    });

    test('jumps to an offset on the first render', () async {
      // For this one the viewport has to scroll the moment it is built, so
      // the rule the stylesheet would have supplied is supplied here.
      final sheet = web.document.createElement('style')
        ..textContent = '.dnn-scroll { height: 200px; overflow: auto; }';
      web.document.head!.appendChild(sheet);
      addTearDown(() => sheet.remove());

      await renderer.render(tall(scrollOffset: 120));

      expect(of('Scroll').scrollTop, 120);
    });

    test('jumps again only when the version is a new one', () async {
      await renderer.render(tall(scrollOffset: 0));
      final scroller = viewport();

      await renderer.render(tall(scrollOffset: 300, scrollVersion: 1));
      expect(scroller.scrollTop, 300);

      // The user scrolls on; a render that repeats the last ask leaves them
      // where they are.
      scroller.scrollTop = 500;
      await renderer.render(
        tall(scrollOffset: 300, scrollVersion: 1, padding: [0, 0, 0, 0]),
      );
      expect(scroller.scrollTop, 500);

      await renderer.render(tall(scrollOffset: 40, scrollVersion: 2));
      expect(scroller.scrollTop, 40);
    });

    test('says where it has been scrolled to, once it has come to rest',
        () async {
      final reports = <Map<String, dynamic>>[];
      renderer.onEvent('at', reports.add);
      await renderer.render(
        node(
          'Scroll',
          {'scrollEventId': 'at'},
          [UIBuilder.sizedBox(height: 2000, width: 100)],
        ),
      );
      final scroller = viewport();

      // Three moves in quick succession: one report as it starts moving (the
      // first is never held back), one for where it stopped - not three.
      for (final top in [100, 200, 340]) {
        scroller.scrollTop = top;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(reports.length, lessThan(3));
      expect(reports.last['offset'], 340);
      expect(reports.last['maxExtent'], 1800);
      expect(reports.last['viewport'], 200);
    });

    test('a horizontal scroller is moved along its own axis', () async {
      await renderer.render(tall(axis: 'horizontal', scrollOffset: 0));
      final scroller = viewport();

      await renderer.render(
        tall(axis: 'horizontal', scrollOffset: 75, scrollVersion: 1),
      );

      expect(scroller.scrollLeft, 75);
      expect(scroller.scrollTop, 0);
    });

    group('pull to refresh', () {
      web.TouchEvent touch(String type, web.Element target, num y) {
        final point = web.Touch(
          web.TouchInit(identifier: 1, target: target, clientY: y, clientX: 10),
        );
        return web.TouchEvent(
          type,
          web.TouchEventInit(
            touches: type == 'touchend' ? <web.Touch>[].toJS : [point].toJS,
            bubbles: true,
            cancelable: true,
          ),
        );
      }

      test('a pull past the threshold at the top sends the event', () async {
        var refreshes = 0;
        renderer.onEvent('refresh', (_) => refreshes++);
        await renderer.render(tall(refreshEventId: 'refresh'));
        final scroller = viewport();

        scroller.dispatchEvent(touch('touchstart', scroller, 100));
        scroller.dispatchEvent(touch('touchmove', scroller, 200));
        scroller.dispatchEvent(touch('touchmove', scroller, 300));
        scroller.dispatchEvent(touch('touchend', scroller, 300));

        expect(refreshes, 1);
      });

      test('a short pull puts the spinner away and sends nothing', () async {
        var refreshes = 0;
        renderer.onEvent('refresh', (_) => refreshes++);
        await renderer.render(tall(refreshEventId: 'refresh'));
        final scroller = viewport();

        scroller.dispatchEvent(touch('touchstart', scroller, 100));
        scroller.dispatchEvent(touch('touchmove', scroller, 140));
        final badge = scroller.querySelector('.dnn-scroll__badge')!
            as web.HTMLElement;
        expect(badge.style.getPropertyValue('transform'), isNotEmpty);
        scroller.dispatchEvent(touch('touchend', scroller, 140));

        expect(refreshes, 0);
        expect(badge.style.getPropertyValue('transform'), isEmpty);
      });

      test('a pull that starts down the list is just a scroll', () async {
        var refreshes = 0;
        renderer.onEvent('refresh', (_) => refreshes++);
        await renderer.render(tall(refreshEventId: 'refresh'));
        final scroller = viewport()..scrollTop = 150;

        scroller.dispatchEvent(touch('touchstart', scroller, 100));
        scroller.dispatchEvent(touch('touchmove', scroller, 400));
        scroller.dispatchEvent(touch('touchend', scroller, 400));

        expect(refreshes, 0);
      });

      test('the spinner shows for as long as the tree says refreshing',
          () async {
        await renderer.render(tall(refreshEventId: 'refresh'));
        final scroller = viewport()..scrollTop = 90;
        final indicator = scroller.querySelector('.dnn-scroll__refresh')!;
        expect(indicator.classList.contains('dnn-scroll__refresh--on'), isFalse);

        await renderer.render(tall(refreshEventId: 'refresh', refreshing: true));
        expect(indicator.classList.contains('dnn-scroll__refresh--on'), isTrue);
        // And turning it on did not cost the user their place.
        expect(scroller.scrollTop, 90);

        await renderer.render(tall(refreshEventId: 'refresh'));
        expect(indicator.classList.contains('dnn-scroll__refresh--on'), isFalse);
      });

      test('a scroller without it has no indicator at all', () async {
        await renderer.render(tall());

        expect(root.querySelector('.dnn-scroll__refresh'), isNull);
      });
    });
  });

  group('a lazy list', () {
    WidgetNode list({double? scrollOffset, int? scrollVersion}) => node(
      'LazyList',
      {
        'id': 'rows',
        'itemCount': 200,
        'itemExtent': 40.0,
        'startIndex': 0,
        'rangeEventId': 'range',
        'scrollOffset': ?scrollOffset,
        if (scrollOffset != null) 'scrollVersion': scrollVersion ?? 0,
      },
      [
        for (var i = 0; i < 30; i++)
          withId(UIBuilder.text('Row $i'), 'rows/$i'),
      ],
    );

    test('is moved by an offset whose version is new', () async {
      renderer.onEvent('range', (_) {});
      await renderer.render(list());
      final viewport = of('LazyList')..style.height = '200px';

      await renderer.render(list(scrollOffset: 400, scrollVersion: 1));
      expect(viewport.scrollTop, 400);

      viewport.scrollTop = 80;
      await renderer.render(list(scrollOffset: 400, scrollVersion: 1));
      expect(viewport.scrollTop, 80);
    });
  });
}
