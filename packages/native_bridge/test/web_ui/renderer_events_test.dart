@TestOn('browser')
/// The events a renderer raises on its own account: the viewport, hardware
/// keys and whether the page is being looked at.
library;

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

  web.KeyboardEvent key(String type, String name) => web.KeyboardEvent(
    type,
    web.KeyboardEventInit(key: name, bubbles: true, cancelable: true),
  );

  group('the viewport', () {
    test('is sent once the first frame is drawn', () async {
      final seen = <Map<String, dynamic>>[];
      renderer.onEvent(RendererEvents.viewport, seen.add);

      await renderer.render(UIBuilder.text('Hello'));

      expect(seen, hasLength(1));
      final viewport = seen.single;
      expect(viewport.keys, containsAll([
        'width',
        'height',
        'paddingTop',
        'paddingBottom',
        'paddingLeft',
        'paddingRight',
        'keyboardInset',
        'devicePixelRatio',
        'textScale',
        'dark',
      ]));
      expect(viewport['width'], web.window.innerWidth.toDouble());
      expect(viewport['height'], web.window.innerHeight.toDouble());
      expect(viewport['devicePixelRatio'], web.window.devicePixelRatio);
      expect(viewport['dark'], isA<bool>());
      // No notch on a desktop browser, and no keyboard.
      expect(viewport['paddingTop'], 0.0);
      expect(viewport['keyboardInset'], 0.0);
      expect(viewport['textScale'], 1.0);
    });

    test('is not sent again for a render, or a resize that changed nothing',
        () async {
      var count = 0;
      renderer.onEvent(RendererEvents.viewport, (_) => count++);
      await renderer.render(UIBuilder.text('Hello'));

      await renderer.render(UIBuilder.text('Again'));
      web.window.dispatchEvent(web.Event('resize'));

      expect(count, 1);
    });

    test('reaches a handler that only started listening after the frame',
        () async {
      await renderer.render(UIBuilder.text('Hello'));
      var count = 0;

      renderer.onEvent(RendererEvents.viewport, (_) => count++);
      await settle(10);
      expect(count, 1);

      // Registering again - an app does, on every build - is not a new ask.
      renderer.onEvent(RendererEvents.viewport, (_) => count++);
      await settle(10);
      expect(count, 1);
    });
  });

  group('keys', () {
    test('a press and a release are sent with the key\'s name', () async {
      final seen = <String>[];
      renderer.onEvent(RendererEvents.key, (data) => seen.add('$data'));
      await renderer.render(UIBuilder.text('Hello'));

      web.document.body!.dispatchEvent(key('keydown', 'ArrowUp'));
      web.document.body!.dispatchEvent(key('keyup', 'ArrowUp'));
      web.document.body!.dispatchEvent(key('keydown', ' '));

      expect(seen, [
        '{key: ArrowUp, down: true}',
        '{key: ArrowUp, down: false}',
        '{key:  , down: true}',
      ]);
    });

    test('a key typed into a field is text, and is not sent', () async {
      final seen = <String>[];
      renderer.onEvent(RendererEvents.key, (data) => seen.add('$data'));
      await renderer.render(
        UIBuilder.column(
          children: [
            UIBuilder.textField(hint: 'Name', eventId: 'name'),
            UIBuilder.dropdown(
              items: const ['a'],
              selectedIndex: 0,
              eventId: 'pick',
            ),
          ],
        ),
      );

      root.querySelector('input')!.dispatchEvent(key('keydown', 'w'));
      root.querySelector('select')!.dispatchEvent(key('keydown', 'ArrowDown'));

      expect(seen, isEmpty);
    });
  });

  group('lifecycle', () {
    test('a visibility change says whether the page is being looked at',
        () async {
      final seen = <Object?>[];
      renderer.onEvent(RendererEvents.lifecycle, (d) => seen.add(d['state']));
      await renderer.render(UIBuilder.text('Hello'));

      web.document.dispatchEvent(web.Event('visibilitychange'));

      expect(seen, [web.document.hidden ? 'paused' : 'resumed']);
    });

    test('the page going away is detached', () async {
      final seen = <Object?>[];
      renderer.onEvent(RendererEvents.lifecycle, (d) => seen.add(d['state']));
      await renderer.render(UIBuilder.text('Hello'));

      web.window.dispatchEvent(web.Event('pagehide'));

      expect(seen, ['detached']);
    });
  });

  test('with nobody listening, none of them is sent or complained about',
      () async {
    // Everything the renderer does with an event goes through handleEvent;
    // counting its calls is counting what was sent.
    final quiet = _CountingRenderer(root);
    await quiet.render(UIBuilder.text('Hello'));

    web.window.dispatchEvent(web.Event('resize'));
    web.document.body!.dispatchEvent(key('keydown', 'a'));
    web.document.dispatchEvent(web.Event('visibilitychange'));
    web.window.dispatchEvent(web.Event('pagehide'));

    expect(quiet.sent, isEmpty);
  });
}

class _CountingRenderer extends WebUIRenderer {
  _CountingRenderer(web.HTMLElement root)
    : super(root: root, animations: false);

  final List<String> sent = [];

  @override
  Future<dynamic> handleEvent(String eventId, Map<String, dynamic> data) {
    sent.add(eventId);
    return super.handleEvent(eventId, data);
  }
}
