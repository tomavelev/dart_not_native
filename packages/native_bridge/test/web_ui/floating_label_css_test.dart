@TestOn('vm')
/// The other half of the floating label: the stylesheet that moves it.
///
/// The renderer only puts a class on the field and keeps a placeholder there
/// (`floating_label_test.dart`); everything visible is in `web_shell/dnn.css`.
/// Delete those rules and the label would sit still with every browser test
/// passing, so the shipped stylesheet is read here.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final css = File('web_shell/dnn.css').readAsStringSync();

  /// The body of the rule whose selector list contains [selector].
  String ruleFor(String selector) {
    for (final rule in css.split('}')) {
      final brace = rule.indexOf('{');
      if (brace < 0) continue;
      if (!rule.substring(0, brace).contains(selector)) continue;
      return rule.substring(brace + 1);
    }
    fail('no rule selects "$selector" in web_shell/dnn.css');
  }

  test('the label is taken out of the flow, inside the field', () {
    expect(ruleFor('.dnn-textfield--floating .dnn-textfield__label'),
        contains('position: absolute'));
    // Over the input, so a click on the label still reaches the field.
    expect(ruleFor('.dnn-textfield--floating .dnn-textfield__label'),
        contains('pointer-events: none'));
  });

  test('focus and a value are what raise it', () {
    final raise = ruleFor(
      '.dnn-textfield--floating:has(.dnn-textfield__input:not(:placeholder-shown))',
    );
    expect(raise, contains('transform:'));
    // Both states raise it: the same rule lists :focus-within.
    expect(
      css,
      contains('.dnn-textfield--floating:focus-within .dnn-textfield__label,'),
    );
    // And it moves rather than jumps.
    expect(ruleFor('.dnn-textfield--floating .dnn-textfield__label'),
        contains('transition:'));
  });

  test('the hint waits until the label is out of the way', () {
    // Both sit in the same place, so the placeholder is invisible until the
    // field has focus - by which time the label has risen.
    expect(ruleFor('.dnn-textfield--floating .dnn-textfield__input::placeholder'),
        contains('transparent'));
    expect(
      css,
      contains('.dnn-textfield--floating .dnn-textfield__input:focus::placeholder'),
    );
  });

  test('an invalid field colours its label too', () {
    expect(
      ruleFor('.dnn-textfield--error.dnn-textfield--floating'),
      contains('--dnn-error'),
    );
  });
}
