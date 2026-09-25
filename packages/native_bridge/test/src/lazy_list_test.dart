/// Tests for long lists: the window a `LazyList` node carries, and how an app
/// moves it when the renderer reports what is on screen.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/src/lazy_list.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ten thousand rows, of which only the window is ever built.
class _LongListApp extends NativeUIApp {
  int itemCount = 10000;
  final List<int> built = [];

  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Long list'),
    body: UIBuilder.lazyList(
      id: 'rows',
      itemCount: itemCount,
      itemExtent: 56,
      itemBuilder: (index) {
        built.add(index);
        return UIBuilder.text('Row $index');
      },
    ),
  );
}

WidgetNode _list(InMemoryRenderer renderer) =>
    renderer.tree!.children!.firstWhere((node) => node.type == 'LazyList');

Future<void> _reportVisible(
  InMemoryRenderer renderer,
  int first,
  int last,
) async {
  final eventId = _list(renderer).props['rangeEventId'] as String;
  await renderer.handleEvent(eventId, {'first': first, 'last': last});
}

void main() {
  group('LazyListWindow', () {
    test('starts at the top with the initial count', () {
      final window = LazyListWindow(initialCount: 20);
      expect(window.clampTo(1000), (0, 20));
    });

    test('never runs past the end of a short list', () {
      expect(LazyListWindow(initialCount: 30).clampTo(5), (0, 5));
      expect(LazyListWindow().clampTo(0), (0, 0));
    });

    test('keeps overscan rows either side of what is visible', () {
      final window = LazyListWindow();
      expect(
        window.update(first: 500, last: 510, itemCount: 1000, overscan: 10),
        isTrue,
      );
      expect((window.start, window.end), (490, 521));
    });

    test('stays put while the visible rows are well inside it', () {
      final window = LazyListWindow()
        ..update(first: 500, last: 510, itemCount: 1000, overscan: 10);
      expect(
        window.update(first: 502, last: 512, itemCount: 1000, overscan: 10),
        isFalse,
      );
      expect((window.start, window.end), (490, 521));
    });

    test('moves once the visible rows near an edge', () {
      final window = LazyListWindow()
        ..update(first: 500, last: 510, itemCount: 1000, overscan: 10);
      expect(
        window.update(first: 507, last: 517, itemCount: 1000, overscan: 10),
        isTrue,
      );
      expect((window.start, window.end), (497, 528));
    });

    test('does not move for an edge that is the list\'s own', () {
      final window = LazyListWindow(initialCount: 30);
      expect(
        window.update(first: 0, last: 10, itemCount: 1000, overscan: 10),
        isFalse,
      );
    });

    test('a list that shrinks under the window pulls it back', () {
      final window = LazyListWindow()
        ..update(first: 900, last: 910, itemCount: 1000, overscan: 10);
      expect(window.clampTo(100), (69, 100));
    });

    test('a report beyond the list is clamped to it', () {
      final window = LazyListWindow();
      window.update(first: 5000, last: 5010, itemCount: 100, overscan: 10);
      expect((window.start, window.end), (89, 100));
    });
  });

  group('UIBuilder.lazyList in an app', () {
    late _LongListApp app;
    late InMemoryRenderer renderer;

    setUp(() {
      app = _LongListApp();
      renderer = InMemoryRenderer();
      app.mount(renderer);
    });

    test('builds only the initial window of a huge list', () {
      final list = _list(renderer);
      expect(list.props['itemCount'], 10000);
      expect(list.props['itemExtent'], 56);
      expect(list.props['startIndex'], 0);
      expect(list.children, hasLength(30));
      expect(app.built, hasLength(30));
    });

    test('rows without an id are keyed by list and index', () {
      final ids = _list(renderer).children!.map((row) => row.props['id']);
      expect(ids.take(3), ['rows/0', 'rows/1', 'rows/2']);
    });

    test('a visible range far down moves the window and rebuilds', () async {
      app.built.clear();
      await _reportVisible(renderer, 5000, 5012);

      final list = _list(renderer);
      expect(list.props['startIndex'], 4990);
      expect(list.children!.first.props['content'], 'Row 4990');
      expect(list.children!.last.props['content'], 'Row 5022');
      expect(app.built, hasLength(33));
    });

    test('a range the window already covers renders nothing', () async {
      await _reportVisible(renderer, 5000, 5012);
      final before = renderer.tree;
      app.built.clear();

      await _reportVisible(renderer, 5001, 5013);

      expect(identical(renderer.tree, before), isTrue);
      expect(app.built, isEmpty);
    });

    test('the window survives an unrelated rebuild', () async {
      await _reportVisible(renderer, 5000, 5012);
      app.setState(() {});
      expect(_list(renderer).props['startIndex'], 4990);
    });

    test('shrinking the list keeps a valid window', () async {
      await _reportVisible(renderer, 9000, 9012);
      app.setState(() => app.itemCount = 50);

      final list = _list(renderer);
      expect(list.props['startIndex'], greaterThanOrEqualTo(0));
      expect(list.children!.last.props['content'], 'Row 49');
    });

    test('the range event id is stable across builds', () async {
      final eventId = _list(renderer).props['rangeEventId'];
      await _reportVisible(renderer, 5000, 5012);
      expect(_list(renderer).props['rangeEventId'], eventId);
    });
  });

  test('building a lazy list outside a build explains itself', () {
    expect(
      () => UIBuilder.lazyList(
        id: 'x',
        itemCount: 1,
        itemExtent: 10,
        itemBuilder: (_) => UIBuilder.text('x'),
      ),
      throwsStateError,
    );
  });

  group('rows of their own heights', () {
    /// Rows 40 points tall, every tenth one 120 - the shape of a feed with
    /// the odd picture in it.
    double heightOf(int index) => index % 10 == 0 ? 120 : 40;

    late _VariableListApp app;
    late InMemoryRenderer renderer;

    setUp(() {
      app = _VariableListApp(heightOf);
      renderer = InMemoryRenderer();
      app.mount(renderer);
    });

    Future<void> scrollTo(double offset, double viewport) async {
      final eventId = _list(renderer).props['rangeEventId'] as String;
      await renderer.handleEvent(eventId, {
        'offset': offset,
        'viewport': viewport,
      });
    }

    test('the node carries the window it holds, and the whole height', () {
      final list = _list(renderer);

      expect(list.props.containsKey('itemExtent'), isFalse);
      expect(list.props['startOffset'], 0);
      // 100 rows: ten of 120 and ninety of 40.
      expect(list.props['totalExtent'], 10 * 120 + 90 * 40);
      expect(
        (list.props['extents'] as List).take(11),
        [120, 40, 40, 40, 40, 40, 40, 40, 40, 40, 120],
      );
    });

    test('a scroll is reported in pixels and lands on the right row', () async {
      // 120 + 9*40 = 480 is the top of row 10.
      await scrollTo(480, 200);

      final list = _list(renderer);
      expect(list.props['startIndex'], 0);
      expect(app.built, contains(10));
      // The window reaches past what is visible, and its heights are the
      // heights of the rows it holds.
      final extents = list.props['extents'] as List;
      expect(extents.length, list.children!.length);
    });

    test('a scroll far down moves the window with it', () async {
      app.built.clear();
      // Row 50 starts at five blocks of (120 + 9*40) = 2400.
      await scrollTo(2400, 200);

      final list = _list(renderer);
      expect(list.props['startIndex'], 40);
      expect(list.props['startOffset'], 4 * 480);
      expect(app.built.first, 40);
      expect((list.props['extents'] as List).first, 120);
    });

    test('a report that is not pixels is ignored, not guessed at', () async {
      final before = _list(renderer).props['startIndex'];
      final eventId = _list(renderer).props['rangeEventId'] as String;

      await renderer.handleEvent(eventId, {'first': 40, 'last': 50});

      expect(_list(renderer).props['startIndex'], before);
    });
  });
}

/// A list whose rows are not all the same height.
class _VariableListApp extends NativeUIApp {
  _VariableListApp(this.heightOf);

  final double Function(int index) heightOf;
  final List<int> built = [];

  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Feed'),
    body: UIBuilder.lazyList(
      id: 'feed',
      itemCount: 100,
      itemExtentBuilder: heightOf,
      itemBuilder: (index) {
        built.add(index);
        return UIBuilder.text('Row $index');
      },
    ),
  );
}
