/// A swipe across a `TabBarView` moves to the tab beside it. There was no
/// swipe: the strip was the only way to choose a tab.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

BuildContext? _context;

Widget _tabs({
  ScrollPhysics? physics,
  TextDirection direction = TextDirection.ltr,
  int count = 3,
}) => Directionality(
  textDirection: direction,
  child: DefaultTabController(
    length: count,
    child: Column(
      children: [
        TabBar(tabs: [for (var i = 0; i < count; i++) Tab(text: 'Tab $i')]),
        Builder(
          builder: (context) {
            _context = context;
            return const SizedBox.shrink();
          },
        ),
        Expanded(
          child: TabBarView(
            physics: physics,
            children: [for (var i = 0; i < count; i++) Text('Page $i')],
          ),
        ),
      ],
    ),
  ),
);

void main() {
  /// The box that listens for the swipe: the one with a pan along the row.
  WidgetNode? swiped(AppTester app) => app.nodes
      .where((node) => node.props['panAxis'] == 'horizontal')
      .firstOrNull;

  Future<void> swipe(
    AppTester app, {
    required double from,
    required double to,
    double speed = 0,
  }) async {
    final id = swiped(app)!.props['panEventId'] as String;
    await app.emit('${id}_start', {'x': from, 'y': 100.0});
    await app.emit('${id}_update', {'x': to, 'y': 100.0, 'dx': to - from});
    await app.emit('${id}_end', {'x': to, 'y': 100.0, 'vx': speed});
  }

  group('the pages move', () {
    /// The view, told how wide it is, as a renderer tells it.
    Future<AppTester> measured() async {
      final app = AppTester.widget(_tabs());
      final view = swiped(app)!;
      await app.emit(view.props['sizeEventId'] as String, {
        'width': 360.0,
        'height': 500.0,
      });
      return app;
    }

    Map<String, num> moving(AppTester app) {
      String textIn(WidgetNode node) => node.type == 'Text'
          ? node.props['content'] as String
          : textIn(node.children!.single);
      return {
        for (final box in app.nodes.where(
          (n) =>
              ((n.props['id'] as String?)?.startsWith('page-') ?? false) &&
              n.props['transform'] != null,
        ))
          textIn(box): (box.props['transform'] as Map)['dx'] as num,
      };
    }

    test('selecting a tab slides the page there', () async {
      final app = await measured();
      DefaultTabController.of(_context!).index = 2;
      await Future<void>.delayed(Duration.zero);

      expect(moving(app), {'Page 0': 0, 'Page 2': 360});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(moving(app), {'Page 0': -360, 'Page 2': 0});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(app.hasText('Page 2'), isTrue);
      expect(moving(app), isEmpty);
    });

    test('the page follows a finger', () async {
      final app = await measured();
      final id = swiped(app)!.props['panEventId'] as String;
      await app.emit('${id}_start', {'x': 300.0, 'y': 100.0});
      await app.emit('${id}_update', {'x': 200.0, 'y': 100.0});

      expect(moving(app), {'Page 0': -100, 'Page 1': 260});
    });
  });

  test('a swipe towards the start shows the next tab', () async {
    final app = AppTester.widget(_tabs());
    expect(app.hasText('Page 0'), isTrue);

    await swipe(app, from: 300, to: 100);

    expect(app.hasText('Page 1'), isTrue);
    expect(app.hasText('Page 0'), isFalse);
  });

  test('a swipe towards the end goes back', () async {
    final app = AppTester.widget(_tabs());
    await swipe(app, from: 300, to: 100);

    await swipe(app, from: 100, to: 300);

    expect(app.hasText('Page 0'), isTrue);
  });

  test('a short, slow drag is not a swipe', () async {
    final app = AppTester.widget(_tabs());

    await swipe(app, from: 300, to: 260);

    expect(app.hasText('Page 0'), isTrue);
  });

  test('a short fling is', () async {
    final app = AppTester.widget(_tabs());

    await swipe(app, from: 300, to: 260, speed: -900);

    expect(app.hasText('Page 1'), isTrue);
  });

  test('a fling back the way the finger came is a change of mind', () async {
    final app = AppTester.widget(_tabs());

    await swipe(app, from: 300, to: 260, speed: 900);

    expect(app.hasText('Page 0'), isTrue);
  });

  test('there is nothing before the first tab or after the last', () async {
    final app = AppTester.widget(_tabs(count: 2));

    await swipe(app, from: 100, to: 300);
    expect(app.hasText('Page 0'), isTrue);

    await swipe(app, from: 300, to: 100);
    await swipe(app, from: 300, to: 100);
    expect(app.hasText('Page 1'), isTrue);
  });

  test('read from the right, the next tab is the other way', () async {
    final app = AppTester.widget(_tabs(direction: TextDirection.rtl));

    await swipe(app, from: 300, to: 100);
    expect(app.hasText('Page 0'), isTrue);

    await swipe(app, from: 100, to: 300);
    expect(app.hasText('Page 1'), isTrue);
  });

  test('physics that never scroll leave the strip the only way', () {
    final app = AppTester.widget(
      _tabs(physics: const NeverScrollableScrollPhysics()),
    );

    expect(swiped(app), isNull);
    expect(app.hasText('Page 0'), isTrue);
  });

  test('a drag detector along one axis says which', () {
    Map<String, dynamic> box(Widget detector) =>
        AppTester.widget(detector).ofType('Box').single.props;

    expect(
      box(GestureDetector(onHorizontalDragEnd: (_) {}, child: const Text('x')))
          ['panAxis'],
      'horizontal',
    );
    expect(
      box(GestureDetector(onVerticalDragUpdate: (_) {}, child: const Text('x')))
          ['panAxis'],
      'vertical',
    );
    // A pan, or both drags, is every direction's.
    expect(
      box(GestureDetector(onPanUpdate: (_) {}, child: const Text('x')))
          .containsKey('panAxis'),
      isFalse,
    );
    expect(
      box(
        GestureDetector(
          onHorizontalDragEnd: (_) {},
          onVerticalDragEnd: (_) {},
          child: const Text('x'),
        ),
      ).containsKey('panAxis'),
      isFalse,
    );
  });
}
