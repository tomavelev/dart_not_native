/// Asking for a button of a particular shape, the way Flutter does.
///
/// The design system has three named sizes; a Flutter-shaped app says the same
/// thing with `styleFrom(padding:, minimumSize:, textStyle:)`, and those have
/// to reach the renderers as numbers.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            ElevatedButton(
              key: const ValueKey('plain'),
              onPressed: () {},
              child: const Text('Plain'),
            ),
            ElevatedButton(
              key: const ValueKey('styled'),
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                minimumSize: const Size(96, 28),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('Small'),
            ),
            TextButton(
              key: const ValueKey('flat'),
              onPressed: () {},
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Flat'),
            ),
          ],
        ),
      );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Screen())));

  WidgetNode button(String id) => tester.get(id);

  test('a button with no style is Material 3\'s, as Flutter\'s is', () {
    // 40 tall with 24 either side of the label - stated, because the
    // protocol's own default is the smaller button of its scale.
    final props = button('plain').props;
    expect(props['minHeight'], 40);
    expect(props['paddingHorizontal'], 24);
    // A text button has less beside its label, and keeps what it stated.
    expect(button('flat').props['paddingHorizontal'], 12);
    expect(button('flat').props['minHeight'], 44.0);

    for (final key in ['minWidth', 'fontSize', 'paddingVertical']) {
      expect(props.containsKey(key), isFalse, reason: key);
    }
  });

  test('under a Material 2 theme it says nothing about its shape', () {
    final tester = AppTester.mount(
      hostApp(
        Theme(
          data: ThemeData(useMaterial3: false),
          child: const _Screen(),
        ),
      ),
    );
    final props = tester.get('plain').props;

    for (final key in [
      'minHeight',
      'minWidth',
      'fontSize',
      'paddingHorizontal',
      'paddingVertical',
    ]) {
      expect(props.containsKey(key), isFalse, reason: key);
    }
  });

  test('styleFrom becomes the numbers a renderer draws with', () {
    final props = button('styled').props;

    expect(props['paddingHorizontal'], 12.0);
    expect(props['paddingVertical'], 4.0);
    expect(props['minWidth'], 96.0);
    expect(props['minHeight'], 28.0);
    expect(props['fontSize'], 12.0);
  });

  test('a TextButton is styled the same way', () {
    final props = button('flat').props;

    expect(props['variant'], 'tertiary');
    expect(props['minHeight'], 44.0);
    expect(props.containsKey('fontSize'), isFalse, reason: 'not asked for');
  });
}
