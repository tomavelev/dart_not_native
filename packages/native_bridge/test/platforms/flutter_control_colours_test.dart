/// The colours an app gives one control, drawn by the Flutter renderer.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const green = Color(0xFF2E7D32);
const pink = Color(0xFFE91E63);
const grey = Color(0xFF9E9E9E);

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());
  tearDown(() => renderer.dispose());

  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
  }

  WidgetNode node(String type, Map<String, dynamic> props) =>
      WidgetNode(type: type, props: {'eventId': 'e', ...props});

  testWidgets('a checkbox takes its fill and its tick', (tester) async {
    await show(
      tester,
      node('Checkbox', {
        'checked': true,
        'activeColor': '#2e7d32',
        'checkColor': '#e91e63',
      }),
    );

    final box = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(box.activeColor, green);
    expect(box.checkColor, pink);
  });

  testWidgets('a radio that is chosen takes its colour, and one that is not '
      'does not', (tester) async {
    await show(
      tester,
      UIBuilder.column(
        children: [
          node('Radio', {
            'value': 'a',
            'selected': true,
            'activeColor': '#2e7d32',
          }),
          node('Radio', {
            'value': 'b',
            'selected': false,
            'activeColor': '#2e7d32',
          }),
        ],
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.radio_button_checked)).color,
      green,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.radio_button_unchecked)).color,
      isNot(green),
    );
  });

  testWidgets('a switch is its colour when on, under a white thumb', (
    tester,
  ) async {
    await show(
      tester,
      node('Toggle', {'enabled': true, 'activeColor': '#2e7d32'}),
    );

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.activeTrackColor, green);
    expect(toggle.activeThumbColor, Colors.white);
  });

  testWidgets('a switch takes the thumb and the off colours it is given', (
    tester,
  ) async {
    await show(
      tester,
      node('Toggle', {
        'enabled': true,
        'activeColor': '#2e7d32',
        'thumbColor': '#e91e63',
        'inactiveTrackColor': '#9e9e9e',
        'inactiveThumbColor': '#2e7d32',
      }),
    );

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.activeThumbColor, pink);
    expect(toggle.inactiveTrackColor, grey);
    expect(toggle.inactiveThumbColor, green);
  });

  testWidgets('a slider takes its three', (tester) async {
    await show(
      tester,
      node('Slider', {
        'value': 0.5,
        'activeColor': '#2e7d32',
        'inactiveColor': '#9e9e9e',
        'thumbColor': '#e91e63',
      }),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.activeColor, green);
    expect(slider.inactiveColor, grey);
    expect(slider.thumbColor, pink);
  });

  testWidgets('a floating button takes what it is and what is on it', (
    tester,
  ) async {
    await show(
      tester,
      UIBuilder.scaffold(
        body: UIBuilder.text('x'),
        floatingActionButton: node('FloatingActionButton', {
          'tooltip': 'Add',
          'icon': 'add',
          'backgroundColor': '#2e7d32',
          'foregroundColor': '#e91e63',
        }),
      ),
    );

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.backgroundColor, green);
    expect(fab.foregroundColor, pink);
  });

  testWidgets('a control given none is the brand\'s, as before', (
    tester,
  ) async {
    await show(tester, node('Checkbox', {'checked': true}));
    final plain = tester.widget<Checkbox>(find.byType(Checkbox)).activeColor;

    expect(plain, isNotNull);
    expect(plain, isNot(green));
  });
}
