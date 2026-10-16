/// A `Draggable` hears its drag begin and end. It used to hear only a drop a
/// target accepted, so a board could not mark the piece being moved or put
/// one back that was let go over nothing.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> heard;
  DraggableDetails? ended;
  (Velocity, Offset)? cancelledAt;
  Offset? droppedAt;

  setUp(() {
    heard = [];
    ended = null;
    cancelledAt = null;
    droppedAt = null;
  });

  Widget board({bool accepts = true, bool listens = true, Widget? away}) =>
      Column(
        children: [
          Draggable<String>(
            key: const ValueKey('piece'),
            data: 'pawn',
            feedback: const Text('lifted'),
            childWhenDragging: away,
            onDragStarted: listens ? () => heard.add('started') : null,
            onDragEnd: listens
                ? (details) {
                    heard.add('end accepted=${details.wasAccepted}');
                    ended = details;
                  }
                : null,
            onDraggableCanceled: listens
                ? (velocity, offset) {
                    heard.add('cancelled');
                    cancelledAt = (velocity, offset);
                  }
                : null,
            onDragCompleted: () => heard.add('completed'),
            child: const Text('Pawn'),
          ),
          DragTarget<String>(
            key: const ValueKey('square'),
            onWillAcceptWithDetails: (_) => accepts,
            onAcceptWithDetails: (details) {
              heard.add('dropped ${details.data}');
              droppedAt = details.offset;
            },
            builder: (context, candidates, rejected) => const Text('Square'),
          ),
        ],
      );

  WidgetNode piece(AppTester app) => app.get('piece');
  String drag(AppTester app) => piece(app).props['dragEventId'] as String;
  Future<void> drop(AppTester app) => app.emit(
    app.get('square').props['dropEventId'] as String,
    {'data': piece(app).props['dragData']},
  );

  test('picked up and let go over nothing: started, cancelled, ended', () async {
    final app = AppTester.widget(board());

    await app.emit('${drag(app)}_start');
    expect(heard, ['started']);
    await app.emit('${drag(app)}_end');

    expect(heard, ['started', 'cancelled', 'end accepted=false']);
  });

  test('dropped on a target that takes it: completed, and ended as accepted',
      () async {
    final app = AppTester.widget(board());

    await app.emit('${drag(app)}_start');
    await drop(app);
    await app.emit('${drag(app)}_end');

    expect(heard, [
      'started',
      'dropped pawn',
      'completed',
      'end accepted=true',
    ]);
  });

  test('dropped on a target that refuses it is a cancel', () async {
    final app = AppTester.widget(board(accepts: false));

    await app.emit('${drag(app)}_start');
    await drop(app);
    await app.emit('${drag(app)}_end');

    expect(heard, ['started', 'cancelled', 'end accepted=false']);
  });

  test('one drag is not remembered by the next', () async {
    final app = AppTester.widget(board());
    await app.emit('${drag(app)}_start');
    await drop(app);
    await app.emit('${drag(app)}_end');
    heard.clear();

    await app.emit('${drag(app)}_start');
    await app.emit('${drag(app)}_end');

    expect(heard, ['started', 'cancelled', 'end accepted=false']);
  });

  test('an end with no start, or a second start, is not a drag', () async {
    final app = AppTester.widget(board());

    await app.emit('${drag(app)}_end');
    expect(heard, isEmpty);

    await app.emit('${drag(app)}_start');
    await app.emit('${drag(app)}_start');
    expect(heard, ['started']);
  });

  test('childWhenDragging is drawn where the piece was, while it is away',
      () async {
    final app = AppTester.widget(board(away: const Text('Empty square')));
    expect(app.hasText('Pawn'), isTrue);
    final box = piece(app).props['dragData'];

    await app.emit('${drag(app)}_start');
    await Future<void>.delayed(Duration.zero);
    expect(app.hasText('Empty square'), isTrue);
    expect(app.hasText('Pawn'), isFalse);
    // The same box, still carrying the same thing: only what it holds changed.
    expect(piece(app).props['dragData'], box);

    await app.emit('${drag(app)}_end');
    await Future<void>.delayed(Duration.zero);
    expect(app.hasText('Pawn'), isTrue);
    expect(app.hasText('Empty square'), isFalse);
  });

  test('a draggable nobody listens to still says when it is picked up', () {
    // A target under it names what is over it from the drags in the air.
    final app = AppTester.widget(board(listens: false));

    expect(piece(app).props['dragEventId'], isA<String>());
    expect(piece(app).props['dragData'], isA<String>());
  });

  test('what is carried is the feedback, drawn apart from the box', () {
    final app = AppTester.widget(board());
    final feedback = piece(app).props['dragFeedback'] as Map<String, dynamic>;

    expect(feedback['type'], 'Text');
    expect((feedback['props'] as Map)['content'], 'lifted');
    // Not among the box's children, which are what is laid out.
    expect(piece(app).children!.single.props['content'], 'Pawn');
  });

  test('a feedback that is the child again does not take its name', () {
    final app = AppTester.widget(
      const Draggable<String>(
        key: ValueKey('piece'),
        data: 'x',
        feedback: Text('Pawn', key: ValueKey('pawn')),
        child: Text('Pawn', key: ValueKey('pawn')),
      ),
    );
    final feedback = app.get('piece').props['dragFeedback'] as Map;
    expect((feedback['props'] as Map).containsKey('id'), isFalse);
    expect(app.get('pawn').props['content'], 'Pawn');
  });

  test(
    'let go over nothing: where the picture was and how fast it went',
    () async {
      final app = AppTester.widget(board());
      await app.emit('${drag(app)}_start');
      await app.emit('${drag(app)}_end', {
        'x': 120.0,
        'y': 340.0,
        'vx': -50.0,
        'vy': 800.0,
      });

      expect(ended!.offset, const Offset(120, 340));
      expect(ended!.velocity.pixelsPerSecond, const Offset(-50, 800));
      expect(cancelledAt!.$1.pixelsPerSecond, const Offset(-50, 800));
      expect(cancelledAt!.$2, const Offset(120, 340));
    },
  );

  test('dropped: the target is told where the picture was', () async {
    final app = AppTester.widget(board());
    await app.emit('${drag(app)}_start');
    await app.emit(app.get('square').props['dropEventId'] as String, {
      'data': piece(app).props['dragData'],
      'x': 10.0,
      'y': 20.0,
    });
    await app.emit('${drag(app)}_end', {'x': 10.0, 'y': 20.0});

    expect(droppedAt, const Offset(10, 20));
    expect(ended!.wasAccepted, isTrue);
    expect(ended!.offset, const Offset(10, 20));
  });
}
