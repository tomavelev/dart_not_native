/// The window of rows a `LazyList` node carries.
///
/// A list of ten thousand rows cannot be built, sent and drawn on every
/// render. The node carries only the rows around what is on screen, plus the
/// total count and the fixed row height the renderer needs to size the
/// scrollable area. The renderer reports which rows are visible; this decides
/// when that calls for a different window.
library;

/// Where every row of a list starts and ends, when they are not all the same
/// height.
///
/// A uniform list needs none of this: a renderer multiplies an index by the
/// row height and knows where everything is. Rows that differ have to be added
/// up, and the sum has to exist on the Dart side, because that is the only
/// place that knows about rows outside the window - a renderer is holding
/// twenty of ten thousand.
///
/// So the renderer reports *pixels* (where it is scrolled to, and how tall its
/// viewport is) and this turns them back into row numbers.
class RowExtents {
  /// Builds the offsets for [itemCount] rows, each as tall as [extentOf] says.
  RowExtents(int itemCount, double Function(int index) extentOf)
      : _offsets = List<double>.filled(itemCount + 1, 0) {
    for (var i = 0; i < itemCount; i++) {
      final extent = extentOf(i);
      _offsets[i + 1] = _offsets[i] + (extent.isFinite && extent > 0 ? extent : 0);
    }
  }

  /// `_offsets[i]` is where row i starts; the last entry is the total height.
  final List<double> _offsets;

  int get itemCount => _offsets.length - 1;

  /// The height of the whole list.
  double get total => _offsets.last;

  /// Where row [index] starts.
  double offsetOf(int index) => _offsets[index.clamp(0, itemCount)];

  /// The height of row [index].
  double extentOf(int index) =>
      index < 0 || index >= itemCount ? 0 : _offsets[index + 1] - _offsets[index];

  /// The heights of rows [start] (inclusive) to [end] (exclusive).
  List<double> slice(int start, int end) =>
      [for (var i = start; i < end; i++) extentOf(i)];

  /// The last row that starts at or before [offset] - the row a viewport with
  /// its top edge there is showing first.
  int indexAt(double offset) {
    if (itemCount == 0) return 0;
    var low = 0;
    var high = itemCount - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_offsets[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}

class LazyListWindow {
  LazyListWindow({int initialCount = 30}) : _end = initialCount;

  int _start = 0;
  int _end;

  /// First row in the window.
  int get start => _start;

  /// One past the last row in the window.
  int get end => _end;

  /// The window clamped to a list of [itemCount] rows.
  ///
  /// A list that shrinks under a window scrolled near its end keeps the same
  /// number of rows, moved up to fit, rather than showing an empty window.
  (int, int) clampTo(int itemCount) {
    if (itemCount <= 0) return (_start = 0, _end = 0);
    final size = (_end - _start).clamp(1, itemCount);
    if (_end > itemCount) {
      _end = itemCount;
      _start = (itemCount - size).clamp(0, itemCount);
    }
    return (_start, _end);
  }

  /// Takes the renderer's report that rows [first]..[last] (inclusive) are
  /// visible, and returns whether the window moved.
  ///
  /// The window keeps [overscan] rows either side of the visible ones. It only
  /// moves once the visible rows come within half of that margin of an edge,
  /// so a slow scroll re-renders every few rows rather than on every row.
  bool update({
    required int first,
    required int last,
    required int itemCount,
    int overscan = 10,
  }) {
    if (itemCount <= 0) {
      final moved = _start != 0 || _end != 0;
      _start = _end = 0;
      return moved;
    }
    first = first.clamp(0, itemCount - 1);
    last = last.clamp(first, itemCount - 1);

    final margin = overscan ~/ 2;
    final coveredAbove = first - _start >= margin || _start == 0;
    final coveredBelow = _end - 1 - last >= margin || _end >= itemCount;
    if (first >= _start && last < _end && coveredAbove && coveredBelow) {
      return false;
    }

    final start = (first - overscan).clamp(0, itemCount);
    final end = (last + 1 + overscan).clamp(0, itemCount);
    if (start == _start && end == _end) return false;
    _start = start;
    _end = end;
    return true;
  }
}
