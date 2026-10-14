/// `PageView` slides between pages: [PageController.animateToPage] and a
/// swipe draw the page left and the page arriving side by side, moved along
/// the axis by the view's own length, and [PageController.jumpToPage] does
/// not.
library;

import 'dart:async';

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pages(
    PageController controller, {
    TextDirection reading = TextDirection.ltr,
    Axis axis = Axis.horizontal,
  }) => Directionality(
    textDirection: reading,
    child: PageView(
      controller: controller,
      scrollDirection: axis,
      children: const [Text('Page 0'), Text('Page 1'), Text('Page 2')],
    ),
  );

  /// The view, once the renderer has said how big it is.
  Future<AppTester> measured(Widget widget) async {
    final app = AppTester.widget(widget);
    final view = app.nodes.firstWhere((n) => n.props['sizeEventId'] != null);
    await app.emit(view.props['sizeEventId'] as String, {
      'width': 360.0,
      'height': 600.0,
    });
    return app;
  }

  /// The pages being slid, as `{text: offset}`, and whether they move.
  (Map<String, num>, int?) sliding(AppTester app, [String key = 'dx']) {
    // A page at rest is in a box like the rest, with nothing moving it.
    final boxes = app.nodes.where(
      (n) =>
          ((n.props['id'] as String?)?.startsWith('page-') ?? false) &&
          n.props['transform'] != null,
    );
    String textIn(WidgetNode node) => node.type == 'Text'
        ? node.props['content'] as String
        : textIn(node.children!.single);
    return (
      {
        for (final box in boxes)
          textIn(box): (box.props['transform'] as Map)[key] as num,
      },
      boxes.firstOrNull?.props['animateMs'] as int?,
    );
  }

  Future<void> wait(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('animateToPage slides the next page in from the end', () async {
    final controller = PageController();
    final app = await measured(pages(controller));

    final done = controller.animateToPage(
      1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeInOut,
    );
    await wait(0);
    // First where it starts...
    expect(sliding(app).$1, {'Page 0': 0, 'Page 1': 360});
    expect(sliding(app).$2, 0);

    // ...then where it is going, over the time asked for.
    await wait(60);
    expect(sliding(app).$1, {'Page 0': -360, 'Page 1': 0});
    expect(sliding(app).$2, 120);
    expect(controller.page, 1);

    var arrived = false;
    unawaited(done.then((_) => arrived = true));
    await wait(150);
    expect(arrived, isTrue);
    expect(sliding(app).$1, isEmpty);
    expect(app.hasText('Page 1'), isTrue);
    expect(app.hasText('Page 0'), isFalse);
  });

  test('going back, the page before comes in from the start', () async {
    final controller = PageController(initialPage: 2);
    final app = await measured(pages(controller));

    unawaited(
      controller.animateToPage(
        0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.ease,
      ),
    );
    await wait(0);
    expect(sliding(app).$1, {'Page 2': 0, 'Page 0': -360});
    await wait(50);
    expect(sliding(app).$1, {'Page 2': 360, 'Page 0': 0});
  });

  test('read from the right, the next page comes in from the left', () async {
    final controller = PageController();
    final app = await measured(
      pages(controller, reading: TextDirection.rtl),
    );

    unawaited(
      controller.nextPage(
        duration: const Duration(milliseconds: 80),
        curve: Curves.ease,
      ),
    );
    await wait(0);
    expect(sliding(app).$1, {'Page 0': 0, 'Page 1': -360});
  });

  test('a vertical one slides by its height', () async {
    final controller = PageController();
    final app = await measured(pages(controller, axis: Axis.vertical));

    unawaited(
      controller.nextPage(
        duration: const Duration(milliseconds: 80),
        curve: Curves.ease,
      ),
    );
    await wait(0);
    expect(sliding(app, 'dy').$1, {'Page 0': 0, 'Page 1': 600});
  });

  test('jumpToPage is there at once', () async {
    final controller = PageController();
    final app = await measured(pages(controller));

    controller.jumpToPage(2);
    await wait(0);

    expect(sliding(app).$1, isEmpty);
    expect(app.hasText('Page 2'), isTrue);
  });

  test('a page let go of by a swipe slides in', () async {
    final controller = PageController();
    final app = await measured(pages(controller));
    final pan = app.nodes
        .firstWhere((n) => n.props['panAxis'] == 'horizontal')
        .props['panEventId'] as String;

    await app.emit('${pan}_start', {'x': 300.0});
    await app.emit('${pan}_end', {'x': 100.0});

    expect(sliding(app).$1, {'Page 0': 0, 'Page 1': 360});
    await wait(60);
    expect(sliding(app).$1, {'Page 0': -360, 'Page 1': 0});
  });

  group('under the finger', () {
    String panOf(AppTester app) =>
        app.nodes
                .firstWhere((n) => n.props['panAxis'] == 'horizontal')
                .props['panEventId']
            as String;

    test('the page follows it, and the next comes in beside it', () async {
      final controller = PageController();
      final app = await measured(pages(controller));
      final pan = panOf(app);

      await app.emit('${pan}_start', {'x': 300.0});
      await app.emit('${pan}_update', {'x': 200.0});

      expect(sliding(app).$1, {'Page 0': -100, 'Page 1': 260});
      expect(sliding(app).$2, isNull, reason: 'it moves with the finger');

      await app.emit('${pan}_update', {'x': 340.0});
      // Going the other way from the first page there is nothing before it:
      // the page gives a little, alone.
      expect(sliding(app).$1, {'Page 0': closeTo(13.3, 0.1)});
    });

    test('let go far enough, it slides on from where it was', () async {
      final controller = PageController();
      final app = await measured(pages(controller));
      final pan = panOf(app);

      await app.emit('${pan}_start', {'x': 300.0});
      await app.emit('${pan}_update', {'x': 150.0});
      await app.emit('${pan}_end', {'x': 150.0});

      expect(controller.page, 1);
      expect(sliding(app).$1, {'Page 0': -150, 'Page 1': 210});
      await wait(60);
      expect(sliding(app).$1, {'Page 0': -360, 'Page 1': 0});
    });

    test('let go short, it goes back', () async {
      final controller = PageController();
      final changed = <int>[];
      final app = await measured(
        Directionality(
          textDirection: TextDirection.ltr,
          child: PageView(
            controller: controller,
            onPageChanged: changed.add,
            children: const [Text('Page 0'), Text('Page 1')],
          ),
        ),
      );
      final pan = panOf(app);

      await app.emit('${pan}_start', {'x': 300.0});
      await app.emit('${pan}_update', {'x': 260.0});
      await app.emit('${pan}_end', {'x': 260.0});

      expect(controller.page, 0);
      expect(changed, isEmpty);
      expect(sliding(app).$1, {'Page 0': -40, 'Page 1': 320});
      await wait(60);
      expect(sliding(app).$1, {'Page 0': 0, 'Page 1': 360});
      await wait(400);
      expect(sliding(app).$1, isEmpty);
      expect(app.hasText('Page 0'), isTrue);
    });

    test('read from the right, a finger going right brings the next', () async {
      final controller = PageController();
      final app = await measured(
        pages(controller, reading: TextDirection.rtl),
      );
      final pan = panOf(app);

      await app.emit('${pan}_start', {'x': 100.0});
      await app.emit('${pan}_update', {'x': 180.0});

      expect(sliding(app).$1, {'Page 0': 80, 'Page 1': -280});
    });
  });

  test('with no view to show it, animateToPage completes at once', () async {
    final controller = PageController();
    await controller.animateToPage(
      2,
      duration: const Duration(seconds: 5),
      curve: Curves.ease,
    );
    expect(controller.page, 2);
  });
}
