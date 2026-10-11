/// A windowed list's padding and its pull-to-refresh, on their way to a
/// renderer. The padding was a `Padding` node around the list, which held the
/// edges in rather than letting the rows scroll under them, and a
/// `RefreshIndicator` over a windowed list was its child and no more.
library;

import 'dart:async';

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _list({EdgeInsets? padding}) => ListView.builder(
  itemCount: 500,
  itemExtent: 48,
  padding: padding,
  itemBuilder: (context, index) => Text('Row $index'),
);

void main() {
  group('a windowed list\'s padding', () {
    test('is the list\'s own, not a node around it', () {
      final app = AppTester.widget(
        _list(padding: const EdgeInsets.fromLTRB(1, 2, 3, 4)),
      );

      expect(app.ofType('LazyList').single.props['padding'], [1, 2, 3, 4]);
      expect(app.ofType('Padding'), isEmpty);
    });

    test('is not said by a list that has none', () {
      final app = AppTester.widget(_list());

      expect(
        app.ofType('LazyList').single.props.containsKey('padding'),
        isFalse,
      );
    });
  });

  group('a RefreshIndicator over a windowed list', () {
    test('gives the list the refresh, and its spinner while it runs', () async {
      final done = Completer<void>();
      var asked = 0;
      final app = AppTester.widget(
        RefreshIndicator(
          onRefresh: () {
            asked++;
            return done.future;
          },
          child: _list(),
        ),
      );
      Map<String, dynamic> list() => app.ofType('LazyList').single.props;

      expect(list()['refreshing'], isFalse);
      await app.emit(list()['refreshEventId'] as String);

      expect(asked, 1);
      expect(list()['refreshing'], isTrue);

      done.complete();
      await Future<void>.delayed(Duration.zero);

      expect(list()['refreshing'], isFalse);
    });

    test('a list with no indicator over it has no refresh', () {
      final app = AppTester.widget(_list());

      expect(
        app.ofType('LazyList').single.props.containsKey('refreshEventId'),
        isFalse,
      );
    });

    test('the first scroller under it takes the refresh, once', () {
      final app = AppTester.widget(
        RefreshIndicator(
          onRefresh: () async {},
          child: Column(
            children: [
              Expanded(child: _list()),
              Expanded(child: _list()),
            ],
          ),
        ),
      );
      final lists = app.ofType('LazyList');

      expect(lists, hasLength(2));
      expect(lists.first.props['refreshEventId'], isA<String>());
      expect(lists.last.props.containsKey('refreshEventId'), isFalse);
    });
  });
}
