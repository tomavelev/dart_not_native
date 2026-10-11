/// A `Dismissible` slides its row away under the finger. It used to reveal
/// an action behind the row instead, and did nothing for a vertical
/// direction.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<DismissDirection> dismissed;
  late List<DismissDirection> asked;

  setUp(() {
    dismissed = [];
    asked = [];
  });

  AppTester row({
    DismissDirection direction = DismissDirection.horizontal,
    bool? confirm,
    Map<DismissDirection, double> thresholds = const {},
    TextDirection reading = TextDirection.ltr,
  }) => AppTester.widget(
    Directionality(
      textDirection: reading,
      child: Dismissible(
        key: const ValueKey('row'),
        direction: direction,
        background: const Text('Archive'),
        secondaryBackground: const Text('Delete'),
        dismissThresholds: thresholds,
        movementDuration: Duration.zero,
        confirmDismiss: confirm == null
            ? null
            : (way) async {
                asked.add(way);
                return confirm;
              },
        onDismissed: dismissed.add,
        child: const Text('The row'),
      ),
    ),
  );

  WidgetNode front(AppTester app) => app.get('row').children!.last;
  double at(AppTester app, [String axis = 'dx']) =>
      ((front(app).props['transform'] as Map?)?[axis] as num?)?.toDouble() ?? 0;

  /// A drag of [by] along the row (or down it), let go at [speed].
  Future<void> drag(
    AppTester app,
    double by, {
    double speed = 0,
    bool vertical = false,
  }) async {
    final pan = front(app).props['panEventId'] as String;
    final d = vertical ? 'dy' : 'dx';
    final v = vertical ? 'vy' : 'vx';
    await app.emit('${pan}_start', const {});
    // The row is told how big it is, as a renderer tells it.
    await app.emit(front(app).props['sizeEventId'] as String, {
      'width': 400.0,
      'height': 60.0,
    });
    await app.emit('${pan}_update', {d: by / 2});
    await app.emit('${pan}_update', {d: by / 2});
    await app.emit('${pan}_end', {v: speed});
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test('at rest it is the row, with nothing behind it', () {
    final app = row();

    expect(app.hasText('The row'), isTrue);
    expect(app.hasText('Archive'), isFalse);
    expect(app.hasText('Delete'), isFalse);
    expect(front(app).props.containsKey('transform'), isFalse);
  });

  test('the row follows the finger, at once', () async {
    final app = row();
    final pan = front(app).props['panEventId'] as String;

    await app.emit('${pan}_start', const {});
    await app.emit('${pan}_update', {'dx': 30.0});
    await app.emit('${pan}_update', {'dx': 25.0});

    expect(at(app), 55);
    expect(front(app).props['animateMs'], 0);
  });

  test('each way shows its own background', () async {
    final app = row();
    final pan = front(app).props['panEventId'] as String;

    await app.emit('${pan}_start', const {});
    await app.emit('${pan}_update', {'dx': 30.0});
    expect(app.hasText('Archive'), isTrue);
    expect(app.hasText('Delete'), isFalse);

    await app.emit('${pan}_update', {'dx': -60.0});
    expect(app.hasText('Delete'), isTrue);
    expect(app.hasText('Archive'), isFalse);
  });

  test('past the threshold it slides away and is dismissed', () async {
    final app = row();

    await drag(app, 200);

    expect(dismissed, [DismissDirection.startToEnd]);
    // All the way out, by its own width.
    expect(at(app), 400);
  });

  test('short of it, it goes back', () async {
    final app = row();

    await drag(app, 100);

    expect(dismissed, isEmpty);
    expect(at(app), 0);
    expect(app.hasText('Archive'), isFalse);
  });

  test('a fling dismisses from anywhere; one back does not', () async {
    var app = row();
    await drag(app, -60, speed: -1200);
    expect(dismissed, [DismissDirection.endToStart]);

    dismissed.clear();
    app = row();
    await drag(app, -60, speed: 1200);
    expect(dismissed, isEmpty);
  });

  test('a threshold of its own is the one that counts', () async {
    final app = row(thresholds: {DismissDirection.startToEnd: 0.8});

    await drag(app, 200);

    expect(dismissed, isEmpty);
  });

  test('confirmDismiss is asked, and false puts the row back', () async {
    final app = row(confirm: false);

    await drag(app, 300);

    expect(asked, [DismissDirection.startToEnd]);
    expect(dismissed, isEmpty);
    expect(at(app), 0);
  });

  test('a row swiped one way only does not move the other', () async {
    final app = row(direction: DismissDirection.endToStart);
    final pan = front(app).props['panEventId'] as String;

    await app.emit('${pan}_start', const {});
    await app.emit('${pan}_update', {'dx': 80.0});
    expect(at(app), 0);
    expect(app.hasText('Archive'), isFalse);

    await drag(app, -300);
    expect(dismissed, [DismissDirection.endToStart]);
  });

  test('read from the right, the start is on the right', () async {
    final app = row(reading: TextDirection.rtl);

    await drag(app, 300);

    expect(dismissed, [DismissDirection.endToStart]);
  });

  test('a vertical one goes up or down', () async {
    var app = row(direction: DismissDirection.vertical);
    expect(front(app).props['panAxis'], 'vertical');

    await drag(app, -40, vertical: true);
    expect(dismissed, [DismissDirection.up]);
    expect(at(app, 'dy'), -60);

    dismissed.clear();
    app = row(direction: DismissDirection.down);
    await drag(app, -40, vertical: true);
    expect(dismissed, isEmpty);
    await drag(app, 40, vertical: true);
    expect(dismissed, [DismissDirection.down]);
  });

  test('DismissDirection.none is the row and no more', () {
    final app = row(direction: DismissDirection.none);

    expect(app.nodes.any((node) => node.props['panEventId'] != null), isFalse);
    expect(app.hasText('The row'), isTrue);
  });

  test('once dismissed, it does not answer another swipe', () async {
    final app = row();
    await drag(app, 300);

    await drag(app, -300);

    expect(dismissed, [DismissDirection.startToEnd]);
  });
}
