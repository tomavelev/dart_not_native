/// Reads advance widths and kerning out of a font file - see [FontReader].
library;

import 'dart:typed_data';

/// The parts of a TrueType or OpenType file a width is read from: each
/// character's advance (`cmap` and `hmtx`), the kerning pairs of its `kern`
/// feature (`GPOS`) and the standard ligatures of its `liga` feature
/// (`GSUB`). For the tools that write `TextPainter`'s tables.
class FontReader {
  FontReader(Uint8List bytes) : _data = ByteData.sublistView(bytes) {
    final tables = _data.getUint16(4);
    for (var i = 0; i < tables; i++) {
      final at = 12 + i * 16;
      final tag = String.fromCharCodes(bytes.sublist(at, at + 4));
      _tables[tag] = _data.getUint32(at + 8);
    }
    _unitsPerEm = _data.getUint16(_tables['head']! + 18);
    _metrics = _data.getUint16(_tables['hhea']! + 34);
    _readCmap();
  }

  final ByteData _data;
  final Map<String, int> _tables = {};
  late final int _unitsPerEm;
  late final int _metrics;
  final Map<int, int> _glyphs = {};

  /// The characters the font has a glyph for.
  Iterable<int> get codePoints =>
      _glyphs.entries.where((e) => e.value != 0).map((e) => e.key);

  /// How wide [rune] is, in thousandths of an em; -1 with no glyph for it.
  int width(int rune) {
    final glyph = _glyphs[rune];
    if (glyph == null || glyph == 0) return -1;
    return _glyphWidth(glyph);
  }

  /// How wide [glyph] is, in thousandths of an em.
  int _glyphWidth(int glyph) {
    final index = glyph < _metrics ? glyph : _metrics - 1;
    final advance = _data.getUint16(_tables['hmtx']! + index * 4);
    return (advance * 1000 / _unitsPerEm).round();
  }

  /// The characters the font's `liga` feature draws as one glyph - `fi`,
  /// `ffl` - each with that glyph's width in thousandths of an em. A
  /// ligature of glyphs no character maps to is left out.
  List<(List<int>, int)> ligatures() {
    final gsub = _tables['GSUB'];
    if (gsub == null) return const [];
    final runeOf = <int, int>{};
    for (final MapEntry(key: rune, value: glyph) in _glyphs.entries) {
      if (glyph != 0) runeOf.putIfAbsent(glyph, () => rune);
    }
    final out = <(List<int>, int)>[];
    final seen = <String>{};
    for (final subtable in _subtables(gsub, 'liga', single: 4, extension: 7)) {
      final firsts = _coverageGlyphs(subtable + _data.getUint16(subtable + 2));
      for (var i = 0; i < firsts.length; i++) {
        final set = subtable + _data.getUint16(subtable + 6 + i * 2);
        for (var j = 0; j < _data.getUint16(set); j++) {
          final ligature = set + _data.getUint16(set + 2 + j * 2);
          final count = _data.getUint16(ligature + 2);
          final glyphs = [
            firsts[i],
            for (var k = 1; k < count; k++)
              _data.getUint16(ligature + 4 + (k - 1) * 2),
          ];
          final runes = [for (final g in glyphs) runeOf[g]];
          if (runes.contains(null)) continue;
          // The first lookup to take a sequence is the one a shaper uses.
          if (!seen.add(runes.join(','))) continue;
          out.add((
            [for (final r in runes) r!],
            _glyphWidth(_data.getUint16(ligature)),
          ));
        }
      }
    }
    return out;
  }

  /// How much narrower each ligature is than its characters set one by one
  /// with the kerning between them that `TextPainter` counts (printable
  /// ASCII), by the characters, in thousandths of an em. A ligature that
  /// saves nothing is left out.
  Map<String, int> ligatureSavings() => {
    for (final (runes, joined) in ligatures())
      if (_apart(runes) - joined case final saving when saving != 0)
        String.fromCharCodes(runes): saving,
  };

