/// `AnimatedSize.onEnd`: the box asks to be told when a move to its child's
/// size has got there, and the answer calls it.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onEnd is called when the renderer says the move got there', () async {
    var ended = 0;
    final app = AppTester.widget(
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        onEnd: () => ended++,
        child: const Text('hi'),
      ),
    );
    final box = app.nodes.firstWhere((n) => n.props['animateSize'] == true);
    final id = box.props['sizeEndEventId'] as String;

    await app.emit(id, const {});

    expect(ended, 1);
  });

  test('with no onEnd there is nothing to ask', () {
    final app = AppTester.widget(
      const AnimatedSize(
        duration: Duration(milliseconds: 300),
        child: Text('hi'),
      ),
    );
    final box = app.nodes.firstWhere((n) => n.props['animateSize'] == true);
    expect(box.props.containsKey('sizeEndEventId'), isFalse);
  });
}
