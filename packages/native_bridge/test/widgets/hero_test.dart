/// `Hero` in the widget layer: a box that carries the tag, for a renderer to
/// pair with the one on the other page.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a hero is a box with its tag around its child', () {
    final tester = AppTester.widget(
      const Scaffold(body: Hero(tag: 'cover-7', child: Text('book'))),
    );

    final hero = tester.ofType('Box').singleWhere(
      (node) => node.props['hero'] != null,
    );
    expect(hero.props['hero'], 'cover-7');
    expect(hero.children!.single.props['content'], 'book');
  });

  test('a tag that is not a string is told as it prints', () {
    final tester = AppTester.widget(
      const Scaffold(body: Hero(tag: 42, child: Text('x'))),
    );

    expect(
      tester.ofType('Box').where((node) => node.props['hero'] == '42'),
      hasLength(1),
    );
  });

  test('both pages have theirs when one is pushed over the other', () async {
    late BuildContext page;
    final tester = AppTester.widget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const Scaffold(body: Hero(tag: 'a', child: Text('small')));
          },
        ),
      ),
    );
    Navigator.of(page).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Hero(tag: 'a', child: Text('big'))),
      ),
    );
    await pumpEventQueue();

    // The page beneath is kept, not drawn: one hero on screen, the new one,
    // and the tree says how the page was reached.
    final heroes = tester.ofType('Box').where((n) => n.props['hero'] == 'a');
    expect(heroes, hasLength(1));
    expect(tester.hasText('big'), isTrue);
    expect(tester.tree.props['pageTransition'], isNotNull);
  });

  group('its flight', () {
    late BuildContext page;

    AppTester app(Widget hero) => AppTester.widget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const Scaffold(
              body: Hero(tag: 'a', child: Text('small')),
            );
          },
        ),
      ),
    );

    Future<WidgetNode> pushed(AppTester tester, Widget hero) async {
      Navigator.of(
        page,
      ).push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: hero)));
      await pumpEventQueue();
      return tester.ofType('Box').singleWhere((n) => n.props['hero'] == 'a');
    }

    test('arcs in a MaterialApp, as Flutter\'s does', () {
      final tester = app(const SizedBox());
      final hero = tester
          .ofType('Box')
          .singleWhere((n) => n.props['hero'] == 'a');
      expect(hero.props['heroArc'], isTrue);
    });

    test('flies straight outside one', () {
      final tester = AppTester.widget(
        const Scaffold(
          body: Hero(tag: 'a', child: Text('x')),
        ),
      );
      final hero = tester
          .ofType('Box')
          .singleWhere((n) => n.props['hero'] == 'a');
      expect(hero.props.containsKey('heroArc'), isFalse);
    });

    test('createRectTween says which', () async {
      final tester = app(const SizedBox());
      final straight = await pushed(
        tester,
        Hero(
          tag: 'a',
          createRectTween: (begin, end) => RectTween(begin: begin, end: end),
          child: const Text('big'),
        ),
      );
      expect(straight.props.containsKey('heroArc'), isFalse);
    });

    test(
      'the shuttle is drawn for the tree that turns the page, and only it',
      () async {
        final tester = app(const SizedBox());
        late HeroFlightDirection direction;
        late StateSetter rebuild;
        final hero = await pushed(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Hero(
                tag: 'a',
                flightShuttleBuilder: (_, animation, way, from, to) {
                  direction = way;
                  return Text('flying ${animation.value}');
                },
                child: const Text('big'),
              );
            },
          ),
        );
        final shuttle = hero.props['heroShuttle'] as Map;
        expect((shuttle['props'] as Map)['content'], 'flying 1.0');
        expect(direction, HeroFlightDirection.push);
        // Not among what is laid out.
        expect(tester.hasText('flying 1.0'), isFalse);

        rebuild(() {});
        await pumpEventQueue();
        final again = tester
            .ofType('Box')
            .singleWhere((n) => n.props['hero'] == 'a');
        expect(again.props.containsKey('heroShuttle'), isFalse);
      },
    );
  });

  test('flying back, it takes the shuttle of the hero it flies from',
      () async {
    late BuildContext page;
    final tester = AppTester.widget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const Scaffold(body: Hero(tag: 'a', child: Text('small')));
          },
        ),
      ),
    );
    Navigator.of(page).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Hero(
            tag: 'a',
            flightShuttleBuilder: (_, _, way, _, _) =>
                Text('shuttle ${way.name}'),
            child: const Text('big'),
          ),
        ),
      ),
    );
    await pumpEventQueue();
    Navigator.of(page).pop();
    await pumpEventQueue();

    final hero = tester.ofType('Box').singleWhere(
      (n) => n.props['hero'] == 'a',
    );
    expect(hero.children!.single.props['content'], 'small');
    final shuttle = hero.props['heroShuttle'] as Map;
    expect((shuttle['props'] as Map)['content'], 'shuttle pop');
  });

  test('what stands in for it is sent with every tree', () async {
    late BuildContext page;
    late StateSetter rebuild;
    Size? asked;
    final tester = AppTester.widget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const Scaffold(body: Hero(tag: 'a', child: Text('small')));
          },
        ),
      ),
    );
    Navigator.of(page).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: Hero(
                tag: 'a',
                placeholderBuilder: (_, size, child) {
                  asked = size;
                  return Opacity(opacity: 0.5, child: child);
                },
                child: const Text('big'),
              ),
            );
          },
        ),
      ),
    );
    await pumpEventQueue();

    WidgetNode hero() =>
        tester.ofType('Box').singleWhere((n) => n.props['hero'] == 'a');
    final standIn = hero().props['heroPlaceholder'] as Map;
    expect(asked, Size.zero);
    expect(standIn.toString(), contains('big'));
    // Not among what is laid out: the hero's child is.
    expect(
      tester.ofType('Text').where((n) => n.props['content'] == 'big'),
      hasLength(1),
    );

    // Still there after the page has turned: the hero a later flight
    // leaves is drawn from this tree.
    rebuild(() {});
    await pumpEventQueue();
    expect(hero().props['heroPlaceholder'].toString(), contains('big'));
  });

  group('MaterialRectArcTween', () {
    const begin = Rect.fromLTWH(0, 0, 10, 10);
    const end = Rect.fromLTWH(100, 200, 40, 40);

    test('starts and ends where it is told', () {
      final tween = MaterialRectArcTween(begin: begin, end: end);
      expect(tween.lerp(0), begin);
      expect(tween.lerp(1), end);
    });

    test('goes round, not straight', () {
      final arc = MaterialRectArcTween(begin: begin, end: end).lerp(0.5)!;
      final line = RectTween(begin: begin, end: end).lerp(0.5)!;
      expect(arc, isNot(line));
      // Flutter's own numbers for these two rectangles, half way.
      expect(arc.left, closeTo(73.6068, 1e-3));
      expect(arc.top, closeTo(88.1966, 1e-3));
      expect(arc.right, closeTo(105.2511, 1e-3));
      expect(arc.bottom, closeTo(107.9016, 1e-3));
    });

    test('a move along an axis is a straight line', () {
      const below = Rect.fromLTWH(0, 300, 10, 10);
      expect(
        MaterialRectArcTween(begin: begin, end: below).lerp(0.5),
        RectTween(begin: begin, end: below).lerp(0.5),
      );
    });
  });
}
