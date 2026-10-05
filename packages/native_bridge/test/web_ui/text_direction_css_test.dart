@TestOn('vm')
/// The stylesheet half of a right-to-left screen.
///
/// The renderer only puts `dir="rtl"` on its root; what that turns is decided
/// by `web_shell/dnn.css`, where a rule that names a side stays on that side
/// and one that names the start or the end follows the direction. So the
/// shipped file is read here - the same split as the column alignment.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/direction_rules.dart';

void main() {
  final css = File('web_shell/dnn.css')
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  /// Everything the stylesheet declares for [selector], across every rule
  /// that names it.
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

  /// The declarations of the first rule whose selector list contains
  /// [selector] as written - for a selector with a comma of its own, an
  /// `:is(a, b)`, which [declarationsFor] would cut in two.
  String blockOf(String selector) {
    final at = css.indexOf(selector);
    if (at < 0) fail('nothing selects "$selector" in web_shell/dnn.css');
    final open = css.indexOf('{', at);
    return css.substring(open + 1, css.indexOf('}', open));
  }

  test('every rule the browser tests borrow is in the shipped stylesheet', () {
    for (final (selector, declaration) in directionRules) {
      expect(declarationsFor(selector), contains(declaration), reason: selector);
    }
  });

  group('what means the start or the end says so', () {
    // Each of these named a side once, and so stayed put in Arabic.
    const logical = {
      '.dnn-appbar__actions': 'margin-inline-start: auto',
      '.dnn-appbar__leading': 'margin-inline: -8px 8px',
      '.dnn-fab': 'inset-inline-end: 24px',
      '.dnn-fab.dnn-fab--extended': 'padding-inline: 16px 20px',
      '.dnn-dropdown__field::after': 'inset-inline-end: 14px',
      '.dnn-dropdown select.dnn-dropdown__select': 'padding-inline-end: 36px',
      '.dnn-textfield--floating .dnn-textfield__label':
          'inset-inline-start: 8px',
      '.dnn-textfield--prefix .dnn-textfield__box > input':
          'padding-inline-start: 40px',
      '.dnn-textfield--suffix .dnn-textfield__box > input':
          'padding-inline-end: 40px',
      '.dnn-switch__track::after': 'inset-inline-start: -2px',
      '.dnn-switch input:checked + .dnn-switch__track::after':
          'inset-inline-start: 18px',
      '.dnn-alert': 'border-inline-start: 4px solid currentColor',
      '.dnn-snackbar': 'padding-inline: 16px 8px',
      '.dnn-bottomnav--rail': 'border-inline-end: 1px solid var(--dnn-divider)',
    };

    logical.forEach((selector, declaration) {
      test(selector, () {
        final declared = declarationsFor(selector);
        expect(declared, contains(declaration));
        for (final physical in const [
          'margin-left',
          'margin-right',
          'padding-left',
          'padding-right',
          'border-left',
          'border-right',
        ]) {
          expect(declared, isNot(contains(physical)), reason: physical);
        }
      });
    });
  });

  // A glyph is set left to right whatever is around it, and a logical
  // property follows the element's own direction - so a rule on the glyph
  // itself would not turn. These name the side, twice.
  group('a rule on a glyph names the side again for rtl', () {
    test('a text field\'s prefix and suffix swap ends', () {
      expect(declarationsFor('.dnn-textfield__icon--prefix'),
          contains('left: 10px'));
      expect(declarationsFor('[dir="rtl"] .dnn-textfield__icon--prefix'),
          allOf(contains('left: auto'), contains('right: 10px')));
      expect(declarationsFor('[dir="rtl"] .dnn-textfield__icon--suffix'),
          allOf(contains('right: auto'), contains('left: 10px')));
      expect(declarationsFor('[dir="rtl"] button.dnn-textfield__icon--suffix'),
          contains('left: 4px'));
    });

    test('a button\'s icon keeps its gap on the label\'s side', () {
      expect(declarationsFor('[dir="rtl"] .dnn-button__icon.material-icons'),
          allOf(contains('margin-right: 0'), contains('margin-left: 8px')));
    });

    test('a floating label shrinks towards the corner it starts in', () {
      expect(
        declarationsFor(
          '[dir="rtl"] .dnn-textfield--floating .dnn-textfield__label',
        ),
        contains('transform-origin: right top'),
      );
    });
  });

  test('the back arrow, and only it, is turned round', () {
    expect(declarationsFor('[dir="rtl"] .dnn-appbar__leading--back'),
        contains('scaleX(-1)'));
    expect(css, isNot(contains('[dir="rtl"] .dnn-appbar__leading {')));
  });

  group('a row asked to fill', () {
    test('is as wide as it is allowed', () {
      expect(declarationsFor('.dnn-row--size-max'), contains('width: 100%'));
    });

    test('takes the padding or the box around it with it', () {
      // A percentage of a parent that hugs is the child's own width, so the
      // parent has to take the width it is offered for the row to have any.
      const selector =
          ':is(.dnn-padding, .dnn-box, .dnn-fade):has(> .dnn-row--size-max)';
      expect(blockOf(selector), contains('align-self: stretch'));
      expect(blockOf(selector), contains('justify-self: stretch'));
    });

    test('and an Expanded in a column around it', () {
      expect(
        blockOf(
          '.dnn-column > .dnn-expanded:has(> :is(.dnn-row--size-max, .dnn-fill-w))',
        ),
        contains('align-self: stretch'),
      );
    });
  });

  // Reported by two migrations: in a row that centres its children, an
  // Expanded holding a column asked to fill was as tall as the column's
  // content - and a column whose content is a share of its height has none.
  test('an Expanded in a row gives a max-size column the row\'s height', () {
    expect(
      declarationsFor('.dnn-row > .dnn-expanded:has(> .dnn-column--size-max)'),
      contains('align-self: stretch'),
    );
  });

  test('a disabled checkable control is drawn as one', () {
    expect(declarationsFor('.dnn-choice--disabled'), contains('opacity: 0.38'));
  });

  test('an image and its fallback share one cell', () {
    expect(declarationsFor('.dnn-image-frame'), contains('inline-grid'));
    expect(declarationsFor('.dnn-image-frame > *'), contains('grid-area: 1 / 1'));
  });
}
