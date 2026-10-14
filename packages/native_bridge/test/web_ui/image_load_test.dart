@TestOn('browser')
/// Browser test for an image that asked how its load ended (`eventId`).
///
/// Run with: flutter test --platform chrome test/web_ui/image_load_test.dart
library;

import 'dart:async';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

const _picture =
    'data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 '
    'width=%2220%22 height=%2220%22><rect width=%2210%22 height=%2220%22/></svg>';

/// Nothing a browser can draw.
const _broken = 'data:image/png;base64,AAAA';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<String> said;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    said = [];
    renderer.onEvent('img', (data) => said.add(data['state'] as String));
  });
  tearDown(() => root.remove());

  /// Long enough for a data URI to decode, or to fail to.
  Future<void> settle() async {
    for (var i = 0; i < 40 && said.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  test('a picture that loads says so, once', () async {
    await renderer.render(
      UIBuilder.image(src: _picture, alt: 'a', eventId: 'img'),
    );
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(said, ['loaded']);
  });

  test('one that cannot be drawn says it failed', () async {
    await renderer.render(
      UIBuilder.image(src: _broken, alt: 'a', eventId: 'img'),
    );
    await settle();

    expect(said, ['failed']);
  });

  test('with a stand-in: it shows until the picture does, then says', () async {
    await renderer.render(
      UIBuilder.image(
        src: _picture,
        alt: 'a',
        eventId: 'img',
        fallback: UIBuilder.text('waiting'),
      ),
    );
    await settle();

    expect(said, ['loaded']);
    final image = root.querySelector('img')! as web.HTMLElement;
    final standIn =
        root.querySelector('.dnn-image-frame__fallback')! as web.HTMLElement;
    expect(image.hidden, isFalse);
    expect(standIn.hidden, isTrue);
  });

  test('with a stand-in: a failure leaves it showing, and says', () async {
    await renderer.render(
      UIBuilder.image(
        src: _broken,
        alt: 'a',
        eventId: 'img',
        fallback: UIBuilder.text('no picture'),
      ),
    );
    await settle();

    expect(said, ['failed']);
    final standIn =
        root.querySelector('.dnn-image-frame__fallback')! as web.HTMLElement;
    expect(standIn.hidden, isFalse);
    expect(standIn.textContent, contains('no picture'));
  });

  test('an image that did not ask is not answered', () async {
    var heard = 0;
    renderer.onEvent('other', (_) => heard++);
    await renderer.render(UIBuilder.image(src: _picture, alt: 'a'));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(said, isEmpty);
    expect(heard, 0);
  });
}