  /// How wide [runes] are set one by one, kerned as `TextPainter` kerns.
  int _apart(List<int> runes) {
    bool printable(int c) => c >= 0x20 && c < 0x7F;
    var width = 0;
    for (var i = 0; i < runes.length; i++) {
      width += this.width(runes[i]);
      if (i > 0 && printable(runes[i - 1]) && printable(runes[i])) {
        width += kern(runes[i - 1], runes[i]);
      }
    }
    return width;
  }

  /// The glyphs a coverage table lists, in its order.
  List<int> _coverageGlyphs(int coverage) {
    final format = _data.getUint16(coverage);
    final count = _data.getUint16(coverage + 2);
    if (format == 1) {
      return [
        for (var i = 0; i < count; i++) _data.getUint16(coverage + 4 + i * 2),
      ];
    }
    return [
      for (var i = 0; i < count; i++)
        for (
          var g = _data.getUint16(coverage + 4 + i * 6);
          g <= _data.getUint16(coverage + 6 + i * 6);
          g++
        )
          g,
    ];
  }

  /// How far [right] is moved towards [left] when it follows it, in
  /// thousandths of an em - the font's `kern` feature in `GPOS`, as pair
  /// adjustments; 0 where it says nothing.
  int kern(int left, int right) {
    final a = _glyphs[left], b = _glyphs[right];
    if (a == null || b == null || a == 0 || b == 0) return 0;
    for (final subtable in _kernSubtables) {
      final value = _pairAdjust(subtable, a, b);
      if (value != null) return (value * 1000 / _unitsPerEm).round();
    }
    return 0;
  }

  /// The pair-adjustment subtables of the `kern` feature's lookups, in order.
  late final List<int> _kernSubtables = _readKern();

  List<int> _readKern() {
    final gpos = _tables['GPOS'];
    if (gpos == null) return const [];
    return _subtables(gpos, 'kern', single: 2, extension: 9);
  }

  /// The subtables of type [single] in the lookups of [table]'s feature
  /// [tag], in lookup order - those behind an [extension] lookup included.
  List<int> _subtables(
    int table,
    String tag, {
    required int single,
    required int extension,
  }) {
    final features = table + _data.getUint16(table + 6);
    final lookups = table + _data.getUint16(table + 8);
    final indices = <int>{};
    final featureCount = _data.getUint16(features);
    for (var i = 0; i < featureCount; i++) {
      final at = features + 2 + i * 6;
      final name = String.fromCharCodes([
        for (var k = 0; k < 4; k++) _data.getUint8(at + k),
      ]);
      if (name != tag) continue;
      final feature = features + _data.getUint16(at + 4);
      final count = _data.getUint16(feature + 2);
      for (var j = 0; j < count; j++) {
        indices.add(_data.getUint16(feature + 4 + j * 2));
      }
    }
    final out = <int>[];
    for (final index in indices.toList()..sort()) {
      final lookup = lookups + _data.getUint16(lookups + 2 + index * 2);
      final type = _data.getUint16(lookup);
      final count = _data.getUint16(lookup + 4);
      for (var j = 0; j < count; j++) {
        var subtable = lookup + _data.getUint16(lookup + 6 + j * 2);
        var subtype = type;
        if (type == extension) {
          // An extension: the real subtable is further on.
          subtype = _data.getUint16(subtable + 2);
          subtable += _data.getUint32(subtable + 4);
        }
        if (subtype == single) out.add(subtable);
      }
    }
    return out;
  }

  /// Where [glyph] is in a coverage table, or -1.
  int _covered(int coverage, int glyph) {
    final format = _data.getUint16(coverage);
    final count = _data.getUint16(coverage + 2);
    if (format == 1) {
      for (var i = 0; i < count; i++) {
        if (_data.getUint16(coverage + 4 + i * 2) == glyph) return i;
      }
      return -1;
    }
    for (var i = 0; i < count; i++) {
      final at = coverage + 4 + i * 6;
      final start = _data.getUint16(at), end = _data.getUint16(at + 2);
      if (glyph >= start && glyph <= end) {
        return _data.getUint16(at + 4) + glyph - start;
      }
    }
    return -1;
  }

