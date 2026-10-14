/// A named route is a page over the one before it, as a pushed page is: what
/// is beneath is kept as it was left, and whoever pushed it hears how it
/// ended.
library;

import 'dart:async';

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter extends StatefulWidget {
  const _Counter(this.name);
  final String name;
  @override
  State<_Counter> createState() => _CounterState();
}

final Map<String, _CounterState> _live = {};
final List<String> _disposed = [];

class _CounterState extends State<_Counter> {
  int count = 0;
  String? route;
  Object? arguments;

  void bump() => setState(() => count++);

  @override
  void dispose() {
    _disposed.add(widget.name);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _live[widget.name] = this;
    final settings = ModalRoute.of(context)?.settings;
    route = settings?.name;
    arguments = settings?.arguments;
    return Scaffold(body: Text('${widget.name} $count'));
  }
}

void main() {
  late AppTester tester;

  NavigatorState nav(String page) => Navigator.of(_live[page]!.context);

  setUp(() {
    _live.clear();
    _disposed.clear();
    tester = AppTester.widget(
      MaterialApp(
        initialRoute: '/',
        routes: {
          '/': (_) => const _Counter('home'),
          '/two': (_) => const _Counter('two'),
          '/item': (context) => _Counter(
            'item ${ModalRoute.of(context)?.settings.arguments}',
          ),
        },
      ),
    );
  });

  test('the page beneath a named route is as it was left', () async {
    _live['home']!.bump();
    await pumpEventQueue();
    expect(tester.hasText('home 1'), isTrue);

    unawaited(nav('home').pushNamed('/two'));
    await pumpEventQueue();
    expect(tester.hasText('two 0'), isTrue);
    expect(_disposed, isEmpty, reason: 'home is beneath, not gone');

    nav('two').pop();
    await pumpEventQueue();
    expect(tester.hasText('home 1'), isTrue);
    expect(_disposed, ['two']);
  });

  test('a page beneath can still change, and shows it on the way back', () async {
    unawaited(nav('home').pushNamed('/two'));
    await pumpEventQueue();
    _live['home']!.bump();
    await pumpEventQueue();
    expect(tester.hasText('two 0'), isTrue);

    nav('two').pop();
    await pumpEventQueue();
    expect(tester.hasText('home 1'), isTrue);
  });

  test('the future of a named push is what the page was popped with', () async {
    Object? answer = 'not yet';
    unawaited(
      nav('home').pushNamed<String>('/two').then((value) => answer = value),
    );
    await pumpEventQueue();
    expect(answer, 'not yet', reason: 'the page is still on screen');

    nav('two').pop('chosen');
    await pumpEventQueue();
    expect(answer, 'chosen');
  });

  test('a page beneath is still its own route', () async {
    unawaited(nav('home').pushNamed('/two', arguments: 7));
    await pumpEventQueue();

    expect(_live['two']!.route, '/two');
    expect(_live['two']!.arguments, 7);
    expect(_live['home']!.route, '/');
    expect(_live['home']!.arguments, isNull);
  });

  test('the same route twice on the way is two pages', () async {
    unawaited(nav('home').pushNamed('/item', arguments: 1));
    await pumpEventQueue();
    _live['item 1']!.bump();
    unawaited(nav('item 1').pushNamed('/item', arguments: 2));
    await pumpEventQueue();
    expect(tester.hasText('item 2 0'), isTrue);

    nav('item 2').pop();
    await pumpEventQueue();
    expect(tester.hasText('item 1 1'), isTrue);
  });

  test('a page pushed again after going back starts afresh', () async {
    unawaited(nav('home').pushNamed('/two'));
    await pumpEventQueue();
    _live['two']!.bump();
    nav('two').pop();
    await pumpEventQueue();

    unawaited(nav('home').pushNamed('/two'));
    await pumpEventQueue();
    expect(tester.hasText('two 0'), isTrue);
  });

  test('a replaced page answers with the result it was replaced with', () async {
    Object? answer = 'not yet';
    unawaited(nav('home').pushNamed<String>('/two').then((v) => answer = v));
    await pumpEventQueue();

    unawaited(
      nav('two').pushReplacementNamed('/item', arguments: 3, result: 'moved'),
    );
    await pumpEventQueue();
    expect(tester.hasText('item 3 0'), isTrue);
    expect(answer, 'moved');
  });
}
