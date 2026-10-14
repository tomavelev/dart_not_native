@TestOn('browser')
/// Browser test for a box that moves to the size its child comes to
/// (`animateSize`).
///
/// Run with: flutter test --platform chrome test/web_ui/animate_size_test.dart
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;

  setUp(() => root = mountRoot());
  tearDown(() => root.remove());

  WidgetNode sized(double inner, {bool animate = true}) => UIBuilder.box(
    animateSize: animate,
    animateMs: 300,
    clip: true,
    id: 'outer',
    child: UIBuilder.box(width: 50, height: inner),
  );

  double height() =>
      (root.querySelector('#outer')! as web.HTMLElement).offsetHeight
          .toDouble();

  Future<void> wait(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('a box whose child grows moves to the new size', () async {
    final renderer = WebUIRenderer(root: root);
    await renderer.render(sized(20));
    expect(height(), 20);

    await renderer.render(sized(120));
    await wait(80);
    final between = height();
    expect(between, greaterThan(20));
    expect(between, lessThan(120));

    await wait(320);
    expect(height(), 120);
  });

  test('without animateSize it is there at once', () async {
    final renderer = WebUIRenderer(root: root);
    await renderer.render(sized(20, animate: false));
    await renderer.render(sized(120, animate: false));
    expect(height(), 120);
  });

  test('with no animations, at once too', () async {
    final renderer = WebUIRenderer(root: root, animations: false);
    await renderer.render(sized(20));
    await renderer.render(sized(120));
    expect(height(), 120);
  });
}
