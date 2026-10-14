@TestOn('browser')
/// Browser test for a moving node's ask to be told when it has got there
/// (`endEventId`, `endAsk`).
///
/// Run with: flutter test --platform chrome test/web_ui/animation_end_test.dart
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late List<int> said;

  WidgetNode box(double width, {int? ask, int ms = 80}) => WidgetNode(
    type: 'Box',
    props: {
      'width': width,
      'height': 20,
      'animateMs': ms,
      if (ask != null) 'endEventId': 'end',
      'endAsk': ?ask,
    },
  );

  WebUIRenderer mounted({bool animations = true}) {
    final renderer = WebUIRenderer(root: root, animations: animations);
    renderer.onEvent('end', (data) => said.add(data['ask'] as int));
    return renderer;
  }

  setUp(() {
    root = mountRoot();
    said = [];
  });
  tearDown(() => root.remove());

  Future<void> wait(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('a box that moves says so once it has, and not before', () async {
    final renderer = mounted();
    await renderer.render(box(40));
    await renderer.render(box(120, ask: 1));

    await wait(30);
    expect(said, isEmpty);
    await wait(100);
    expect(said, [1]);
  });

  test('the same ask again is not answered again', () async {
    final renderer = mounted();
    await renderer.render(box(40));
    await renderer.render(box(120, ask: 1));
    await wait(120);
    await renderer.render(box(120, ask: 1));
    await wait(120);

    expect(said, [1]);
  });

  test('an ask overtaken before its end is not answered', () async {
    final renderer = mounted();
    await renderer.render(box(40));
    await renderer.render(box(120, ask: 1));
    await wait(30);
    await renderer.render(box(200, ask: 2));
    await wait(140);

    expect(said, [2]);
  });

  test('with no animations, at once', () async {
    final renderer = mounted(animations: false);
    await renderer.render(box(40));
    await renderer.render(box(120, ask: 1));
    await wait(1);

    expect(said, [1]);
  });
}
