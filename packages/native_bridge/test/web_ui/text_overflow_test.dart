@TestOn('browser')
/// Text that does not fit, in a real browser: the CSS that cuts it off.
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

  web.HTMLElement text() => root.querySelector('#line') as web.HTMLElement;

  String styleOf(String property) =>
      web.window.getComputedStyle(text()).getPropertyValue(property);

  Future<void> show({int? maxLines, String? overflow}) => renderer.render(
        UIBuilder.text(
          'A line long enough that it has to be cut off somewhere',
          id: 'line',
          maxLines: maxLines,
          overflow: overflow,
        ),
      );

  test('text with no cap wraps as far as it likes', () async {
    await show();

    expect(styleOf('text-overflow'), 'clip');
    expect(text().style.getPropertyValue('-webkit-line-clamp'), '');
  });

  test('one line is nowrap and an ellipsis', () async {
    await show(maxLines: 1, overflow: 'ellipsis');

    expect(styleOf('white-space'), 'nowrap');
    expect(styleOf('overflow-x'), 'hidden');
    expect(styleOf('text-overflow'), 'ellipsis');
  });

  test('more than one line is a clamp, and is really that tall', () async {
    // The mechanism (a clamp) and the effect (three lines of a text that
    // would otherwise take many more), since browsers disagree about how the
    // property is spelled but not about what it does.
    root.style.setProperty('width', '120px');
    await show(maxLines: 3, overflow: 'ellipsis');
    final clamped = text().getBoundingClientRect().height;

    await renderer.render(
      UIBuilder.text(
        'A line long enough that it has to be cut off somewhere',
        id: 'line',
      ),
    );
    final whole = text().getBoundingClientRect().height;

    expect(clamped, lessThan(whole));
    expect(clamped / (whole / 5), closeTo(3, 1));
  });

  test('clipping cuts without the ellipsis', () async {
    await show(maxLines: 1, overflow: 'clip');

    expect(styleOf('text-overflow'), 'clip');
    expect(styleOf('white-space'), 'nowrap');
  });

  test('a cap with no overflow still ends in an ellipsis', () async {
    // Flutter's default for a capped Text, and the one an app means.
    await show(maxLines: 2);

    expect(text().style.getPropertyValue('-webkit-line-clamp'), '2');
  });
}
