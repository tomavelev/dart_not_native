@TestOn('browser')
/// A box that moves, in a real browser: the transition the CSS carries, the
/// element that has to survive for there to be anything to move from, and the
/// curve names mapped onto the ones CSS knows.
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

  web.HTMLElement box() =>
      root.querySelector('[data-type="AnimatedContainer"]') as web.HTMLElement;

  Future<void> show({
    double? width,
    double? height,
    String? color,
    int ms = 300,
    String curve = 'easeInOut',
  }) =>
      renderer.render(
        UIBuilder.animatedContainer(
          width: width,
          height: height,
          color: color,
          duration: Duration(milliseconds: ms),
          curve: curve,
          child: UIBuilder.text('Tap', id: 'label'),
        ),
      );

  test('carries the size and colour it is at', () async {
    await show(width: 80, height: 64, color: '#9e9e9e');

    expect(box().style.getPropertyValue('width'), '80px');
    expect(box().style.getPropertyValue('height'), '64px');
    expect(
      box().style.getPropertyValue('background-color'),
      anyOf('rgb(158, 158, 158)', '#9e9e9e'),
    );
  });

  test('names every property it animates in the transition', () async {
    await show(width: 80, curve: 'easeOut');

    final transition = box().style.getPropertyValue('transition');
    expect(transition, contains('width 300ms ease-out'));
    expect(transition, contains('height 300ms ease-out'));
    expect(transition, contains('background-color 300ms ease-out'));
  });

  test('a change is applied to the same element, not a new one', () async {
    await show(width: 80, color: '#9e9e9e');
    final before = box();

    await show(width: 300, color: '#2196f3');

    // The whole point: a replaced element would already be at the new size
    // and there would be nothing to move from.
    expect(box(), same(before));
    expect(box().style.getPropertyValue('width'), '300px');
  });

  test('the child is kept through the move', () async {
    await show(width: 80);

    await show(width: 300);

    expect(box().querySelector('#label')?.textContent, 'Tap');
  });

  test('a dimension the tree stops stating stops being set', () async {
    await show(width: 80, height: 64);

    await show(height: 64);

    expect(box().style.getPropertyValue('width'), '');
  });

  test('each curve name reaches the CSS timing function for it', () async {
    for (final pair in const [
      ('linear', 'linear'),
      // `ease` is the CSS default, and the browser reads it back with the
      // timing function dropped - the transition is still there.
      ('ease', ''),
      ('easeIn', 'ease-in'),
      ('easeOut', 'ease-out'),
      ('easeInOut', 'ease-in-out'),
    ]) {
      await show(width: 80, curve: pair.$1);

      expect(
        box().style.getPropertyValue('transition'),
        contains('width 300ms ${pair.$2}'.trimRight()),
        reason: pair.$1,
      );
    }
  });
}
