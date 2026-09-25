/// The icon table, generated from Flutter's own.
///
/// The codepoints have to match the `MaterialIcons-Regular.otf` that
/// `uses-material-design: true` bundles, because that is the font the native
/// renderers draw from - a wrong number draws whatever glyph happens to sit
/// there, which is how the text-input FAB once showed a dark dot.
library;

import 'package:dart_not_native/src/icons.dart';
import 'package:dart_not_native/src/material_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the whole filled set is there, not a curated handful', () {
    // Flutter ships a few more than two thousand base icons; the exact count
    // follows the SDK, so this only guards against the table shrinking back
    // to a hand-written list.
    expect(materialIconCount, greaterThan(2000));
  });

  test('an icon has the codepoint Flutter gives it', () {
    // Checked against packages/flutter/lib/src/material/icons.dart.
    expect(materialIconCodepoint('search'), 0xe567);
    expect(materialIconCodepoint('favorite'), 0xe25b);
    expect(materialIconCodepoint('home'), 0xe318);
    expect(materialIconCodepoint('more_vert'), 0xe404);
  });

  test('the icons an app names carry the same numbers', () {
    expect(Icons.search.codePoint, materialIconCodepoint('search'));
    expect(Icons.favorite.codePoint, materialIconCodepoint('favorite'));
    expect(Icons.settings.name, 'settings');
  });

  test('the ones the examples reach for are all there', () {
    for (final name in [
      'add',
      'arrow_back',
      'arrow_forward',
      'check',
      'close',
      'delete',
      'edit',
      'menu',
      'more_vert',
      'refresh',
      'share',
      'star',
    ]) {
      expect(materialIconCodepoint(name), isNotNull, reason: name);
    }
  });

  test('a name that is not an icon is null, not a guess', () {
    expect(materialIconCodepoint('definitely_not_an_icon'), isNull);
  });

  test('the variants that need a font we do not ship are left out', () {
    // Rounded, sharp and outlined live in fonts `uses-material-design` does
    // not bundle; their codepoints would draw whatever sits there in the
    // filled one.
    expect(materialIconCodepoint('search_rounded'), isNull);
    expect(materialIconCodepoint('home_outlined'), isNull);
  });
}
