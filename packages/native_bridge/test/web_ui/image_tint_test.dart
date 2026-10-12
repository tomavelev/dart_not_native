@TestOn('browser')
/// Browser test for a tinted image: the picture's shape, filled with one
/// colour.
///
/// Run with: flutter test --platform chrome test/web_ui/image_tint_test.dart
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

/// A 2x2 picture: opaque black on the left, clear on the right.
const _halves =
    'data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 '
    'width=%2220%22 height=%2220%22><rect width=%2210%22 height=%2220%22/></svg>';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
  });
  tearDown(() => root.remove());

  web.HTMLImageElement image() =>
      root.querySelector('img')! as web.HTMLImageElement;

  test('a tint masks a fill of the colour with the picture', () async {
    await renderer.render(
      UIBuilder.image(
        src: _halves,
        alt: 'half',
        width: 20,
        height: 20,
        fit: 'contain',
        color: '#ff0000',
      ),
    );

    final style = web.window.getComputedStyle(image());
    expect(style.backgroundColor, 'rgb(255, 0, 0)');
    expect(style.getPropertyValue('mask-image'), contains('data:image/svg+xml'));
    expect(style.getPropertyValue('mask-size'), 'contain');
    expect(style.getPropertyValue('mask-repeat'), 'no-repeat');
    expect(style.objectPosition, startsWith('-100000px'));
    expect(image().getBoundingClientRect().width, 20, reason: 'still its size');
  });

  test('an image with no tint is left as it is', () async {
    await renderer.render(
      UIBuilder.image(src: _halves, alt: 'half', width: 20, height: 20),
    );

    final style = web.window.getComputedStyle(image());
    expect(style.getPropertyValue('mask-image'), 'none');
    expect(style.backgroundColor, 'rgba(0, 0, 0, 0)');
  });

  test('a tinted image with a fallback is tinted too', () async {
    await renderer.render(
      UIBuilder.image(
        src: _halves,
        alt: 'half',
        color: '#00ff00',
        fallback: UIBuilder.text('?'),
      ),
    );

    expect(
      web.window.getComputedStyle(image()).backgroundColor,
      'rgb(0, 255, 0)',
    );
  });
}
