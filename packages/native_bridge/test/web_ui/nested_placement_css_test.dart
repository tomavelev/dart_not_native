@TestOn('vm')
/// Two places where what a node is *in* decides how it is laid out, which
/// only the stylesheet can say: a floating button a nested scaffold pins, and
/// a dropdown that is a list row's trailing.
library;

import 'package:flutter_test/flutter_test.dart';

import 'free_form_css_test.dart' show declarationsIn;

void main() {
  final dnn = declarationsIn('web_shell/dnn.css');

  test('a floating button inside a Positioned is placed by it', () {
    // On its own the button is fixed to the window's corner, which puts a
    // nested scaffold's button on top of the outer scaffold's bottom bar.
    expect(dnn('.dnn-fab'), contains('position: fixed'));
    expect(dnn('.dnn-positioned > .dnn-fab'), contains('position: static'));
  });

  test('a snackbar sits above the bottom bar and the floating button', () {
    // Fixed to the window's bottom edge on its own, which is where both are.
    expect(dnn('.dnn-snackbar'), contains('bottom: 16px'));
    expect(
      dnn('.dnn-overlay:has(> .dnn-scaffold > .dnn-bottombar) > .dnn-snackbar'),
      contains('bottom: calc(8px + var(--dnn-bottombar-height, 0px))'),
    );
    expect(
      dnn('.dnn-overlay:has(> .dnn-scaffold > .dnn-fab) > .dnn-snackbar'),
      contains('bottom: 88px'),
    );
    expect(
      dnn(
        '.dnn-overlay:has(> .dnn-scaffold > .dnn-bottombar)'
        ':has(> .dnn-scaffold > .dnn-fab) > .dnn-snackbar',
      ),
      contains('bottom: calc(88px + var(--dnn-bottombar-height, 0px))'),
    );
  });

  test('a rail with more destinations than fit scrolls', () {
    expect(dnn('.dnn-bottomnav--rail'), contains('overflow-y: auto'));
  });

  test('a dropdown in a row is as wide as its choices, not the row', () {
    final inRow = dnn('.dnn-row > .dnn-dropdown');
    expect(inRow, contains('width: auto'));
    expect(inRow, contains('flex: 0 0 auto'));
  });
}
