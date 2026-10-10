/// A box that grows and changes colour, through the widget layer.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _Chip extends StatefulWidget {
  const _Chip();

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool open = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            AnimatedContainer(
              key: const ValueKey('chip'),
              width: open ? 300 : 80,
              height: 64,
              color: open ? Colors.blue : Colors.grey,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: const Text('Tap', key: ValueKey('label')),
            ),
            ElevatedButton(
              key: const ValueKey('toggle'),
              onPressed: () => setState(() => open = !open),
              child: const Text('Toggle'),
            ),
          ],
        ),
      );
}

/// A screen that is nothing but the widget under test.
class _Wrapper extends StatelessWidget {
  const _Wrapper(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(body: child);
}

/// The node one [AnimatedContainer] renders to, on its own: a box that says
/// how long a change to it should take.
WidgetNode boxOf(AnimatedContainer box) => AppTester.mount(
  hostApp(_Wrapper(box)),
).ofType('Box').singleWhere((node) => node.props.containsKey('animateMs'));

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Chip())));

  WidgetNode box() => tester.get('chip');

  test('carries the size, the colour, the duration and the curve', () {
    expect(box().props['width'], 80.0);
    expect(box().props['height'], 64.0);
    expect(box().props['color'], '#9e9e9e');
    expect(box().type, 'Box');
    expect(box().props['animateMs'], 300);
    expect(box().props['curve'], 'easeOut');
  });

  test('the child rides along inside it', () {
    expect(box().children, hasLength(1));
    expect(box().children!.single.props['content'], 'Tap');
  });

  test('a change is a new size in the tree, not an instruction', () async {
    await tester.tap('toggle');

    // As with the fade: the tree says what the box *is*, and each renderer
    // moves from whatever it was showing.
    expect(box().props['width'], 300.0);
    expect(box().props['color'], '#2196f3');
  });

  test('a dimension left out is left out of the node', () {
    final node = boxOf(
      AnimatedContainer(
        height: 40,
        duration: const Duration(milliseconds: 200),
        child: const Text('x'),
      ),
    );

    expect(node.props.containsKey('width'), isFalse);
    expect(node.props['height'], 40.0);
    // The default curve is Flutter's, and it is named, so a renderer never
    // has to guess.
    expect(node.props['curve'], 'linear');
    expect(node.props['animateMs'], 200);
  });

  test('a fade carries a curve too', () {
    final node = AppTester.mount(
      hostApp(
        const _Wrapper(
          AnimatedOpacity(
            opacity: 0.5,
            curve: Curves.easeIn,
            duration: Duration(milliseconds: 200),
            child: Text('x'),
          ),
        ),
      ),
    ).ofType('AnimatedOpacity').single;

    expect(node.props['curve'], 'easeIn');
  });
}
