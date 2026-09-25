/// Asking for the keyboard: at first render, and later on.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

class _Screen extends StatefulWidget {
  const _Screen();

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  final search = FocusNode();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            TextField(
              key: const ValueKey('search'),
              focusNode: search,
              decoration: const InputDecoration(hintText: 'Search'),
            ),
            TextField(
              key: const ValueKey('other'),
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Other'),
            ),
            ElevatedButton(
              key: const ValueKey('focus'),
              onPressed: () => setState(search.requestFocus),
              child: const Text('Focus search'),
            ),
            ElevatedButton(
              key: const ValueKey('dismiss'),
              onPressed: () => setState(search.unfocus),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Screen())));

  WidgetNode field(String id) => tester.get(id);

  test('a field that says nothing about focus asks for nothing', () {
    expect(field('search').props.containsKey('autofocus'), isFalse);
    expect(field('search').props.containsKey('focusVersion'), isFalse);
  });

  test('autofocus travels as a flag the renderer acts on once', () {
    expect(field('other').props['autofocus'], isTrue);
  });

  test('asking for the keyboard bumps a version', () async {
    await tester.tap('focus');

    expect(field('search').props['focusVersion'], 1);
    expect(field('search').props.containsKey('focusRequested'), isFalse);
  });

  test('asking twice is two asks, not one state', () async {
    await tester.tap('focus');
    await tester.tap('focus');

    expect(field('search').props['focusVersion'], 2);
  });

  test('giving it up is the same version, the other way', () async {
    await tester.tap('focus');
    await tester.tap('dismiss');

    expect(field('search').props['focusVersion'], 2);
    expect(field('search').props['focusRequested'], isFalse);
  });
}
