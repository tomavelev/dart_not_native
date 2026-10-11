/// `ElevatedButton` under each Material. It was a filled primary button under
/// both, where Flutter's Material 3 draws the surface, raised, with the
/// primary for its label.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _in(ThemeData theme, Widget child) =>
    MaterialApp(theme: theme, home: Scaffold(body: child));

void main() {
  Map<String, dynamic> button(AppTester app) =>
      app.ofType('Button').single.props;

  test('under Material 3 it is the elevated button', () {
    final app = AppTester.widget(
      _in(
        ThemeData(),
        ElevatedButton(onPressed: () {}, child: const Text('Save')),
      ),
    );

    expect(button(app)['variant'], 'elevated');
  });

  test('under Material 2 it is the filled primary', () {
    final app = AppTester.widget(
      _in(
        ThemeData(useMaterial3: false),
        ElevatedButton(onPressed: () {}, child: const Text('Save')),
      ),
    );

    expect(button(app)['variant'], 'primary');
  });

  test('one given a fill is filled with it', () {
    final app = AppTester.widget(
      _in(
        ThemeData(),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
          ),
          child: const Text('Save'),
        ),
      ),
    );

    expect(button(app)['variant'], 'primary');
    expect(button(app)['color'], '#2e7d32');
  });

  test('a filled button is still the filled primary', () {
    final app = AppTester.widget(
      _in(
        ThemeData(),
        FilledButton(onPressed: () {}, child: const Text('Save')),
      ),
    );

    expect(button(app)['variant'], 'primary');
  });

  test('drawn from a box, it is the surface with a shadow', () {
    // A shape of its own makes it a box, which has to say the colours itself.
    final theme = ThemeData();
    final app = AppTester.widget(
      _in(
        theme,
        ElevatedButton(
          key: const ValueKey('save'),
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
          ),
          child: const Text('Save'),
        ),
      ),
    );
    final box = app.get('save').props;

    expect(box['color'], isNot(isNull));
    expect(box['shadow'], isA<Map>());
    expect(app.ofType('Text').last.props['color'], isNot('#ffffff'));
  });

  test('the theme says which Material it is, for a renderer to read', () {
    expect(ThemeData().toAppTheme().material3, isTrue);
    expect(ThemeData(useMaterial3: false).toAppTheme().material3, isFalse);
  });
}
