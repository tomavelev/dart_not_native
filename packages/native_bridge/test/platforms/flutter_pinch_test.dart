/// Widget test for a pan that hears a second finger (`panScale`) in the
/// Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('two fingers spreading say how far', (tester) async {
    final renderer = FlutterUIRenderer();
    final said = <Map<String, dynamic>>[];
    for (final phase in const ['start', 'update', 'end']) {
      renderer.onEvent(
        'pan_$phase',
        (data) => said.add({'phase': phase, ...data}),
      );
    }
    await renderer.render(
      const WidgetNode(
        type: 'Box',
        props: {
          'width': 300,
          'height': 300,
          'color': '#eeeeee',
          'panEventId': 'pan',
          'panScale': true,
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: Builder(builder: renderer.build),
        ),
      ),
    );

    final one = await tester.startGesture(const Offset(100, 150));
    final two = await tester.startGesture(const Offset(200, 150), pointer: 2);
    await tester.pump();
    await one.moveTo(const Offset(50, 150));
    await two.moveTo(const Offset(250, 150));
    await tester.pump();
    await one.up();
    await two.up();
    await tester.pump();

    final updates = said.where((e) => e['phase'] == 'update').toList();
    expect(said.first['phase'], 'start');
    expect(said.last['phase'], 'end');
    expect(updates.last['scale'], closeTo(2.0, 0.01));
    expect(updates.last['pointers'], 2);
    expect(updates.last['x'], closeTo(150, 0.5));
    expect(updates.last['rotation'], closeTo(0, 0.01));
  });
}
