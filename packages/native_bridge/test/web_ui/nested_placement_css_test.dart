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

  test('a rail puts its leading above its destinations, the rest below', () {
    // One holder with no box of its own, so each child is the rail's item.
    expect(dnn('.dnn-bottomnav__slots'), contains('display: contents'));
    expect(dnn('.dnn-bottomnav--rail > .dnn-bottomnav__item'),
        contains('order: 1'));
    expect(dnn('.dnn-bottomnav__slots > *'), contains('order: 2'));
    expect(
      dnn('.dnn-bottomnav--leading > .dnn-bottomnav__slots > :first-child'),
      contains('order: 0'),
    );
    // Flutter's own example of a leading is a floating button, which on its
    // own is fixed to the window's corner.
    expect(dnn('.dnn-bottomnav__slots > .dnn-fab'),
        allOf(contains('position: relative'), contains('inset: auto')));
  });

  test('an extended rail is wide, each label beside its icon', () {
    expect(dnn('.dnn-bottomnav--rail.dnn-bottomnav--extended'),
        contains('width: 256px'));
    expect(dnn('.dnn-bottomnav--extended > .dnn-bottomnav__item'),
        contains('flex-direction: row'));
  });

  test('a dropdown in a row is as wide as its choices, not the row', () {
    final inRow = dnn('.dnn-row > .dnn-dropdown');
    expect(inRow, contains('width: auto'));
    expect(inRow, contains('flex: 0 0 auto'));
  });
}
