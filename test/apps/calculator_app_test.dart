/// Tests for the calculator example: pure logic plus the mounted app.
library;

import 'package:dart_not_native/widgets.dart' show hostApp;
import 'package:dart_not_native_example/examples/apps/calculator_app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

void main() {
  group('CalculatorLogic', () {
    CalculatorLogic run(String keys) {
      final logic = CalculatorLogic();
      for (final key in keys.split(' ')) {
        logic.press(key);
      }
      return logic;
    }

    test('starts at zero', () {
      expect(CalculatorLogic().display, '0');
    });

    test('arithmetic', () {
      expect(run('7 + 5 =').display, '12');
      expect(run('1 ÷ 4 =').display, '0.25');
      expect(run('6 × 7 =').display, '42');
      expect(run('3 - 9 =').display, '-6');
    });

    test('typing digits replaces the leading zero', () {
      expect(run('4 2').display, '42');
    });

    test('division by zero shows Error', () {
      expect(run('9 ÷ 0 =').display, 'Error');
    });

    test('clear, backspace and decimal', () {
      expect(run('1 2 3 ←').display, '12');
      expect(run('1 2 C').display, '0');
      expect(run('1 . . 5').display, '1.5');
    });

    test('= without an operation leaves the display alone', () {
      expect(run('7 =').display, '7');
    });

    test('chaining reuses the running result', () {
      expect(run('2 + 3 = + 4 =').display, '9');
    });
  });

  group('CalculatorApp', () {
    late AppTester tester;

    setUp(() => tester = AppTester.mount(hostApp(const CalculatorApp())));

    test('renders the display and a full keypad', () {
      expect(tester.text('display'), '0');
      for (final key in ['7', '+', '5', '=', 'C', '←', '.']) {
        expect(
          tester.nodes.any((n) => n.props['label'] == key),
          isTrue,
          reason: 'the keypad is missing "$key"',
        );
      }
    });

    test('pressing keys updates the display', () async {
      // Each button carries its own callback, tapped by its stable id.
      await tester.tap('key_7');
      await tester.tap('key_plus');
      await tester.tap('key_5');
      await tester.tap('key_equals');

      expect(tester.text('display'), '12');
    });

    test('every keypad button carries a callback and taps cleanly', () async {
      final buttons = tester.ofType('Button');
      expect(buttons, isNotEmpty);

      for (final button in buttons) {
        expect(button.props['eventId'], isA<String>());
        // Tapping by the button's own id fires its bound callback.
        await tester.tap(button.props['id'] as String);
      }
      // The keypad ran without a missing handler throwing.
      expect(tester.find('display'), isNotNull);
    });

    test('each press re-renders once', () async {
      var changes = 0;
      final host = hostApp(const CalculatorApp())..onChanged = () => changes++;
      final tester = AppTester(host);

      expect(changes, 1, reason: 'the initial render');
      await tester.tap('key_7');

      expect(changes, 2);
    });

    test('unknown events are reported, not thrown', () async {
      final result = await tester.emit('nope');

      expect(result['success'], isFalse);
    });
  });
}
