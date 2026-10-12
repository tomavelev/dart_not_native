/// `ScrollController.animateTo` asks the renderer to travel to the offset;
/// `jumpTo` asks it to be there.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScrollController controller;
  late AppTester app;

  Map<String, dynamic> scroller() => app.ofType('Scroll').single.props;

  setUp(() {
    controller = ScrollController();
    app = AppTester.widget(
      Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [for (var i = 0; i < 80; i++) Text('row $i')],
          ),
        ),
      ),
    );
  });

  test('animateTo says to travel there', () async {
    final before = scroller()['scrollVersion'] as int;
    final done = controller.animateTo(
      400,
      duration: const Duration(milliseconds: 40),
      curve: Curves.easeOut,
    );
    await pumpEventQueue();

    expect(scroller()['scrollOffset'], 400);
    expect(scroller()['scrollVersion'], before + 1);
    expect(scroller()['scrollAnimated'], isTrue);
    expect(controller.offset, 400);
    await done;
  });

  test('its future takes the duration', () async {
    var finished = false;
    controller
        .animateTo(
          400,
          duration: const Duration(milliseconds: 60),
          curve: Curves.easeOut,
        )
        .then((_) => finished = true);
    await pumpEventQueue();
    expect(finished, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(finished, isTrue);
  });

  test('jumpTo says nothing of travelling, even after an animateTo', () async {
    await controller.animateTo(
      400,
      duration: const Duration(milliseconds: 10),
      curve: Curves.easeOut,
    );
    controller.jumpTo(100);
    await pumpEventQueue();

    expect(scroller()['scrollOffset'], 100);
    expect(scroller().containsKey('scrollAnimated'), isFalse);
  });

  test('no time is a jump', () async {
    await controller.animateTo(400, duration: Duration.zero, curve: Curves.ease);
    await pumpEventQueue();

    expect(scroller().containsKey('scrollAnimated'), isFalse);
  });

  test('a windowed list is told too', () async {
    final listController = ScrollController();
    app = AppTester.widget(
      Scaffold(
        body: ListView.builder(
          controller: listController,
          itemCount: 1000,
          itemExtent: 48,
          itemBuilder: (context, index) => Text('row $index'),
        ),
      ),
    );

    final done = listController.animateTo(
      960,
      duration: const Duration(milliseconds: 20),
      curve: Curves.easeOut,
    );
    await pumpEventQueue();

    expect(app.ofType('LazyList').single.props['scrollAnimated'], isTrue);
    await done;
  });
}
