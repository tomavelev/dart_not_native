/// Handing a subtree a value, rather than threading it through constructors.
library;

import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

class _Config extends InheritedWidget {
  const _Config({required this.apiUrl, required super.child});

  final String apiUrl;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Config>()?.apiUrl ?? 'none';

  @override
  bool updateShouldNotify(_Config oldWidget) => oldWidget.apiUrl != apiUrl;
}

/// Reads whatever is above it, wherever it is put.
class _Reader extends StatelessWidget {
  const _Reader(this.id);

  final String id;

  @override
  Widget build(BuildContext context) =>
      Text(_Config.of(context), key: ValueKey(id));
}

class _Screen extends StatelessWidget {
  const _Screen({this.url = 'https://api.example.com'});

  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            _Config(
              apiUrl: url,
              child: Column(
                children: [
                  const _Reader('inside'),
                  // The nearest one wins, as in Flutter.
                  const _Config(
                    apiUrl: 'https://inner.example.com',
                    child: _Reader('nested'),
                  ),
                ],
              ),
            ),
            const _Reader('outside'),
          ],
        ),
      );
}

class _Themed extends StatelessWidget {
  const _Themed();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Text(Theme.of(context).primary, key: const ValueKey('primary')),
      );
}

void main() {
  test('a value reaches everything built below it', () {
    final tester = AppTester.mount(hostApp(const _Screen()));

    expect(tester.text('inside'), 'https://api.example.com');
  });

  test('and nothing built beside it', () {
    final tester = AppTester.mount(hostApp(const _Screen()));

    expect(tester.text('outside'), 'none');
  });

  test('the nearest one wins', () {
    final tester = AppTester.mount(hostApp(const _Screen()));

    expect(tester.text('nested'), 'https://inner.example.com');
  });

  test('a new value reaches the subtree on the next build', () {
    final tester = AppTester.mount(hostApp(const _Screen(url: 'one')));
    expect(tester.text('inside'), 'one');

    // Mounting again stands in for the app rebuilding with a different value;
    // the framework rebuilds from the root either way.
    final next = AppTester.mount(hostApp(const _Screen(url: 'two')));

    expect(next.text('inside'), 'two');
  });

  group('Theme', () {
    test('is at the root, so any screen can read the palette', () {
      final tester = AppTester.mount(
        hostApp(const _Themed(), theme: const AppTheme(primary: '#ff0000')),
      );

      expect(tester.text('primary'), '#ff0000');
    });

    test('falls back rather than being absent', () {
      // An app that declared no theme still reads colours, which is what lets
      // a widget use Theme.of without asking whether anyone set one.
      final tester = AppTester.mount(hostApp(const _Themed()));

      expect(tester.text('primary'), AppTheme.fallback.primary);
    });
  });
}
