/// Rows that are not all the same height: where each one starts, and which
/// one a scroll offset lands on.
library;

import 'package:dart_not_native/src/lazy_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Heights 10, 20, 30, 40, 50 - offsets 0, 10, 30, 60, 100, total 150.
  RowExtents five() => RowExtents(5, (index) => (index + 1) * 10);

  test('a row starts where the ones above it end', () {
    final extents = five();

    expect(extents.offsetOf(0), 0);
    expect(extents.offsetOf(1), 10);
    expect(extents.offsetOf(3), 60);
    expect(extents.total, 150);
  });

  test('the window carries its own heights', () {
    expect(five().slice(1, 4), [20, 30, 40]);
  });

  test('an offset lands on the row it is inside', () {
    final extents = five();

    expect(extents.indexAt(0), 0);
    expect(extents.indexAt(9.9), 0);
    expect(extents.indexAt(10), 1);
    expect(extents.indexAt(59), 2);
    expect(extents.indexAt(60), 3);
    expect(extents.indexAt(149), 4);
  });

  test('past the end is the last row, not an exception', () {
    expect(five().indexAt(1000), 4);
    expect(five().offsetOf(99), 150);
  });

  test('a height that is nonsense is treated as nothing', () {
    final extents = RowExtents(3, (index) => index == 1 ? double.nan : 10);

    expect(extents.total, 20);
    expect(extents.offsetOf(2), 10);
  });

  test('an empty list has nothing to look up', () {
    final extents = RowExtents(0, (_) => 10);

    expect(extents.total, 0);
    expect(extents.indexAt(5), 0);
  });

  test('ten thousand rows are added up once, not searched linearly', () {
    final extents = RowExtents(10000, (index) => index.isEven ? 40 : 80);

    expect(extents.total, 5000 * 40 + 5000 * 80);
    // The row at 600,000 points down, found by halving rather than walking.
    expect(extents.indexAt(600000), 10000 - 1);
    expect(extents.indexAt(120), 2);
  });
}
