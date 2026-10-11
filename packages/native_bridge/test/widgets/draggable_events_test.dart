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

  setUp(() => heard = []);

  Widget board({bool accepts = true, bool listens = true, Widget? away}) => Column(
    children: [
      Draggable<String>(
        key: const ValueKey('piece'),
        data: 'pawn',
        feedback: const Text('lifted'),
        childWhenDragging: away,
        onDragStarted: listens ? () => heard.add('started') : null,
        onDragEnd: listens
            ? (details) => heard.add('end accepted=${details.wasAccepted}')
            : null,
        onDraggableCanceled: listens
            ? (velocity, offset) => heard.add('cancelled')
            : null,
        onDragCompleted: () => heard.add('completed'),
        child: const Text('Pawn'),
      ),
      DragTarget<String>(
        key: const ValueKey('square'),
        onWillAcceptWithDetails: (_) => accepts,
        onAcceptWithDetails: (details) => heard.add('dropped ${details.data}'),
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

  test('a draggable nobody listens to asks for no events', () {
    final app = AppTester.widget(board(listens: false));

    expect(piece(app).props.containsKey('dragEventId'), isFalse);
    expect(piece(app).props['dragData'], isA<String>());
  });
}
