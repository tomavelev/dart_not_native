/// A windowed list says where it is in pixels, so a `ScrollController` on
/// one follows the reader and the list comes back where it was. It used to
/// report rows and nothing finer: the controller heard the app's own moves
/// only.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _list({ScrollController? controller}) => ListView.builder(
  controller: controller,
  itemCount: 500,
  itemExtent: 48,
  itemBuilder: (context, index) => Text('Row $index'),
);

void main() {
  Map<String, dynamic> list(AppTester app) =>
      app.ofType('LazyList').single.props;

  test('a controller on a windowed list follows the reader', () async {
    final controller = ScrollController();
    var heard = 0;
    controller.addListener(() => heard++);
    final app = AppTester.widget(_list(controller: controller));

    await app.emit(list(app)['scrollEventId'] as String, {
      'offset': 960.0,
      'maxExtent': 23200.0,
      'viewport': 800.0,
    });

    expect(controller.offset, 960);
    expect(controller.position.maxScrollExtent, 23200);
    expect(heard, 1);
  });

  test('being told where it is does not send it anywhere', () async {
    final controller = ScrollController();
    final app = AppTester.widget(_list(controller: controller));
    expect(list(app).containsKey('scrollOffset'), isFalse);

    await app.emit(list(app)['scrollEventId'] as String, {'offset': 960.0});

    expect(list(app).containsKey('scrollOffset'), isFalse);
  });

  test('a jump is still a jump, to a new version', () async {
    final controller = ScrollController();
    final app = AppTester.widget(_list(controller: controller));
    await app.emit(list(app)['scrollEventId'] as String, {'offset': 960.0});

    controller.jumpTo(0);
    await Future<void>.delayed(Duration.zero);

    expect(list(app)['scrollOffset'], 0);
    expect(list(app)['scrollVersion'], 1);
  });

  test('a list with no controller says where it is all the same', () {
    final app = AppTester.widget(_list());

    expect(list(app)['scrollEventId'], isA<String>());
  });

  test('a list behind another tab comes back where it was', () async {
    final app = AppTester.widget(
      DefaultTabController(
        length: 2,
        child: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                key: const ValueKey('other'),
                onPressed: () => DefaultTabController.of(context).index = 1,
                child: const Text('Other'),
              ),
              TextButton(
                key: const ValueKey('back'),
                onPressed: () => DefaultTabController.of(context).index = 0,
                child: const Text('Back'),
              ),
              Expanded(
                child: TabBarView(children: [_list(), const Text('Other tab')]),
              ),
            ],
          ),
        ),
      ),
    );
    // Nothing to go back to yet.
    expect(list(app).containsKey('scrollOffset'), isFalse);
    await app.emit(list(app)['scrollEventId'] as String, {'offset': 960.0});

    await app.tap('other');
    expect(app.ofType('LazyList'), isEmpty);
    await app.tap('back');

    // Sent back to where the reader left it, as a new ask: a renderer that
    // made the list's view again would otherwise start it at the top.
    expect(list(app)['scrollOffset'], 960);
    expect(list(app)['scrollVersion'], greaterThan(0));
  });
}
