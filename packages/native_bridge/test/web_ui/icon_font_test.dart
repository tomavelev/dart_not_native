@TestOn('vm')
/// The font half of an icon on the web.
///
/// The renderer writes the character at an icon's codepoint
/// (`extended_props_test.dart`); what draws it is the font the shell ships,
/// so that file is read here. It has to be Flutter's own, because `Icons.x`
/// carries Flutter's codepoints - another Material Icons font has the same
/// pictures at other numbers, and only the filled ones.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

const _vendor = 'web_shell/vendor/material-icons';

/// The codepoints the WOFF at [path] has a glyph for, from its `cmap`.
Set<int> mappedCodepoints(String path) {
  final woff = File(path).readAsBytesSync();
  final header = ByteData.sublistView(woff);
  expect(header.getUint32(0), 0x774F4646, reason: 'not a WOFF');
  for (var i = 0; i < header.getUint16(12); i++) {
    final entry = 44 + 20 * i;
    if (header.getUint32(entry) != 0x636D6170) continue; // 'cmap'
    final offset = header.getUint32(entry + 4);
    final stored = header.getUint32(entry + 8);
    final length = header.getUint32(entry + 12);
    final bytes = Uint8List.sublistView(woff, offset, offset + stored);
    final cmap = ByteData.sublistView(
      stored < length ? Uint8List.fromList(zlib.decode(bytes)) : bytes,
    );
    for (var t = 0; t < cmap.getUint16(2); t++) {
      // Format 12 is the one that reaches past the sixteen-bit range.
      final table = cmap.getUint32(4 + 8 * t + 4);
      if (cmap.getUint16(table) != 12) continue;
      final mapped = <int>{};
      for (var g = 0; g < cmap.getUint32(table + 12); g++) {
        final group = table + 16 + 12 * g;
        final first = cmap.getUint32(group);
        final last = cmap.getUint32(group + 4);
        final glyph = cmap.getUint32(group + 8);
        for (var code = first; code <= last; code++) {
          // Glyph 0 is the font's "no such character".
          if (glyph + code - first != 0) mapped.add(code);
        }
      }
      return mapped;
    }
  }
  fail('no format 12 cmap in $path');
}

void main() {
  final css = File('$_vendor/material-icons.css').readAsStringSync();

  test('the icon class draws from the font the shell ships', () {
    expect(css, contains('font-family: "Material Icons"'));
    final source = RegExp(r'url\("\./([^"]+)"\)').firstMatch(css)!.group(1)!;
    expect(File('$_vendor/$source').existsSync(), isTrue, reason: source);
    // Nothing shows until the font is there, rather than a row of boxes.
    expect(css, contains('font-display: block'));
  });

  test('that font has a glyph at every codepoint in Icons', () {
    final mapped = mappedCodepoints('$_vendor/MaterialIcons-Regular.woff');
    final icons = RegExp(
      r'^  static const IconData (\w+) = IconData\((0x[0-9a-f]+), ',
      multiLine: true,
    ).allMatches(File('lib/src/icons.dart').readAsStringSync()).toList();
    expect(icons.length, greaterThan(8000));
    expect(
      [
        for (final icon in icons)
          if (!mapped.contains(int.parse(icon.group(2)!))) icon.group(1),
      ],
      isEmpty,
    );
  });

  test('the outlined, rounded and sharp ones among them', () {
    final mapped = mappedCodepoints('$_vendor/MaterialIcons-Regular.woff');
    // home_outlined, home_rounded, home_sharp, timer_outlined.
    expect(mapped, containsAll([0xf107, 0xf7f5, 0xea16, 0xf44a]));
  });

  test('its licence travels with it', () {
    expect(File('$_vendor/LICENSE').existsSync(), isTrue);
  });
}
