/// A back swipe: the root offers one while the page on top can be popped,
/// carries the page beneath while a finger is on it, and pops on commit with
/// no page transition of its own.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppTester tester;
  late BuildContext page;

  Widget screen(String name, {bool canPop = true}) => Builder(
    builder: (context) {
      page = context;
      final body = Scaffold(body: Text(name));
      return canPop ? body : PopScope(canPop: false, child: body);
    },
  );

  String? offered() =>
      tester.tree.props[RootProps.backSwipeEventId] as String?;

  List<String> beneath() {
    final node = tester.tree.props[RootProps.beneath];
    if (node is! Map) return const [];
    final texts = <String>[];
    void walk(Object? n) {
      if (n is! Map) return;
      final content = (n['props'] as Map?)?['content'];
      if (content is String) texts.add(content);
      for (final child in (n['children'] as List?) ?? const []) {
        walk(child);
      }
    }

    walk(node);
    return texts;
  }

  Future<void> swipe(String phase) async {
    await tester.renderer.handleEvent(offered()!, {'phase': phase});
    await pumpEventQueue();
  }

  setUp(() => tester = AppTester.widget(MaterialApp(home: screen('home'))));

  Future<void> pushTwo({bool canPop = true, bool dialog = false}) async {
    Navigator.of(page).push(
      MaterialPageRoute<void>(
        fullscreenDialog: dialog,
        builder: (_) => screen('two', canPop: canPop),
      ),
    );
    await pumpEventQueue();
  }

  test('is not offered with nothing to go back to', () {
    expect(offered(), isNull);
  });

  test('is offered over a pushed page, and draws the page beneath while '
      'a finger is on it', () async {
    await pushTwo();
    expect(offered(), isA<String>());
    expect(beneath(), isEmpty);

    await swipe('start');
    expect(tester.hasText('two'), isTrue);
    expect(beneath(), contains('home'));
  });

  test('a page that is the whole screen is not marked as moving alone: the '
      'screen moves', () async {
    await pushTwo();
    await swipe('start');
    expect(
      tester.nodes.where((n) => n.props.containsKey(RootProps.backSwipePage)),
      isEmpty,
    );
  });

  test('a commit pops, with no transition of its own', () async {
    await pushTwo();
    await swipe('start');
    await swipe('commit');
    expect(tester.hasText('home'), isTrue);
    expect(tester.hasText('two'), isFalse);
    expect(tester.tree.props.containsKey(RootProps.pageTransition), isFalse);
    expect(offered(), isNull);
  });

  test('a cancel keeps the page, and stops drawing the one beneath', () async {
    await pushTwo();
    await swipe('start');
    await swipe('cancel');
    expect(tester.hasText('two'), isTrue);
    expect(beneath(), isEmpty);
  });

  test('is not offered over a page that refuses to go, or a full-screen '
      'dialog', () async {
    await pushTwo(canPop: false);
    expect(offered(), isNull);
    Navigator.of(page).pop();
    await pumpEventQueue();
    await pushTwo(dialog: true);
    expect(offered(), isNull);
  });
}
