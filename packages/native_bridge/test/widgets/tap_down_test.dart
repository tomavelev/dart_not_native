/// A `GestureDetector`'s tap is heard as Flutter's is: `onTapDown` as the
/// finger lands, `onTapUp` and `onTap` as it lifts, `onTapCancel` when it
/// turns out not to be a tap. All three used to fire together after it.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> heard;

  setUp(() => heard = []);

  AppTester pad({bool tap = true}) => AppTester.widget(
    GestureDetector(
      key: const ValueKey('pad'),
      onTapDown: (d) => heard.add('down ${d.localPosition.dx}'),
      onTapUp: (d) => heard.add('up ${d.localPosition.dx}'),
      onTap: tap ? () => heard.add('tap') : null,
      onTapCancel: () => heard.add('cancel'),
      child: const Text('Pad'),
    ),
  );

  String down(AppTester app) =>
      app.get('pad').props['tapDownEventId'] as String;
  String up(AppTester app) => app.get('pad').props['tapEventId'] as String;

  test('down as the finger lands, then up and tap as it lifts', () async {
    final app = pad();
    await app.emit(down(app), {'x': 5.0, 'y': 1.0});
    expect(heard, ['down 5.0']);

    await app.emit(up(app), {'x': 6.0, 'y': 1.0});
    expect(heard, ['down 5.0', 'up 6.0', 'tap']);
  });

  test('a press that is not a tap is cancelled, and nothing else', () async {
    final app = pad();
    await app.emit(down(app), {'x': 5.0, 'y': 1.0});
    await app.emit('${down(app)}_cancel');

    expect(heard, ['down 5.0', 'cancel']);
  });

  test('a cancel with no press, or a second one, says nothing', () async {
    final app = pad();
    await app.emit('${down(app)}_cancel');
    await app.emit(down(app), {'x': 5.0, 'y': 1.0});
    await app.emit(up(app), {'x': 5.0, 'y': 1.0});
    await app.emit('${down(app)}_cancel');

    expect(heard, ['down 5.0', 'up 5.0', 'tap']);
  });

  test('a tap whose down was not reported is told of it first', () async {
    // A press from the keyboard or a screen reader has no pointer going down.
    final app = pad();
    await app.emit(up(app), {'x': 2.0, 'y': 1.0});

    expect(heard, ['down 2.0', 'up 2.0', 'tap']);
  });

  test('with only a down and an up, the up is still heard', () async {
    final app = pad(tap: false);
    await app.emit(down(app), {'x': 1.0, 'y': 1.0});
    await app.emit(up(app), {'x': 1.0, 'y': 1.0});

    expect(heard, ['down 1.0', 'up 1.0']);
  });

  test('a detector with only a tap has no down to hear', () {
    final app = AppTester.widget(
      GestureDetector(
        key: const ValueKey('pad'),
        onTap: () {},
        child: const Text('Pad'),
      ),
    );
    expect(app.get('pad').props.containsKey('tapDownEventId'), isFalse);
  });
}
