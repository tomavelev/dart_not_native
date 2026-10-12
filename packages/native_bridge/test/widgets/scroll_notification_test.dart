/// A scroller tells the `NotificationListener`s above it that it moved.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Custom extends Notification {
  const _Custom(this.word);
  final String word;
}

void main() {
  late AppTester app;
  final heard = <ScrollNotification>[];

  setUp(heard.clear);

  Future<void> scrollTo(double offset, {String type = 'Scroll'}) => app.emit(
    app.ofType(type).single.props['scrollEventId'] as String,
    {'offset': offset, 'maxExtent': 2000.0, 'viewport': 600.0},
  );

  Widget page({bool Function(ScrollNotification)? outer, bool stop = false}) =>
      Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: outer,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              heard.add(notification);
              return stop;
            },
            child: SingleChildScrollView(
              child: Column(
                children: [for (var i = 0; i < 50; i++) Text('row $i')],
              ),
            ),
          ),
        ),
      );

  test('a scroller that moves says it started and where it is', () async {
    app = AppTester.widget(page());

    await scrollTo(120);

    expect(heard, hasLength(2));
    expect(heard[0], isA<ScrollStartNotification>());
    final update = heard[1] as ScrollUpdateNotification;
    expect(update.scrollDelta, 120);
    expect(update.metrics.pixels, 120);
    expect(update.metrics.maxScrollExtent, 2000);
    expect(update.metrics.viewportDimension, 600);
    expect(update.metrics.extentAfter, 1880);
    expect(update.metrics.axis, Axis.vertical);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('more movement is an update, not another start', () async {
    app = AppTester.widget(page());

    await scrollTo(120);
    await scrollTo(100);

    expect(heard.whereType<ScrollStartNotification>(), hasLength(1));
    expect((heard.last as ScrollUpdateNotification).scrollDelta, -20);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('a report of the same place says nothing', () async {
    app = AppTester.widget(page());

    await scrollTo(120);
    heard.clear();
    await scrollTo(120);

    expect(heard, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('a moment of quiet is the end, and then it can start again', () async {
    app = AppTester.widget(page());

    await scrollTo(120);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(heard.last, isA<ScrollEndNotification>());
    expect(heard.last.metrics.pixels, 120);

    heard.clear();
    await scrollTo(200);
    expect(heard.first, isA<ScrollStartNotification>());
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('it goes on up unless a listener answers true', () async {
    final above = <ScrollNotification>[];
    bool outer(ScrollNotification n) {
      above.add(n);
      return false;
    }

    app = AppTester.widget(page(outer: outer));
    await scrollTo(120);
    expect(above, hasLength(2));

    above.clear();
    app = AppTester.widget(page(outer: outer, stop: true));
    await scrollTo(120);
    expect(above, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('a listener for one kind hears only that kind', () async {
    final ends = <ScrollEndNotification>[];
    app = AppTester.widget(
      Scaffold(
        body: NotificationListener<ScrollEndNotification>(
          onNotification: (n) {
            ends.add(n);
            return false;
          },
          child: SingleChildScrollView(child: const Text('one')),
        ),
      ),
    );

    await scrollTo(50);
    expect(ends, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(ends, hasLength(1));
  });

  test('a windowed list says so too', () async {
    app = AppTester.widget(
      Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            heard.add(notification);
            return false;
          },
          child: ListView.builder(
            itemCount: 1000,
            itemExtent: 48,
            itemBuilder: (context, index) => Text('row $index'),
          ),
        ),
      ),
    );

    await scrollTo(960, type: 'LazyList');

    expect(heard.whereType<ScrollUpdateNotification>().single.metrics.pixels, 960);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  test('a notification of the app\'s own is dispatched from a context', () {
    final words = <String>[];
    late BuildContext inside;
    app = AppTester.widget(
      Scaffold(
        body: NotificationListener<_Custom>(
          onNotification: (n) {
            words.add(n.word);
            return true;
          },
          child: Builder(
            builder: (context) {
              inside = context;
              return const Text('x');
            },
          ),
        ),
      ),
    );

    const _Custom('hello').dispatch(inside);

    expect(words, ['hello']);
  });
}
