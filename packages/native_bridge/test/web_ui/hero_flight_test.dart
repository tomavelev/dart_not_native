@TestOn('browser')
/// Browser test for a hero: a box with the same name on the page left and on
/// the page arrived at flies from the one place to the other.
///
/// Run with: flutter test --platform chrome test/web_ui/hero_flight_test.dart
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
    renderer = WebUIRenderer(root: root);
  });
  tearDown(() {
    root.remove();
    final left = web.document.querySelectorAll(
      '.dnn-hero-flight, .dnn-page-leaving',
    );
    for (var i = 0; i < left.length; i++) {
      (left.item(i) as web.Element).remove();
    }
  });

  /// A page with one hero, [size] square, [down] from the top.
  WidgetNode page(String label, {required double size, required double down}) =>
      UIBuilder.column(
        children: [
          UIBuilder.sizedBox(height: down),
          UIBuilder.box(
            hero: 'picture',
            width: size,
            height: size,
            color: '#3366ff',
            id: 'hero-$label',
            child: UIBuilder.text(label),
          ),
        ],
      );

  WidgetNode pushed(WidgetNode tree, {int ms = 400}) =>
      UIBuilder.withPageTransition(tree, {'kind': 'push', 'ms': ms});

  web.HTMLElement? flight() =>
      web.document.querySelector('.dnn-hero-flight') as web.HTMLElement?;

  web.HTMLElement hero() =>
      root.querySelector('[data-hero="picture"]')! as web.HTMLElement;

  test('a box with a hero\'s name says so in the DOM', () async {
    await renderer.render(page('one', size: 40, down: 0));
    expect(hero().getAttribute('data-hero'), 'picture');
  });

  test('the hero flies from where the old one stood', () async {
    await renderer.render(page('one', size: 40, down: 0));
    final from = hero().getBoundingClientRect();
    await renderer.render(pushed(page('two', size: 120, down: 200)));

    final flying = flight();
    expect(flying, isNotNull);
    // Frozen at its first instant, the copy covers the old hero's place.
    final run = flying!.getAnimations().toDart.single..pause();
    run.currentTime = 0.toJS;
    final start = flying.getBoundingClientRect();
    expect(start.left, closeTo(from.left, 0.5));
    expect(start.top, closeTo(from.top, 0.5));
    expect(start.width, closeTo(40, 0.5));
    expect(start.height, closeTo(40, 0.5));
    expect(flying.textContent, contains('two'), reason: 'the new one flies');
  });

  test('neither hero is seen while the copy is in the air', () async {
    await renderer.render(page('one', size: 40, down: 0));
    await renderer.render(pushed(page('two', size: 120, down: 200)));

    expect(hero().style.visibility, 'hidden');
    final old =
        web.document.querySelector('.dnn-page-leaving [data-hero]')!
            as web.HTMLElement;
    expect(old.style.visibility, 'hidden');
  });

  test('it lands where the new hero stands, and the hero shows', () async {
    await renderer.render(page('one', size: 40, down: 0));
    await renderer.render(pushed(page('two', size: 120, down: 200), ms: 60));
    final flying = flight()!;
    // At rest the copy is the size and place of the hero itself.
    final run = flying.getAnimations().toDart.single;
    await run.finished.toDart;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(flight(), isNull);
    expect(hero().style.visibility, isNot('hidden'));
    expect(hero().getBoundingClientRect().width, closeTo(120, 0.5));
  });

  test('a hero with no counterpart does not fly', () async {
    await renderer.render(UIBuilder.column(children: [UIBuilder.text('plain')]));
    await renderer.render(pushed(page('two', size: 120, down: 200)));

    expect(flight(), isNull);
    expect(hero().style.visibility, isNot('hidden'));
  });

  test('with no page transition nothing flies', () async {
    await renderer.render(page('one', size: 40, down: 0));
    await renderer.render(page('two', size: 120, down: 200));

    expect(flight(), isNull);
  });

  test('the copy has no id and no name of its own', () async {
    await renderer.render(page('one', size: 40, down: 0));
    await renderer.render(pushed(page('two', size: 120, down: 200)));

    expect(flight()!.id, isEmpty);
    expect(flight()!.hasAttribute('data-hero'), isFalse);
    expect(web.document.querySelectorAll('#hero-two').length, 1);
  });
}
