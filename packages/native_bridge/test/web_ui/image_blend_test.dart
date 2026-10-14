@TestOn('browser')
/// Browser test for an image tint's blend mode (`blend`).
///
/// Run with: flutter test --platform chrome test/web_ui/image_blend_test.dart
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

const _picture = 'https://example.com/a.png';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
  });
  tearDown(() => root.remove());

  Future<web.CSSStyleDeclaration> style(String? blend) async {
    await renderer.render(
      UIBuilder.image(src: _picture, alt: 'a', color: '#2196F3', blend: blend),
    );
    return (root.querySelector('img')! as web.HTMLElement).style;
  }

  test('a tint with no mode is the picture\'s shape in the colour', () async {
    final s = await style(null);
    expect(s.getPropertyValue('mask-image'), contains('a.png'));
    expect(s.getPropertyValue('background-image'), isEmpty);
    expect(s.getPropertyValue('background-color'), isNotEmpty);
  });

  test('multiply lays the colour over the picture, blended', () async {
    final s = await style('multiply');
    expect(s.getPropertyValue('background-image'), contains('a.png'));
    expect(s.getPropertyValue('background-blend-mode'), 'multiply, normal');
    // Kept to the picture's shape.
    expect(s.getPropertyValue('mask-image'), contains('a.png'));
  });

  test('the two-word modes take their CSS names', () async {
    expect(
      (await style('colorDodge')).getPropertyValue('background-blend-mode'),
      'color-dodge, normal',
    );
    expect(
      (await style('modulate')).getPropertyValue('background-blend-mode'),
      'multiply, normal',
    );
  });

  test('a mode that keeps the picture as it was leaves it untinted', () async {
    final s = await style('dst');
    expect(s.getPropertyValue('mask-image'), isEmpty);
    expect(s.getPropertyValue('object-position'), isEmpty);
  });

  test('srcOut colours outside the picture\'s shape', () async {
    final s = await style('srcOut');
    expect(s.getPropertyValue('mask-composite'), 'exclude');
    expect(s.getPropertyValue('background-color'), isNotEmpty);
  });
}
