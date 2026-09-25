@TestOn('vm')
/// The stylesheet half of a column's main-axis alignment.
///
/// The renderer only puts a class on the column; everything that moves is in
/// `web_shell/dnn.css`, so the shipped file is read here - the same split as
/// the floating label.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Comments first: a selector list that follows one would otherwise read as
  // part of the first selector.
  final css = File('web_shell/dnn.css')
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  /// Everything the stylesheet declares for [selector], across every rule that
  /// names it - a selector can appear in a list with others, which is how the
  /// three alignments share one `flex` declaration.
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

  test('each alignment becomes the flex property that does it', () {
    expect(declarationsFor('.dnn-column--main-center'),
        contains('justify-content: center'));
    expect(declarationsFor('.dnn-column--main-end'),
        contains('justify-content: flex-end'));
    expect(declarationsFor('.dnn-column--main-spaceBetween'),
        contains('justify-content: space-between'));
  });

  test('a column that distributes also grows, or it has nothing to give', () {
    // A column sizes to its content; justify-content over a column that hugs
    // its children moves nothing.
    for (final selector in [
      '.dnn-column--main-center',
      '.dnn-column--main-end',
      '.dnn-column--main-spaceBetween',
    ]) {
      expect(declarationsFor(selector), contains('flex: 1 1 auto'),
          reason: selector);
    }
  });
}
