/// The colours an app gives one control - `activeColor` and the rest - on
/// their way to a renderer. The widgets accepted them and sent none, so
/// every control was the theme's primary.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const green = Color(0xFF2E7D32);
const pink = Color(0xFFE91E63);
const grey = Color(0xFF9E9E9E);
const translucent = Color(0x802E7D32);

void main() {
  Map<String, dynamic> props(Widget control, String type) => AppTester.widget(
    Scaffold(body: control),
  ).ofType(type).single.props;

  group('a control that is given no colour', () {
    test('sends none, and is the renderer\'s to colour', () {
      const names = [
        'activeColor',
        'checkColor',
        'thumbColor',
        'inactiveColor',
        'inactiveTrackColor',
        'inactiveThumbColor',
        'backgroundColor',
        'foregroundColor',
      ];
      final sent = [
        props(Checkbox(value: true, onChanged: (_) {}), 'Checkbox'),
        props(
          Radio<int>(value: 1, groupValue: 1, onChanged: (_) {}),
          'Radio',
        ),
        props(Switch(value: true, onChanged: (_) {}), 'Toggle'),
        props(Slider(value: 0.5, onChanged: (_) {}), 'Slider'),
      ];
      for (final control in sent) {
        expect(control.keys.where(names.contains), isEmpty);
      }
    });
  });

  test('Checkbox sends its fill and its tick', () {
    final sent = props(
      Checkbox(
        value: true,
        activeColor: green,
        checkColor: pink,
        onChanged: (_) {},
      ),
      'Checkbox',
    );

    expect(sent['activeColor'], '#2e7d32');
    expect(sent['checkColor'], '#e91e63');
  });

  test('Radio sends the colour it is when chosen', () {
    final sent = props(
      Radio<int>(
        value: 1,
        groupValue: 1,
        activeColor: green,
        onChanged: (_) {},
      ),
      'Radio',
    );

    expect(sent['activeColor'], '#2e7d32');
  });

  group('Switch', () {
    test('activeColor is the colour it is when on', () {
      final sent = props(
        Switch(value: true, activeColor: green, onChanged: (_) {}),
        'Toggle',
      );

      expect(sent['activeColor'], '#2e7d32');
      expect(sent.containsKey('thumbColor'), isFalse);
    });

    test('activeTrackColor says the same thing more exactly, and wins', () {
      final sent = props(
        Switch(
          value: true,
          activeColor: pink,
          activeTrackColor: green,
          onChanged: (_) {},
        ),
        'Toggle',
      );

      expect(sent['activeColor'], '#2e7d32');
    });

    test('the thumb and the two off colours travel too', () {
      final sent = props(
        Switch(
          value: false,
          activeThumbColor: pink,
          inactiveTrackColor: grey,
          inactiveThumbColor: green,
          onChanged: (_) {},
        ),
        'Toggle',
      );

      expect(sent['thumbColor'], '#e91e63');
      expect(sent['inactiveTrackColor'], '#9e9e9e');
      expect(sent['inactiveThumbColor'], '#2e7d32');
    });
  });

  test('Slider sends its three', () {
    final sent = props(
      Slider(
        value: 0.5,
        activeColor: green,
        inactiveColor: grey,
        thumbColor: pink,
        onChanged: (_) {},
      ),
      'Slider',
    );

    expect(sent['activeColor'], '#2e7d32');
    expect(sent['inactiveColor'], '#9e9e9e');
    expect(sent['thumbColor'], '#e91e63');
  });

  test('FloatingActionButton sends what it is and what is on it', () {
    final sent = AppTester.widget(
      Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          backgroundColor: green,
          foregroundColor: pink,
          child: const Icon(Icons.add),
        ),
        body: const Text('x'),
      ),
    ).ofType('FloatingActionButton').single.props;

    expect(sent['backgroundColor'], '#2e7d32');
    expect(sent['foregroundColor'], '#e91e63');
  });

  test('a colour that is not opaque keeps its alpha', () {
    final sent = props(
      Switch(value: true, activeColor: translucent, onChanged: (_) {}),
      'Toggle',
    );

    expect(sent['activeColor'], '#802e7d32');
  });

  test('the list tiles pass theirs to the control inside', () {
    final tester = AppTester.widget(
      Scaffold(
        body: Column(
          children: [
            CheckboxListTile(
              title: const Text('Terms'),
              value: true,
              activeColor: green,
              onChanged: (_) {},
            ),
            SwitchListTile(
              title: const Text('Alerts'),
              value: true,
              activeColor: green,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );

    expect(tester.ofType('Checkbox').single.props['activeColor'], '#2e7d32');
    expect(tester.ofType('Toggle').single.props['activeColor'], '#2e7d32');
  });
}
