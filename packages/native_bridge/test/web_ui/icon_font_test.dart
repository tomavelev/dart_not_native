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

import 'package:brotli/brotli.dart';
import 'package:flutter_test/flutter_test.dart';

const _vendor = 'web_shell/vendor/material-icons';

/// [bytes] from [at] as WOFF2 writes a length - seven bits to a byte, most
/// significant first - and where the next thing starts.
(int value, int next) _base128(Uint8List bytes, int at) {
  var value = 0;
  while (true) {
    final byte = bytes[at++];
    value = (value << 7) | (byte & 0x7f);
    if (byte & 0x80 == 0) return (value, at);
  }
}

/// The codepoints the WOFF2 at [path] has a glyph for, from its `cmap`.
Set<int> mappedCodepoints(String path) {
  final woff2 = File(path).readAsBytesSync();
  final header = ByteData.sublistView(woff2);
  expect(header.getUint32(0), 0x774F4632, reason: 'not a WOFF2');
  expect(header.getUint32(8), woff2.length, reason: 'its stated length');

  // The directory: a flag byte that names the table - `cmap` is number 0,
  // and 63 means the tag follows in full - then its length. The tables
  // themselves follow in that order, as one Brotli stream.
  var at = 48;
  var offset = 0;
  int? cmapOffset;
  int? cmapLength;
  for (var i = 0; i < header.getUint16(12); i++) {
    final flags = woff2[at++];
    if (flags & 0x3f == 63) at += 4;
    final (length, next) = _base128(woff2, at);
    at = next;
    if (flags == 0) (cmapOffset, cmapLength) = (offset, length);
    offset += length;
  }
  final tables = Uint8List.fromList(
    brotli.decode(Uint8List.sublistView(woff2, at, at + header.getUint32(20))),
  );
  expect(tables.length, offset, reason: 'the tables its directory lists');
  if (cmapOffset != null && cmapLength != null) {
    final cmap = ByteData.sublistView(
      tables,
      cmapOffset,
      cmapOffset + cmapLength,
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
    final mapped = mappedCodepoints('$_vendor/MaterialIcons-Regular.woff2');
    final icons = RegExp(
      r'^  static const IconData (\w+) = IconData\((0x[0-9a-f]+), ',
      multiLine: true,
    ).allMatches(File('lib/src/icons.dart').readAsStringSync()).toList();
    expect(icons.length, greaterThan(8000));
    expect([
      for (final icon in icons)
        if (!mapped.contains(int.parse(icon.group(2)!))) icon.group(1),
    ], isEmpty);
  });

  test('the outlined, rounded and sharp ones among them', () {
    final mapped = mappedCodepoints('$_vendor/MaterialIcons-Regular.woff2');
    // home_outlined, home_rounded, home_sharp, timer_outlined.
    expect(mapped, containsAll([0xf107, 0xf7f5, 0xea16, 0xf44a]));
  });

  test('its licence travels with it', () {
    expect(File('$_vendor/LICENSE').existsSync(), isTrue);
  });
}
