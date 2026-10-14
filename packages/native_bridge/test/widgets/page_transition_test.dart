/// A navigator tells the renderer when the page it draws is another one, and
/// how it got there (`RootProps.pageTransition`).
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppTester tester;
  late BuildContext page;

  Widget screen(String name) => Builder(
    builder: (context) {
      page = context;
      return Scaffold(body: Text(name));
    },
  );

  Object? transition() => tester.tree.props[RootProps.pageTransition];

  setUp(() => tester = AppTester.widget(MaterialApp(home: screen('home'))));

  test('the first page is simply there', () {
    expect(transition(), isNull);
  });

  test('a pushed page says push, and how long', () async {
    Navigator.of(page).push(MaterialPageRoute(builder: (_) => screen('two')));
    await pumpEventQueue();

    expect(tester.hasText('two'), isTrue);
    expect(transition(), {'kind': 'push', 'ms': 300});
  });

  test('only the first tree of the page says so', () async {
    late StateSetter rebuild;
    Navigator.of(page).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return screen('two');
          },
        ),
      ),
    );
    await pumpEventQueue();
    rebuild(() {});
    await pumpEventQueue();

    expect(transition(), isNull);
  });

  test('a popped page says pop', () async {
    Navigator.of(page).push(MaterialPageRoute(builder: (_) => screen('two')));
    await pumpEventQueue();
    Navigator.of(page).pop();
    await pumpEventQueue();

    expect(tester.hasText('home'), isTrue);
    expect(transition(), {'kind': 'pop', 'ms': 300});
  });

  test('a replaced page fades', () async {
    Navigator.of(page).push(MaterialPageRoute(builder: (_) => screen('two')));
    await pumpEventQueue();
    Navigator.of(page).pushReplacement(
      MaterialPageRoute(builder: (_) => screen('three')),
    );
    await pumpEventQueue();

    expect(tester.hasText('three'), isTrue);
    expect(transition(), {'kind': 'fade', 'ms': 300});
  });

  test('a route says how long it takes, each way', () async {
    Navigator.of(page).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => screen('two'),
        transitionDuration: const Duration(milliseconds: 120),
        reverseTransitionDuration: const Duration(milliseconds: 80),
      ),
    );
    await pumpEventQueue();
    expect(transition(), {'kind': 'push', 'ms': 120});

    Navigator.of(page).pop();
    await pumpEventQueue();
    expect(transition(), {'kind': 'pop', 'ms': 80});
  });

  test('no time, no transition', () async {
    Navigator.of(page).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => screen('two'),
        transitionDuration: Duration.zero,
      ),
    );
    await pumpEventQueue();

    expect(tester.hasText('two'), isTrue);
    expect(transition(), isNull);
  });

  group('named routes', () {
    late StateSetter rebuild;

    setUp(() {
      tester = AppTester.widget(
        MaterialApp(
          initialRoute: '/',
          routes: {
            '/': (_) => screen('home'),
            '/two': (_) => StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return screen('two');
              },
            ),
          },
        ),
      );
    });

    test('a named page pushed says push', () async {
      Navigator.of(page).pushNamed('/two');
      await pumpEventQueue();

      expect(tester.hasText('two'), isTrue);
      expect(transition(), {'kind': 'push', 'ms': 300});
    });

    test('and popped says pop', () async {
      Navigator.of(page).pushNamed('/two');
      await pumpEventQueue();
      Navigator.of(page).pop();
      await pumpEventQueue();

      expect(tester.hasText('home'), isTrue);
      expect(transition(), {'kind': 'pop', 'ms': 300});
    });

    test('pushed again after going back says push again', () async {
      // Going back keeps the page ahead; pushing cuts it off, so the way is
      // as long as it was and only the place along it has moved.
      Navigator.of(page).pushNamed('/two');
      await pumpEventQueue();
      Navigator.of(page).pop();
      await pumpEventQueue();
      Navigator.of(page).pushNamed('/two');
      await pumpEventQueue();

      expect(tester.hasText('two'), isTrue);
      expect(transition(), {'kind': 'push', 'ms': 300});
    });

    test('a rebuild of the same named page says nothing', () async {
      Navigator.of(page).pushNamed('/two');
      await pumpEventQueue();
      rebuild(() {});
      await pumpEventQueue();

      expect(transition(), isNull);
    });
  });
}
