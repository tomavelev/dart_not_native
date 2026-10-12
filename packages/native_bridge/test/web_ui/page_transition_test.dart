@TestOn('browser')
/// Browser tests for a page transition: the old page is kept as a picture
/// over the new one for as long as the transition takes.
///
/// Run with: flutter test --platform chrome test/web_ui/page_transition_test.dart
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
    renderer = WebUIRenderer(root: root);
  });

  tearDown(() {
    root.remove();
    web.document.querySelector('.dnn-page-leaving')?.remove();
  });

  WidgetNode page(String name, {String? kind, int ms = 120}) =>
      UIBuilder.withPageTransition(
        UIBuilder.scaffold(body: UIBuilder.text(name, id: 'name')),
        kind == null ? null : {'kind': kind, 'ms': ms},
      );

  web.Element? leaving() => web.document.querySelector('.dnn-page-leaving');

  test('a page that is simply another tree is swapped', () async {
    await renderer.render(page('one'));
    await renderer.render(page('two'));

    expect(leaving(), isNull);
  });

  test('the first page has nothing to come from', () async {
    await renderer.render(page('one', kind: 'push'));

    expect(leaving(), isNull);
  });

  test('a pushed page keeps the old one over it, then lets it go', () async {
    await renderer.render(page('one'));
    await renderer.render(page('two', kind: 'push'));

    final old = leaving()!;
    expect(old.textContent, contains('one'));
    expect(root.textContent, contains('two'));
    expect(root.textContent, isNot(contains('one')));
    expect(old.querySelector('[id]'), isNull, reason: 'ids stay unique');
    expect(web.document.getElementById('name')!.textContent, 'two');
    expect(
      web.window.getComputedStyle(old).pointerEvents,
      'none',
      reason: 'the picture takes no touches',
    );

    await settle(300);
    expect(leaving(), isNull);
  });

  test('the picture sits where the root is', () async {
    await renderer.render(page('one'));
    await renderer.render(page('two', kind: 'fade', ms: 2000));

    final at = leaving()!.getBoundingClientRect();
    final box = root.getBoundingClientRect();
    expect(at.left, box.left);
    expect(at.top, box.top);
    expect(at.width, box.width);
  });

  test('the prop is not left on the tree the next patch starts from', () async {
    await renderer.render(page('one'));
    await renderer.render(page('two', kind: 'pop'));
    await settle(300);
    await renderer.render(page('two'));

    expect(leaving(), isNull);
    expect(root.textContent, contains('two'));
  });

  test('a transition said on a tree that was never drawn is still shown',
      () async {
    await renderer.render(page('one'));
    // Two trees in one batch: only the second is drawn.
    final first = renderer.render(page('two', kind: 'push'));
    final second = renderer.render(page('two'));
    await Future.wait([first, second]);

    expect(leaving(), isNotNull);
    expect(leaving()!.textContent, contains('one'));
    await settle(300);
  });

  test('with animations off, the page is swapped', () async {
    root.remove();
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    await renderer.render(page('one'));
    await renderer.render(page('two', kind: 'push'));

    expect(leaving(), isNull);
  });
}
