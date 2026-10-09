@TestOn('vm')
/// The stylesheet half of the free-form nodes and the screen's frame.
///
/// The renderer puts classes on these and the shipped stylesheets do the
/// laying out, so the files are read here - the same split as the column
/// alignment and the floating label.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Everything [file] declares for [selector], across every rule naming it.
String Function(String selector) declarationsIn(String file) {
  // Comments first: a selector list that follows one would otherwise read as
  // part of the first selector.
  final css = File(file)
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return (selector) {
    final found = StringBuffer();
    for (final rule in css.split('}')) {
      final brace = rule.indexOf('{');
      if (brace < 0) continue;
      final selectors = rule
          .substring(0, brace)
          .split(',')
          .map((s) => s.trim().replaceAll(RegExp(r'\s+'), ' '))
          .toSet();
      if (!selectors.contains(selector)) continue;
      found.writeln(rule.substring(brace + 1));
    }
    if (found.isEmpty) fail('nothing selects "$selector" in $file');
    return found.toString();
  };
}

void main() {
  final dnn = declarationsIn('web_shell/dnn.css');
  const body =
      ':not(.dnn-appbar):not(.dnn-navbar):not(.dnn-fab):not(.dnn-bottombar)';

  group('a scaffold', () {
    test('a fixed one is exactly the viewport, and its body what is left',
        () {
      expect(dnn('.dnn-scaffold--fixed'),
          contains('height: var(--dnn-viewport-height, 100vh)'));
      expect(dnn('.dnn-scaffold--fixed'), contains('overflow: hidden'));
      // A basis of nothing and a floor of nothing: the body is given its
      // height rather than taking its content's, which is what an Expanded
      // or a Scroll inside it needs.
      expect(dnn('.dnn-scaffold--fixed > $body'), contains('flex: 1 1 0'));
      expect(dnn('.dnn-scaffold--fixed > $body'), contains('min-height: 0'));
    });

    test('the body is the child that is none of the furniture', () {
      // The bottom bar is furniture too, or it would grow like a body.
      expect(dnn('.dnn-scaffold > $body'), contains('flex: 1 1 auto'));
    });

    test('a body that scrolls itself is not clipped by the fixed scaffold',
        () {
      expect(
        dnn('.dnn-scaffold--fixed > $body:not(.dnn-scroll):not(.dnn-lazylist)'),
        contains('overflow: hidden'),
      );
    });

    test('the bottom bar stays at the bottom, and the button clears it', () {
      expect(dnn('.dnn-bottombar'), contains('position: sticky'));
      expect(dnn('.dnn-bottombar'), contains('bottom: 0'));
      expect(dnn('.dnn-scaffold:has(> .dnn-bottombar) > .dnn-fab'),
          contains('var(--dnn-bottombar-height, 0px)'));
    });

    test('it keeps clear of the safe area unless told to run under it', () {
      expect(dnn('.dnn-scaffold:not(.dnn-scaffold--edge)'),
          contains('env(safe-area-inset-top, 0px)'));
    });
  });

  group('an app bar', () {
    test('the actions sit at the far end', () {
      expect(dnn('.dnn-appbar__actions'), contains('margin-inline-start: auto'));
    });

    test('a title node takes the room the title had', () {
      expect(
        dnn('.dnn-appbar--title-node .dnn-appbar__actions > :first-child'),
        contains('flex: 1 1 auto'),
      );
    });

    test('a centred title is centred on the bar', () {
      expect(dnn('.dnn-appbar--center .dnn-appbar__title'),
          contains('text-align: center'));
      expect(dnn('.dnn-appbar--center .dnn-appbar__title'),
          contains('position: absolute'));
    });

    test('what is in the bar is drawn in the bar\'s colour', () {
      expect(dnn('.dnn-appbar .dnn-icon-button'), contains('color: inherit'));
    });
  });

  group('layout', () {
    test('the new alignments are the flex properties that do them', () {
      expect(dnn('.dnn-column--main-spaceAround'),
          contains('justify-content: space-around'));
      expect(dnn('.dnn-column--main-spaceEvenly'),
          contains('justify-content: space-evenly'));
      expect(dnn('.dnn-row--spaceAround'),
          contains('justify-content: space-around'));
      expect(dnn('.dnn-row--spaceEvenly'),
          contains('justify-content: space-evenly'));
      expect(dnn('.dnn-row--cross-start'), contains('align-items: flex-start'));
      expect(dnn('.dnn-row--cross-end'), contains('align-items: flex-end'));
      expect(dnn('.dnn-row--cross-stretch'), contains('align-items: stretch'));
    });

    test('a column fills when it is max and hugs when it is min', () {
      expect(dnn('.dnn-column--size-max'), contains('flex: 1 1 auto'));
      expect(dnn('.dnn-column--main-spaceEvenly'), contains('flex: 1 1 auto'));
      // Two classes, so it outranks the growing an alignment asks for.
      expect(dnn('.dnn-column.dnn-column--size-min'), contains('flex: 0 0 auto'));
    });

    test('a row is as wide as its children, or as wide as it is allowed', () {
      expect(dnn('.dnn-row--size-min'), contains('width: fit-content'));
      expect(dnn('.dnn-row--size-max'), contains('width: 100%'));
    });

    test('a loose expanded does not stretch its child', () {
      expect(dnn('.dnn-expanded--loose > *'), contains('flex: 0 1 auto'));
      expect(dnn('.dnn-expanded--loose'), contains('align-items: flex-start'));
    });
  });

  group('free-form composition', () {
    test('a box is one cell its child fills', () {
      expect(dnn('.dnn-box'), contains('display: grid'));
      expect(dnn('.dnn-box'), contains('minmax(0, 1fr) / minmax(0, 1fr)'));
    });

    test('expand means the width across a column and a share along a row',
        () {
      expect(dnn('.dnn-fill-w'), contains('calc(100% - var(--dnn-mx, 0px))'));
      expect(dnn('.dnn-fill-h'), contains('calc(100% - var(--dnn-my, 0px))'));
      expect(dnn('.dnn-row > .dnn-fill-w'), contains('flex: 1 1 0'));
      expect(dnn('.dnn-column > .dnn-fill-h'), contains('flex: 1 1 0'));
    });

    test('a pannable box is not scrolled by the browser', () {
      expect(dnn('.dnn-box--pan'), contains('touch-action: none'));
    });

    test('a stack\'s children share one cell and paint in tree order', () {
      expect(dnn('.dnn-stack'), contains('display: grid'));
      expect(dnn('.dnn-stack'), contains('overflow: hidden'));
      expect(dnn('.dnn-stack > *'), contains('grid-area: 1 / 1'));
      // Positioned, every one: otherwise a pinned child would paint over a
      // later child that is not.
      expect(dnn('.dnn-stack > *'), contains('position: relative'));
    });

    test('a pinned child leaves the cell; outside a stack it is its child',
        () {
      expect(dnn('.dnn-stack > .dnn-positioned'), contains('position: absolute'));
      expect(dnn('.dnn-positioned'), contains('display: contents'));
    });

    test('a scroller fills its parent and scrolls along its axis', () {
      expect(dnn('.dnn-scroll'), contains('flex: 1 1 0'));
      expect(dnn('.dnn-scroll'), contains('min-height: 0'));
      expect(dnn('.dnn-scroll'), contains('overflow-y: auto'));
      expect(dnn('.dnn-scroll--horizontal'), contains('overflow-x: auto'));
      expect(dnn('.dnn-scroll--reverse'),
          contains('flex-direction: column-reverse'));
      expect(dnn('.dnn-scroll.dnn-scroll--shrink'), contains('overflow: visible'));
    });

    test('an icon with no colour of its own inherits one', () {
      expect(dnn('.dnn-icon.material-icons'), contains('color: inherit'));
    });

    test('a canvas\'s surface fills its frame', () {
      expect(dnn('.dnn-canvas__surface'), contains('width: 100%'));
      expect(dnn('.dnn-canvas__surface'), contains('height: 100%'));
    });
  });

  group('bottom navigation', () {
    test('is a row, and a column when it is a rail', () {
      expect(dnn('.dnn-bottomnav'), contains('display: flex'));
      expect(dnn('.dnn-bottomnav--rail'), contains('flex-direction: column'));
    });
  });

  group('buttons', () {
    test('every kit draws outlined with a border and tonal with a wash', () {
      final mdl = declarationsIn('web_shell/kits/mdl.css');
      final materialize = declarationsIn('web_shell/kits/materialize.css');

      for (final outlined in [
        dnn('.dnn-button--outlined'),
        mdl('.dnn-kit-mdl .dnn-mdl-button--outlined'),
        materialize('.dnn-mz-button--outlined.btn-flat'),
      ]) {
        expect(outlined, contains('border: 1px solid'));
      }
      for (final tonal in [
        dnn('.dnn-button--tonal'),
        mdl('.dnn-kit-mdl .dnn-mdl-button--tonal'),
        materialize('.dnn-mz-button--tonal.btn-flat'),
      ]) {
        expect(tonal, contains('color-mix(in srgb, var(--dnn-primary)'));
      }
    });

    test('the extended floating button is a pill in every kit', () {
      final mdl = declarationsIn('web_shell/kits/mdl.css');
      final materialize = declarationsIn('web_shell/kits/materialize.css');

      for (final extended in [
        dnn('.dnn-fab.dnn-fab--extended'),
        mdl('.dnn-fab--extended.mdl-button--fab'),
        materialize('.dnn-fab--extended.btn-floating.btn-large'),
      ]) {
        expect(extended, contains('width: auto'));
        expect(extended, contains('border-radius: 16px'));
      }
    });
  });
}
