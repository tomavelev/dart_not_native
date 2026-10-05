/// The icon table, generated from Flutter's own.
///
/// The codepoints have to match the `MaterialIcons-Regular.otf` that
/// `uses-material-design: true` bundles, because that is the font the native
/// renderers draw from - a wrong number draws whatever glyph happens to sit
/// there, which is how the text-input FAB once showed a dark dot.
library;

import 'dart:io';

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

  test('the outlined, rounded and sharp variants are icons too', () {
    // Flutter keeps every style in the one `MaterialIcons` family, so these
    // are glyphs of the same font. Checked against Flutter's icons.dart.
    expect(Icons.home_outlined.codePoint, 0xf107);
    expect(Icons.home_rounded.codePoint, 0xf7f5);
    expect(Icons.home_sharp.codePoint, 0xea16);
    expect(Icons.timer_outlined.codePoint, 0xf44a);
    expect(Icons.timer_outlined.name, 'timer_outlined');
    // A style is another picture, so another number.
    expect(
      {
        Icons.home.codePoint,
        Icons.home_outlined.codePoint,
        Icons.home_rounded.codePoint,
        Icons.home_sharp.codePoint,
      },
      hasLength(4),
    );
  });

  test('a name is spelled as Flutter spells it', () {
    // Migrated code says `Icons.extension` and `Icons.class_`.
    expect(Icons.extension.codePoint, 0xe250);
    expect(Icons.class_.codePoint, 0xe165);
  });

  test('every icon Flutter names is in the class, in every style', () {
    final declared = RegExp(
      r'^  static const IconData (\w+) = IconData\((0x[0-9a-f]+), ',
      multiLine: true,
    ).allMatches(File('lib/src/icons.dart').readAsStringSync()).toList();
    // 8825 in the SDK this was generated from; the count follows the SDK, so
    // this only guards against the variants being dropped again.
    expect(declared.length, greaterThan(8000));
    for (final style in ['_outlined', '_rounded', '_sharp']) {
      expect(
        declared.where((icon) => icon.group(1)!.endsWith(style)).length,
        greaterThan(2000),
        reason: style,
      );
    }
  });

  test('the name table keeps to base names, since none of it tree-shakes', () {
    // A map is compiled in whole by any build that looks a name up; the
    // variants would make it four times the size. They are reached as
    // `Icons.home_outlined.codePoint`.
    expect(materialIconCount, lessThan(2500));
    expect(materialIconCodepoint('home_outlined'), isNull);
    expect(materialIconCodepoint('search_rounded'), isNull);
  });
}
