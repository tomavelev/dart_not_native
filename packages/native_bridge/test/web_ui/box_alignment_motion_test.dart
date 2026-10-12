@TestOn('browser')
/// Browser test for a box that animates being given another alignment: the
/// child slides to its new place.
///
/// Run with: flutter test --platform chrome test/web_ui/box_alignment_motion_test.dart
library;

import 'dart:js_interop';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;

  setUp(() => root = mountRoot());
  tearDown(() => root.remove());

  WidgetNode box(List<double> alignment, {int? animateMs = 400}) =>
      UIBuilder.box(
        width: 200,
        height: 100,
        alignment: alignment,
        animateMs: animateMs,
        child: UIBuilder.text('child', id: 'child'),
      );

  // The stylesheet is what makes a box a grid, and the tests run without it.
  void asGrid() =>
      (root.querySelector('[data-type="Box"]')! as web.HTMLElement)
          .style
          .display = 'grid';

  int running() => web.document
      .getElementById('child')!
      .getAnimations()
      .toDart
      .length;

  test('a new alignment slides the child from where it was', () async {
    final renderer = WebUIRenderer(root: root);
    await renderer.render(box([-1, -1]));
    asGrid();
    final before = web.document.getElementById('child')!.getBoundingClientRect();
    await renderer.render(box([1, 1]));

    expect(running(), 1);
    final start = web.document.getElementById('child')!.getBoundingClientRect();
    expect(start.left, closeTo(before.left, 8), reason: 'it starts where it was');

    await settle(600);
    final end = web.document.getElementById('child')!.getBoundingClientRect();
    expect(end.left, greaterThan(before.left + 50));
    expect(running(), 0);
  });

  test('the same alignment moves nothing', () async {
    final renderer = WebUIRenderer(root: root);
    await renderer.render(box([1, 1]));
    asGrid();
    await renderer.render(box([1, 1]));

    expect(running(), 0);
  });

  test('a box that does not animate jumps', () async {
    final renderer = WebUIRenderer(root: root);
    await renderer.render(box([-1, -1], animateMs: null));
    asGrid();
    await renderer.render(box([1, 1], animateMs: null));

    expect(running(), 0);
  });

  test('with animations off it jumps', () async {
    final renderer = WebUIRenderer(root: root, animations: false);
    await renderer.render(box([-1, -1]));
    asGrid();
    await renderer.render(box([1, 1]));

    expect(running(), 0);
  });
}
