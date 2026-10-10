/// Text that does not fit: how many lines it may take, and what happens to
/// the rest.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _Screen extends StatelessWidget {
  const _Screen(this.text);

  final Text text;

  @override
  Widget build(BuildContext context) => Scaffold(body: text);
}

WidgetNode nodeOf(Text text) =>
    AppTester.mount(hostApp(_Screen(text))).ofType('Text').single;

void main() {
  test('text that says nothing about fitting carries nothing', () {
    final node = nodeOf(const Text('A long line'));

    expect(node.props.containsKey('maxLines'), isFalse);
    expect(node.props.containsKey('overflow'), isFalse);
  });

  test('a line cap travels as a number', () {
    expect(nodeOf(const Text('x', maxLines: 2)).props['maxLines'], 2);
  });

  test('an overflow without a cap is one line, as in Flutter', () {
    final node = nodeOf(
      const Text('x', overflow: TextOverflow.ellipsis),
    );

    expect(node.props['maxLines'], 1);
    expect(node.props['overflow'], 'ellipsis');
  });

  test('clipping is the other answer, and says so', () {
    final node = nodeOf(
      const Text('x', maxLines: 3, overflow: TextOverflow.clip),
    );

    expect(node.props['maxLines'], 3);
    expect(node.props['overflow'], 'clip');
  });
}
