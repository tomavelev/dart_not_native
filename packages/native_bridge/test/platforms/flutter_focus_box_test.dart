/// Widget test for a `Focus` box in the Flutter renderer: Flutter's own
/// focus, asked for by `focusVersion` and reported by `focusEventId`.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;
  final said = <bool>[];

  setUp(() {
    renderer = FlutterUIRenderer();
    said.clear();
    renderer.onEvent('f', (data) => said.add(data['focused'] == true));
  });

  WidgetNode focus({int? version, bool? requested}) {
    final box = UIBuilder.box(child: UIBuilder.text('inside'));
    return WidgetNode(
      type: box.type,
      props: {
        ...box.props,
        'focusEventId': 'f',
        'focusable': true,
        'focusVersion': ?version,
        'focusRequested': ?requested,
      },
      children: box.children,
    );
  }

  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Builder(builder: renderer.build))),
    );
    await tester.pump();
  }

  testWidgets('takes focus when asked, says so, and gives it up', (
    tester,
  ) async {
    await show(tester, focus());
    expect(said, isEmpty);
    await show(tester, focus(version: 1));
    expect(said, [true]);
    await show(tester, focus(version: 2, requested: false));
    expect(said, [true, false]);
  });
}
