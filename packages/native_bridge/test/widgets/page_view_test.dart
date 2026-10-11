/// `PageView`: pages one at a time, swiped between. It was not there, so an
/// app with an onboarding carousel or a gallery did not compile.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WidgetNode? swiped(AppTester app, [String axis = 'horizontal']) =>
      app.nodes.where((node) => node.props['panAxis'] == axis).firstOrNull;

  Future<void> swipe(AppTester app, double by, {bool vertical = false}) async {
    final id =
        swiped(app, vertical ? 'vertical' : 'horizontal')!.props['panEventId']
            as String;
    final key = vertical ? 'y' : 'x';
    await app.emit('${id}_start', {key: 300.0});
    await app.emit('${id}_end', {key: 300.0 + by});
  }

  Widget pages({
    PageController? controller,
    ValueChanged<int>? onPageChanged,
    Axis axis = Axis.horizontal,
    bool reverse = false,
    ScrollPhysics? physics,
    TextDirection reading = TextDirection.ltr,
  }) => Directionality(
    textDirection: reading,
    child: PageView(
      controller: controller,
      onPageChanged: onPageChanged,
      scrollDirection: axis,
      reverse: reverse,
      physics: physics,
      children: const [Text('Page 0'), Text('Page 1'), Text('Page 2')],
    ),
  );

  test('shows its first page, and the controller\'s initial one', () {
    expect(AppTester.widget(pages()).hasText('Page 0'), isTrue);
    expect(
      AppTester.widget(
        pages(controller: PageController(initialPage: 2)),
      ).hasText('Page 2'),
      isTrue,
    );
  });

  test('a swipe towards the start shows the next page, and says so', () async {
    final changed = <int>[];
    final app = AppTester.widget(pages(onPageChanged: changed.add));

    await swipe(app, -200);

    expect(app.hasText('Page 1'), isTrue);
    expect(app.hasText('Page 0'), isFalse);
    expect(changed, [1]);
  });

  test('there is nothing before the first page or after the last', () async {
    final changed = <int>[];
    final app = AppTester.widget(pages(onPageChanged: changed.add));

    await swipe(app, 200);
    expect(app.hasText('Page 0'), isTrue);
    await swipe(app, -200);
    await swipe(app, -200);
    await swipe(app, -200);

    expect(app.hasText('Page 2'), isTrue);
    expect(changed, [1, 2]);
  });

  test('the controller shows a page, and knows which is showing', () async {
    final controller = PageController();
    var heard = 0;
    controller.addListener(() => heard++);
    final app = AppTester.widget(pages(controller: controller));
    expect(controller.hasClients, isTrue);

    controller.jumpToPage(2);
    await Future<void>.delayed(Duration.zero);
    expect(app.hasText('Page 2'), isTrue);
    expect(controller.page, 2);

    await controller.previousPage(
      duration: const Duration(milliseconds: 200),
      curve: Curves.ease,
    );
    await Future<void>.delayed(Duration.zero);
    expect(app.hasText('Page 1'), isTrue);

    await swipe(app, 200);
    expect(controller.page, 0);
    // Held to the pages there are.
    controller.jumpToPage(9);
    expect(controller.page, 2);
    expect(heard, 4);
  });

  test('a vertical one is swiped up and down', () async {
    final app = AppTester.widget(pages(axis: Axis.vertical));
    expect(swiped(app), isNull);

    await swipe(app, -200, vertical: true);

    expect(app.hasText('Page 1'), isTrue);
  });

  test('reverse, and a screen read from the right, each turn it round',
      () async {
    var app = AppTester.widget(pages(reverse: true));
    await swipe(app, 200);
    expect(app.hasText('Page 1'), isTrue);

    app = AppTester.widget(pages(reading: TextDirection.rtl));
    await swipe(app, 200);
    expect(app.hasText('Page 1'), isTrue);
  });

  test('physics that never scroll leave it to the controller', () async {
    final controller = PageController();
    final app = AppTester.widget(
      pages(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
      ),
    );
    expect(swiped(app), isNull);

    controller.jumpToPage(1);
    await Future<void>.delayed(Duration.zero);

    expect(app.hasText('Page 1'), isTrue);
  });

  test('a page keeps its State while another is in front', () async {
    final app = AppTester.widget(
      PageView(
        children: const [_Counter(), Text('Other')],
      ),
    );
    await app.tap('bump');
    await app.tap('bump');
    expect(app.text('count'), '2');

    await swipe(app, -200);
    expect(app.hasText('Other'), isTrue);
    await swipe(app, 200);

    expect(app.text('count'), '2');
  });

  test('PageView.builder builds the page showing, and ends where it says',
      () async {
    final built = <int>[];
    final app = AppTester.widget(
      PageView.builder(
        itemCount: 2,
        itemBuilder: (context, index) {
          built.add(index);
          return Text('Built $index');
        },
      ),
    );
    expect(built.toSet(), {0});

    await swipe(app, -200);
    await swipe(app, -200);

    expect(app.hasText('Built 1'), isTrue);
    expect(built.toSet(), {0, 1});
  });

  test('a builder with no count ends where it has no page to give', () async {
    final app = AppTester.widget(
      PageView.builder(
        itemBuilder: (context, index) => index < 2 ? Text('Built $index') : null,
      ),
    );

    await swipe(app, -200);
    await swipe(app, -200);

    expect(app.hasText('Built 1'), isTrue);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$_count', key: const ValueKey('count')),
      TextButton(
        key: const ValueKey('bump'),
        onPressed: () => setState(() => _count++),
        child: const Text('Bump'),
      ),
    ],
  );
}
