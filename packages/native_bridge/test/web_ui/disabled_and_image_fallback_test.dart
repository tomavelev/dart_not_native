@TestOn('browser')
/// Two props in the DOM: `disabled` on the three checkable controls, and the
/// fallback child of an `Image`.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

/// A one-pixel GIF, so a load can succeed without a network.
const _pixel =
    'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

/// Not an image at all, so the load fails.
const _broken = 'data:image/png;base64,AAAA';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<String> events;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    events = [];
    renderer.onEvent('e', (data) => events.add('$data'));
  });
  tearDown(() => root.remove());

  group('disabled', () {
    const controls = {
      'Checkbox': 'checked',
      'Radio': 'selected',
      'Toggle': 'enabled',
    };

    web.HTMLInputElement input() =>
        root.querySelector('input')! as web.HTMLInputElement;
    web.Element control(String type) =>
        root.querySelector('[data-type="$type"]')!;

    controls.forEach((type, state) {
      WidgetNode build({required bool disabled, bool on = false}) =>
          node(type, {
            'eventId': 'e',
            state: on,
            'label': 'Label',
            if (type == 'Radio') 'value': 'a',
            if (disabled) 'disabled': true,
          });

      test('a disabled $type cannot be changed and says so', () async {
        await renderer.render(build(disabled: true));

        expect(input().disabled, isTrue);
        expect(
          control(type).classList.contains('dnn-choice--disabled'),
          isTrue,
        );
        // The browser refuses a click on a disabled input, so nothing is sent.
        input().click();
        expect(events, isEmpty);
        expect(input().checked, isFalse);
      });

      test('a $type that is enabled again is the same element', () async {
        await renderer.render(build(disabled: true));
        final before = control(type);
        final built = renderer.debugCreateCount;

        await renderer.render(build(disabled: false));

        expect(control(type), same(before));
        expect(renderer.debugCreateCount, built);
        expect(input().disabled, isFalse);
        expect(before.classList.contains('dnn-choice--disabled'), isFalse);
        input().click();
        expect(events, hasLength(1));
      });

      test('a $type is ticked in place too', () async {
        await renderer.render(build(disabled: false));
        final before = input();

        await renderer.render(build(disabled: false, on: true));

        expect(input(), same(before));
        expect(input().checked, isTrue);
      });
    });

    test('a different label is a different control, and is rebuilt', () async {
      await renderer.render(
        node('Checkbox', {'eventId': 'e', 'checked': false, 'label': 'One'}),
      );
      final before = control('Checkbox');

      await renderer.render(
        node('Checkbox', {'eventId': 'e', 'checked': false, 'label': 'Two'}),
      );

      expect(control('Checkbox'), isNot(same(before)));
      expect(control('Checkbox').textContent, contains('Two'));
    });
  });

  group('an image\'s fallback child', () {
    web.HTMLImageElement img() =>
        root.querySelector('img')! as web.HTMLImageElement;
    web.Element fallback() => root.querySelector('.dnn-image-frame__fallback')!;

    /// Waits for [image] to finish, one way or the other.
    Future<void> settled(web.HTMLImageElement image) {
      if (image.complete) return Future<void>.delayed(Duration.zero);
      final done = Completer<void>();
      void finish(web.Event _) {
        if (!done.isCompleted) done.complete();
      }

      image
        ..addEventListener('load', finish.toJS)
        ..addEventListener('error', finish.toJS);
      return done.future.then((_) => Future<void>.delayed(Duration.zero));
    }

    WidgetNode image(String src, {WidgetNode? fallback}) => UIBuilder.image(
      src: src,
      alt: 'Avatar of Sam',
      width: 48,
      height: 48,
      fallback: fallback,
      id: 'avatar',
    );

    test('an image without one is a plain <img>, as before', () async {
      await renderer.render(image(_pixel));

      final element = web.document.getElementById('avatar')!;
      expect(element.tagName.toLowerCase(), 'img');
      expect(root.querySelector('.dnn-image-frame'), isNull);
    });

    test('is drawn in a frame of the image\'s size, beside the <img>', () async {
      await renderer.render(image(_broken, fallback: UIBuilder.text('SK')));

      final frame = web.document.getElementById('avatar')! as web.HTMLElement;
      expect(frame.classList.contains('dnn-image-frame'), isTrue);
      expect(frame.style.getPropertyValue('width'), '48px');
      expect(frame.style.getPropertyValue('height'), '48px');
      expect(fallback().textContent, 'SK');
      // The alt text is still the image's name.
      expect(frame.getAttribute('aria-label'), 'Avatar of Sam');
      expect(img().alt, 'Avatar of Sam');
    });

    test('shows instead of the image when loading fails', () async {
      await renderer.render(image(_broken, fallback: UIBuilder.text('SK')));
      await settled(img());

      expect(img().hasAttribute('hidden'), isTrue);
      expect(fallback().hasAttribute('hidden'), isFalse);
    });

    test('gives way to the image once it has loaded', () async {
      await renderer.render(image(_pixel, fallback: UIBuilder.text('SK')));
      await settled(img());

      expect(img().hasAttribute('hidden'), isFalse);
      expect(fallback().hasAttribute('hidden'), isTrue);
    });

    test('a rebuild that keeps the image keeps the element, loaded', () async {
      await renderer.render(image(_pixel, fallback: UIBuilder.text('SK')));
      await settled(img());
      final before = img();

      await renderer.render(image(_pixel, fallback: UIBuilder.text('SK')));

      expect(img(), same(before));
      expect(img().hasAttribute('hidden'), isFalse);
    });

    test('the fallback itself is patched like any other child', () async {
      await renderer.render(image(_broken, fallback: UIBuilder.text('SK')));
      await renderer.render(image(_broken, fallback: UIBuilder.text('AB')));

      expect(fallback().textContent, 'AB');
    });

    test('an image that gains a fallback is rebuilt around it', () async {
      await renderer.render(image(_broken));
      await renderer.render(image(_broken, fallback: UIBuilder.text('SK')));

      expect(root.querySelector('.dnn-image-frame'), isNotNull);
      expect(fallback().textContent, 'SK');

      await renderer.render(image(_broken));
      expect(root.querySelector('.dnn-image-frame'), isNull);
      expect(web.document.getElementById('avatar')!.tagName.toLowerCase(), 'img');
    });
  });
}
