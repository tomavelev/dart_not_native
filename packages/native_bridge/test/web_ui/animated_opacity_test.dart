@TestOn('browser')
/// Fading in a real browser: the transition, and the element that has to
/// survive for there to be anything to transition from.
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

  web.HTMLElement fade() =>
      root.querySelector('[data-type="AnimatedOpacity"]') as web.HTMLElement;

  Future<void> show(double opacity, {int ms = 300}) => renderer.render(
        UIBuilder.animatedOpacity(
          opacity: opacity,
          duration: Duration(milliseconds: ms),
          child: UIBuilder.text('Saved', id: 'label'),
        ),
      );

  test('carries the opacity and the transition that will move it', () async {
    await show(0.5, ms: 300);

    expect(fade().style.getPropertyValue('opacity'), '0.5');
    // The browser drops the timing function when it is the default one.
    expect(
      fade().style.getPropertyValue('transition'),
      startsWith('opacity 300ms'),
    );
  });

  test('a change is applied to the same element, not a new one', () async {
    await show(0);
    final before = fade();

    await show(1);

    // The whole point: a replaced element would start at the new opacity and
    // there would be nothing to fade from.
    expect(fade(), same(before));
    expect(fade().style.getPropertyValue('opacity'), '1');
  });

  test('the child is kept through the fade', () async {
    await show(0);

    await show(1);

    expect(fade().querySelector('#label')?.textContent, 'Saved');
  });
}
