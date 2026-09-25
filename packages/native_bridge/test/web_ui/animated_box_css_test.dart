@TestOn('vm')
/// The stylesheet half of an animated box.
///
/// The renderer writes the size, the colour and the transition inline; where
/// the child sits is the stylesheet's, so the shipped file is read here - the
/// same split as the floating label and a column's alignment.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final css = File('web_shell/dnn.css')
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  String declarationsFor(String selector) {
    final found = StringBuffer();
    for (final rule in css.split('}')) {
      final brace = rule.indexOf('{');
      if (brace < 0) continue;
      final selectors =
          rule.substring(0, brace).split(',').map((s) => s.trim()).toSet();
      if (!selectors.contains(selector)) continue;
      found.writeln(rule.substring(brace + 1));
    }
    if (found.isEmpty) fail('nothing selects "$selector" in web_shell/dnn.css');
    return found.toString();
  }

  test('the child is centred, as it is on the other three renderers', () {
    final box = declarationsFor('.dnn-animated-box');

    expect(box, contains('display: flex'));
    expect(box, contains('align-items: center'));
    expect(box, contains('justify-content: center'));
  });

  test('a stated size is the box, not the box plus its padding', () {
    // border-box, because the width the tree asks for is the width the app
    // means - and because the other three renderers measure it that way.
    expect(declarationsFor('.dnn-animated-box'), contains('border-box'));
  });
}
