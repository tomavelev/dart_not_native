/// `Hero` in the widget layer: a box that carries the tag, for a renderer to
/// pair with the one on the other page.
library;

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
}
