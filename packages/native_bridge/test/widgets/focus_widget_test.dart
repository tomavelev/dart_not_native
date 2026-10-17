/// `Focus`: a box that can take the keyboard's focus, asked for through its
/// node and told back to it and to `onFocusChange`.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('is a box that can take focus, and asks for it through its node',
      () async {
    final node = FocusNode();
    final changes = <bool>[];
    final tester = AppTester.widget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            focusNode: node,
            onFocusChange: changes.add,
            child: ElevatedButton(onPressed: () {}, child: const Text('go')),
          ),
        ),
      ),
    );
    WidgetNode box() =>
        tester.ofType('Box').firstWhere((n) => n.props['focusEventId'] != null);
    expect(box().props['focusable'], isTrue);
    expect(box().props.containsKey('focusVersion'), isFalse);

    node.requestFocus();
    await pumpEventQueue();
    expect(box().props['focusVersion'], 1);

    final eventId = box().props['focusEventId'] as String;
    await tester.emit(eventId, {'focused': true});
    expect(node.hasFocus, isTrue);
    await tester.emit(eventId, {'focused': false});
    expect(node.hasFocus, isFalse);
    expect(changes, [true, false]);

    node.unfocus();
    await pumpEventQueue();
    expect(box().props['focusRequested'], isFalse);
  });

  test('is passed over by Tab with skipTraversal, and no stop at all when '
      'it cannot take focus', () {
    WidgetNode boxOf(Widget focus) => AppTester.widget(
      MaterialApp(home: Scaffold(body: focus)),
    ).ofType('Box').firstWhere((n) => n.props['focusEventId'] != null);

    final passedOver = boxOf(
      const Focus(skipTraversal: true, child: Text('a')),
    );
    expect(passedOver.props['focusSkip'], isTrue);
    expect(
      boxOf(const Focus(canRequestFocus: false, child: Text('a')))
          .props
          .containsKey('focusable'),
      isFalse,
    );
  });
}