  /// The class [glyph] is in, by a class definition table.
  int _classOf(int classDef, int glyph) {
    final format = _data.getUint16(classDef);
    if (format == 1) {
      final start = _data.getUint16(classDef + 2);
      final count = _data.getUint16(classDef + 4);
      final i = glyph - start;
      return i >= 0 && i < count ? _data.getUint16(classDef + 6 + i * 2) : 0;
    }
    final count = _data.getUint16(classDef + 2);
    for (var i = 0; i < count; i++) {
      final at = classDef + 4 + i * 6;
      if (glyph >= _data.getUint16(at) && glyph <= _data.getUint16(at + 2)) {
        return _data.getUint16(at + 4);
      }
    }
    return 0;
  }

  /// The bytes a value record of [format] takes, and where its x advance is
  /// in it (-1 when it has none).
  static (int, int) _valueRecord(int format) {
    var size = 0;
    var advance = -1;
    for (var bit = 0; bit < 8; bit++) {
      if (format & (1 << bit) == 0) continue;
      if (bit == 2) advance = size;
      size += 2;
    }
    return (size, advance);
  }

  /// A pair adjustment subtable's x advance for [a] then [b], or null when
  /// it does not cover them.
  int? _pairAdjust(int subtable, int a, int b) {
    final format = _data.getUint16(subtable);
    final first = _covered(subtable + _data.getUint16(subtable + 2), a);
    if (first < 0) return null;
    final (size1, advance1) = _valueRecord(_data.getUint16(subtable + 4));
    final (size2, _) = _valueRecord(_data.getUint16(subtable + 6));
    if (format == 1) {
      final set = subtable + _data.getUint16(subtable + 10 + first * 2);
      final count = _data.getUint16(set);
      final record = 2 + size1 + size2;
      for (var i = 0; i < count; i++) {
        final at = set + 2 + i * record;
        if (_data.getUint16(at) == b) {
          return advance1 < 0 ? 0 : _data.getInt16(at + 2 + advance1);
        }
      }
      return null;
    }
    final class1 = _classOf(subtable + _data.getUint16(subtable + 8), a);
    final class2 = _classOf(subtable + _data.getUint16(subtable + 10), b);
    final class2Count = _data.getUint16(subtable + 14);
    final at = subtable + 16 + (class1 * class2Count + class2) * (size1 + size2);
    return advance1 < 0 ? 0 : _data.getInt16(at + advance1);
  }

  /// The Unicode BMP subtable (platform 3, encoding 1; format 4).
  void _readCmap() {
    final cmap = _tables['cmap']!;
    final count = _data.getUint16(cmap + 2);
    int? table;
    for (var i = 0; i < count; i++) {
      final at = cmap + 4 + i * 8;
      if (_data.getUint16(at) == 3 && _data.getUint16(at + 2) == 1) {
        table = cmap + _data.getUint32(at + 4);
      }
    }
    if (table == null || _data.getUint16(table) != 4) {
      throw StateError('no Unicode format-4 cmap');
    }
    final segments = _data.getUint16(table + 6) ~/ 2;
    final ends = table + 14;
    final starts = ends + segments * 2 + 2;
    final deltas = starts + segments * 2;
    final offsets = deltas + segments * 2;
    for (var s = 0; s < segments; s++) {
      final end = _data.getUint16(ends + s * 2);
      final start = _data.getUint16(starts + s * 2);
      final delta = _data.getInt16(deltas + s * 2);
      final offsetAt = offsets + s * 2;
      final offset = _data.getUint16(offsetAt);
      for (var rune = start; rune <= end && rune != 0xFFFF; rune++) {
        int glyph;
        if (offset == 0) {
          glyph = (rune + delta) & 0xFFFF;
        } else {
          final at = offsetAt + offset + (rune - start) * 2;
          glyph = _data.getUint16(at);
          if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
        }
        _glyphs[rune] = glyph;
      }
    }
  }
}
