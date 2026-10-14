/// `animateTo` tells the renderer how long the scroll takes and along what.
library;

import 'dart:async';

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a travel says its duration and curve; a jump says neither', () async {
    final controller = ScrollController();
    final app = AppTester.widget(
      ListView(
        controller: controller,
        children: [for (var i = 0; i < 50; i++) Text('Row $i')],
      ),
    );
    unawaited(
      controller.animateTo(
        400,
        duration: const Duration(milliseconds: 700),
        curve: Curves.fastOutSlowIn,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final scroll = app.ofType('Scroll').single.props;
    expect(scroll['scrollAnimated'], isTrue);
    expect(scroll['scrollMs'], 700);
    expect(scroll['scrollCurve'], 'cubic(0.4,0.0,0.2,1.0)');

    controller.jumpTo(10);
    await Future<void>.delayed(Duration.zero);
    final jumped = app.ofType('Scroll').single.props;
    expect(jumped.containsKey('scrollAnimated'), isFalse);
    expect(jumped.containsKey('scrollMs'), isFalse);
  });
}
