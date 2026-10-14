/// `Table`, `ReorderableListView`, `InteractiveViewer` and `CustomScrollView`
/// with its slivers. None was there, so an app using one did not compile.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('a Table', () {
    Widget table({
      Map<int, TableColumnWidth>? widths,
      TableBorder? border,
    }) => _app(
      Table(
        columnWidths: widths,
        border: border,
        children: const [
          TableRow(children: [Text('a1'), Text('b1'), Text('c1')]),
          TableRow(children: [Text('a2'), Text('b2'), Text('c2')]),
        ],
      ),
    );

    List<WidgetNode> rows(AppTester app) => [
      for (final row in app.ofType('Row'))
        if ((row.children ?? const []).length == 3) row,
    ];

    test('shows every cell, row by row', () {
      final app = AppTester.widget(table());

      expect(app.texts, ['a1', 'b1', 'c1', 'a2', 'b2', 'c2']);
      expect(rows(app), hasLength(2));
    });

    test('columns share the width unless they state one', () {
      final app = AppTester.widget(
        table(
          widths: const {
            0: FixedColumnWidth(80),
            2: FlexColumnWidth(2),
          },
        ),
      );

      for (final row in rows(app)) {
        final cells = row.children!;
        // A stated width, then two shares - the second twice the first.
        expect(cells[0].type, isNot('Expanded'));
        expect(cells[0].props['width'], 80);
        expect(cells[1].type, 'Expanded');
        expect(cells[2].props['flex'], 2 * (cells[1].props['flex'] as num));
      }
    });

    test('a border draws lines between the rows and round the outside', () {
      final plain = AppTester.widget(table()).ofType('Box').length;
      final lined = AppTester.widget(
        table(border: TableBorder.all()),
      ).ofType('Box');

      expect(lined.length, greaterThan(plain));
      expect(
        lined.where((box) => box.props['borderWidth'] != null),
        isNotEmpty,
      );
    });

    test('a row can be decorated, and a cell placed in its row', () {
      final app = AppTester.widget(
        _app(
          Table(
            children: const [
              TableRow(
                decoration: BoxDecoration(color: Color(0xFFEEEEEE)),
                children: [
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Text('middle'),
                  ),
                  Text('top'),
                ],
              ),
            ],
          ),
        ),
      );

      expect(app.texts, ['middle', 'top']);
      expect(
        app.ofType('Box').where((box) => box.props['color'] == '#eeeeee'),
        hasLength(1),
      );
    });
  });

  group('a ReorderableListView', () {
    late List<String> items;
    late List<String> heard;

    setUp(() {
      items = ['a', 'b', 'c'];
      heard = [];
    });

    Widget list() => _app(
      ReorderableListView(
        onReorderStart: (index) => heard.add('start $index'),
        onReorderEnd: (index) => heard.add('end $index'),
        onReorder: (from, to) {
          heard.add('reorder $from $to');
          // What every Flutter app writes.
          if (to > from) to--;
          items.insert(to, items.removeAt(from));
        },
        children: [
          for (final item in items) Text(item, key: ValueKey(item)),
        ],
      ),
    );

    /// The boxes that can be picked up, and those that take a drop, in order.
    List<WidgetNode> carried(AppTester app) => [
      for (final node in app.nodes)
        if (node.props['dragData'] is String) node,
    ];
    List<WidgetNode> targets(AppTester app) => [
      for (final node in app.nodes)
        if (node.props['dropEventId'] is String) node,
    ];

    Future<void> drag(AppTester app, int from, int onto) => app.emit(
      targets(app)[onto].props['dropEventId'] as String,
      {'data': carried(app)[from].props['dragData']},
    );

    test('every row can be picked up, and takes a drop', () {
      final app = AppTester.widget(list());

      expect(app.texts, ['a', 'b', 'c']);
      expect(carried(app), hasLength(3));
      expect(targets(app), hasLength(3));
    });

    test('dropped on a later row, it goes after it', () async {
      final app = AppTester.widget(list());

      await drag(app, 0, 2);

      expect(heard, ['reorder 0 3']);
      expect(items, ['b', 'c', 'a']);
    });

    test('dropped on an earlier row, it goes before it', () async {
      final app = AppTester.widget(list());

      await drag(app, 2, 0);

      expect(heard, ['reorder 2 0']);
      expect(items, ['c', 'a', 'b']);
    });

    test('dropped on itself, nothing moves', () async {
      final app = AppTester.widget(list());

      await drag(app, 1, 1);

      expect(heard, isEmpty);
    });

    test('the app is told when a drag starts and ends', () async {
      final app = AppTester.widget(list());
      final id = carried(app)[1].props['dragEventId'] as String;

      await app.emit('${id}_start');
      await app.emit('${id}_end');

      expect(heard, ['start 1', 'end 1']);
    });

    test('the builder form builds the same rows', () {
      final app = AppTester.widget(
        _app(
          ReorderableListView.builder(
            itemCount: 2,
            onReorder: (_, _) {},
            itemBuilder: (context, index) =>
                Text('row $index', key: ValueKey(index)),
          ),
        ),
      );

      expect(app.texts, ['row 0', 'row 1']);
    });
  });

  group('an InteractiveViewer', () {
    Map<String, dynamic>? moved(AppTester app) {
      for (final node in app.nodes) {
        final transform = node.props['transform'];
        if (transform is Map) return Map<String, dynamic>.from(transform);
      }
      return null;
    }

    test('at rest it is its child, in a box that hears a pan', () {
      final app = AppTester.widget(
        _app(const InteractiveViewer(child: Text('Map'))),
      );

      expect(app.hasText('Map'), isTrue);
      expect(moved(app), isNull);
      expect(app.nodes.any((n) => n.props['panEventId'] is String), isTrue);
    });

    test('a finger pans the child', () async {
      final app = AppTester.widget(
        _app(const InteractiveViewer(child: Text('Map'))),
      );
      final pan = app.nodes
          .firstWhere((n) => n.props['panEventId'] is String)
          .props['panEventId'] as String;

      await app.emit('${pan}_start', const {});
      await app.emit('${pan}_update', {'dx': 30.0, 'dy': -10.0});
      await app.emit('${pan}_update', {'dx': 5.0, 'dy': 0.0});

      expect(moved(app)!['dx'], 35);
      expect(moved(app)!['dy'], -10);
    });

    test('the controller zooms it, within the scales it allows', () async {
      final controller = TransformationController();
      final app = AppTester.widget(
        _app(
          InteractiveViewer(
            transformationController: controller,
            maxScale: 3,
            child: const Text('Map'),
          ),
        ),
      );

      controller.value = Matrix4.identity()..scale(2.0);
      await Future<void>.delayed(Duration.zero);
      expect(moved(app)!['scale'], 2);

      controller.value = Matrix4.identity()..scale(10.0);
      await Future<void>.delayed(Duration.zero);
      expect(moved(app)!['scale'], 3);
    });

    test('with panning off there is nothing to hear', () {
      final app = AppTester.widget(
        _app(const InteractiveViewer(panEnabled: false, child: Text('Map'))),
      );

      expect(app.nodes.any((n) => n.props['panEventId'] is String), isFalse);
    });

    test('a pan along one axis says which', () {
      final app = AppTester.widget(
        _app(
          const InteractiveViewer(
            panAxis: PanAxis.horizontal,
            child: Text('Map'),
          ),
        ),
      );

      expect(
        app.nodes.firstWhere((n) => n.props['panEventId'] is String)
            .props['panAxis'],
        'horizontal',
      );
    });
  });

  group('a CustomScrollView', () {
    test('is one scroller, with every sliver\'s boxes in order', () {
      final app = AppTester.widget(
        _app(
          CustomScrollView(
            slivers: [
              const SliverAppBar(title: Text('Bar')),
              const SliverToBoxAdapter(child: Text('Intro')),
              SliverList.list(children: const [Text('one'), Text('two')]),
              SliverList.builder(
                itemCount: 2,
                itemBuilder: (context, index) => Text('built $index'),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => index < 2 ? Text('padded $index') : null,
                  ),
                ),
              ),
              const SliverFillRemaining(child: Text('The rest')),
            ],
          ),
        ),
      );

      expect(app.ofType('Scroll'), hasLength(1));
      expect(app.texts, [
        'Bar',
        'Intro',
        'one',
        'two',
        'built 0',
        'built 1',
        'padded 0',
        'padded 1',
        'The rest',
      ]);
    });

    test('separated puts something between each two', () {
      final app = AppTester.widget(
        _app(
          CustomScrollView(
            slivers: [
              SliverList.separated(
                itemCount: 3,
                itemBuilder: (context, index) => Text('item $index'),
                separatorBuilder: (context, index) => Text('gap $index'),
              ),
            ],
          ),
        ),
      );

      expect(app.texts, ['item 0', 'gap 0', 'item 1', 'gap 1', 'item 2']);
    });

    test('a grid among the slivers is a grid that does not scroll itself', () {
      final app = AppTester.widget(
        _app(
          CustomScrollView(
            slivers: [
              SliverGrid.count(
                crossAxisCount: 2,
                children: const [Text('g0'), Text('g1'), Text('g2')],
              ),
            ],
          ),
        ),
      );

      expect(app.texts, ['g0', 'g1', 'g2']);
      // The view's scroller, and no second one for the grid.
      expect(app.ofType('Scroll'), hasLength(1));
      expect(app.ofType('GridView'), hasLength(1));
    });

    test('a sliver that is hidden gives its replacement instead', () {
      final app = AppTester.widget(
        _app(
          const CustomScrollView(
            slivers: [
              SliverVisibility(
                visible: false,
                sliver: SliverToBoxAdapter(child: Text('Hidden')),
                replacementSliver: SliverToBoxAdapter(child: Text('Instead')),
              ),
            ],
          ),
        ),
      );

      expect(app.texts, ['Instead']);
    });

    test('a persistent header is drawn at its full height', () {
      final app = AppTester.widget(
        _app(
          CustomScrollView(
            slivers: [SliverPersistentHeader(delegate: _Header(), pinned: true)],
          ),
        ),
      );

      expect(app.hasText('Header at 0.0'), isTrue);
      expect(
        app.nodes.any((node) => node.props['height'] == 120),
        isTrue,
      );
    });

    test('an app bar with flexible space shows both titles\' places', () {
      final app = AppTester.widget(
        _app(
          const CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 160,
                actions: [Text('Action')],
                flexibleSpace: FlexibleSpaceBar(title: Text('Tall title')),
              ),
            ],
          ),
        ),
      );

      expect(app.texts, containsAll(['Tall title', 'Action']));
      expect(app.nodes.any((node) => node.props['height'] == 160), isTrue);
    });

    group('pinned at the top', () {
      bool scrolls(AppTester app, String text) => app
          .ofType('Scroll')
          .any((scroll) => _texts(scroll).contains(text));

      test('an app bar stands above the scroller, not in it', () {
        final app = AppTester.widget(
          _app(
            const CustomScrollView(
              slivers: [
                SliverAppBar(title: Text('Bar'), pinned: true),
                SliverToBoxAdapter(child: Text('Row')),
              ],
            ),
          ),
        );

        expect(app.hasText('Bar'), isTrue);
        expect(scrolls(app, 'Bar'), isFalse);
        expect(scrolls(app, 'Row'), isTrue);
      });

      test('one that is not pinned scrolls with the rest', () {
        final app = AppTester.widget(
          _app(
            const CustomScrollView(
              slivers: [
                SliverAppBar(title: Text('Bar')),
                SliverToBoxAdapter(child: Text('Row')),
              ],
            ),
          ),
        );

        expect(scrolls(app, 'Bar'), isTrue);
      });

      test('a tall one keeps its toolbar and lets the rest go', () {
        final app = AppTester.widget(
          _app(
            const CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: Text('Bar'),
                  pinned: true,
                  expandedHeight: 160,
                  flexibleSpace: FlexibleSpaceBar(title: Text('Tall title')),
                ),
                SliverToBoxAdapter(child: Text('Row')),
              ],
            ),
          ),
        );

        expect(scrolls(app, 'Bar'), isFalse);
        expect(scrolls(app, 'Tall title'), isTrue);
        // The toolbar's height is held; the rest of the 160 scrolls.
        final scroll = app.ofType('Scroll').single;
        expect(
          _nodes(scroll).any((node) => node.props['height'] == 104),
          isTrue,
        );
      });

      test('a header pinned straight after a pinned bar is held too', () {
        final app = AppTester.widget(
          _app(
            CustomScrollView(
              slivers: [
                const SliverAppBar(title: Text('Bar'), pinned: true),
                SliverPersistentHeader(delegate: _Header(), pinned: true),
                const SliverToBoxAdapter(child: Text('Row')),
              ],
            ),
          ),
        );

        expect(scrolls(app, 'Header at 0.0'), isFalse);
        expect(scrolls(app, 'Row'), isTrue);
      });

      test('a header pinned further down scrolls away', () {
        final app = AppTester.widget(
          _app(
            CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: Text('Row')),
                SliverPersistentHeader(delegate: _Header(), pinned: true),
              ],
            ),
          ),
        );

        expect(scrolls(app, 'Header at 0.0'), isTrue);
      });

      test('a view that takes only the room it needs holds nothing', () {
        final app = AppTester.widget(
          _app(
            const CustomScrollView(
              shrinkWrap: true,
              slivers: [
                SliverAppBar(title: Text('Bar'), pinned: true),
                SliverToBoxAdapter(child: Text('Row')),
              ],
            ),
          ),
        );

        expect(scrolls(app, 'Bar'), isTrue);
      });
    });

    test('a RefreshIndicator over one refreshes it', () {
      final app = AppTester.widget(
        _app(
          RefreshIndicator(
            onRefresh: () async {},
            child: const CustomScrollView(
              slivers: [SliverToBoxAdapter(child: Text('Row'))],
            ),
          ),
        ),
      );

      expect(
        app.ofType('Scroll').single.props['refreshEventId'],
        isA<String>(),
      );
    });
  });
}

class _Header extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 120;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Text('Header at $shrinkOffset');
  @override
  bool shouldRebuild(_Header oldDelegate) => false;
}

Iterable<WidgetNode> _nodes(WidgetNode node) sync* {
  yield node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    yield* _nodes(child);
  }
}

List<String> _texts(WidgetNode node) => [
  for (final inner in _nodes(node))
    if (inner.props['content'] case final String text) text,
];
