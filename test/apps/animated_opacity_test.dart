/// A fade, through the widget layer.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

class _Banner extends StatefulWidget {
  const _Banner();

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  bool visible = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            AnimatedOpacity(
              key: const ValueKey('banner'),
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: const Text('Saved', key: ValueKey('label')),
            ),
            ElevatedButton(
              key: const ValueKey('toggle'),
              onPressed: () => setState(() => visible = !visible),
              child: const Text('Toggle'),
            ),
          ],
        ),
      );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Banner())));

  WidgetNode fade() => tester.ofType('AnimatedOpacity').single;

  test('carries the opacity it is at and how long a change takes', () {
    expect(fade().props['opacity'], 0.0);
    expect(fade().props['durationMs'], 300);
  });

  test('the child rides along inside it', () {
    expect(fade().children, hasLength(1));
    expect(fade().children!.single.props['content'], 'Saved');
  });

  test('a change is a new opacity in the tree, not an instruction', () async {
    await tester.tap('toggle');

    // The tree says what the screen is; the renderers animate the difference
    // from what it was.
    expect(fade().props['opacity'], 1.0);
    expect(fade().props['durationMs'], 300);
  });
}
