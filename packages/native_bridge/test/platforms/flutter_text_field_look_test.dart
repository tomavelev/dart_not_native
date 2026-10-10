/// A text field's look, drawn by the Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const green = Color(0xFF2E7D32);
const cream = Color(0xFFFFF8E1);

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());
  tearDown(() => renderer.dispose());

  Future<TextField> show(
    WidgetTester tester,
    Map<String, dynamic> props,
  ) async {
    await renderer.render(
      UIBuilder.scaffold(
        body: WidgetNode(
          type: 'TextField',
          props: {'eventId': 'e', 'hint': 'Hint', ...props},
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
    return tester.widget<TextField>(find.byType(TextField));
  }

  testWidgets('a field that says nothing is the outlined box it was', (
    tester,
  ) async {
    final field = await show(tester, {});

    expect(field.style, isNull);
    expect(field.decoration!.border, isA<OutlineInputBorder>());
    expect(field.decoration!.filled, isFalse);
  });

  testWidgets('what is typed takes its colour, size and weight', (
    tester,
  ) async {
    final field = await show(tester, {
      'textColor': '#2e7d32',
      'fontSize': 20,
      'fontWeight': 600,
    });

    expect(field.style!.color, green);
    expect(field.style!.fontSize, 20);
    expect(field.style!.fontWeight, FontWeight.w600);
  });

  testWidgets('a fill', (tester) async {
    final field = await show(tester, {'fillColor': '#fff8e1'});

    expect(field.decoration!.filled, isTrue);
    expect(field.decoration!.fillColor, cream);
  });

  testWidgets('no outline', (tester) async {
    final field = await show(tester, {'border': 'none'});

    expect(field.decoration!.border, InputBorder.none);
  });

  testWidgets('an underline', (tester) async {
    final field = await show(tester, {'border': 'underline'});

    expect(field.decoration!.border, isA<UnderlineInputBorder>());
  });

  testWidgets('a box in the colour, width and radius it was given, at rest '
      'and with the caret in it', (tester) async {
    final field = await show(tester, {
      'border': 'outline',
      'borderColor': '#2e7d32',
      'borderWidth': 2,
      'borderRadius': 12,
    });

    for (final border in [
      field.decoration!.border,
      field.decoration!.enabledBorder,
      field.decoration!.focusedBorder,
    ]) {
      final box = border! as OutlineInputBorder;
      expect(box.borderSide.color, green);
      expect(box.borderSide.width, 2);
      expect(box.borderRadius, BorderRadius.circular(12));
    }
  });

  testWidgets('the room inside', (tester) async {
    final field = await show(tester, {
      'contentPadding': [20, 8, 4, 6],
    });

    expect(
      field.decoration!.contentPadding,
      const EdgeInsets.fromLTRB(20, 8, 4, 6),
    );
  });
}
