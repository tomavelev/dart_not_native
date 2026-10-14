@TestOn('browser')
/// Browser test for a curve said as a cubic (`cubic(a,b,c,d)`).
///
/// Run with: flutter test --platform chrome test/web_ui/cubic_curve_test.dart
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

  Future<String> transition(String curve) async {
    final renderer = WebUIRenderer(root: root);
    await renderer.render(
      UIBuilder.box(width: 10, height: 10, animateMs: 200, curve: curve, id: 'b'),
    );
    return (root.querySelector('#b')! as web.HTMLElement).style.transition;
  }

  test('a cubic moves along the same cubic-bezier', () async {
    expect(
      await transition('cubic(0.4,0.0,0.2,1.0)'),
      contains('cubic-bezier(0.4, 0, 0.2, 1)'),
    );
  });

  test('a named one is still its CSS name', () async {
    expect(await transition('easeOut'), contains('ease-out'));
  });
}
