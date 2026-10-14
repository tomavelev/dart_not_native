/// `ScaleUpdateDetails.rotation` is how far the fingers turned, as the
/// renderer reports it.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a turn reaches onScaleUpdate', () async {
    final turns = <double>[];
    final app = AppTester.widget(
      GestureDetector(
        onScaleUpdate: (details) => turns.add(details.rotation),
        child: const SizedBox(width: 100, height: 100),
      ),
    );
    final pan = app.nodes
        .firstWhere((n) => n.props['panEventId'] is String)
        .props['panEventId'] as String;

    await app.emit('${pan}_start', const {});
    await app.emit('${pan}_update', {'scale': 1.0, 'rotation': 0.5, 'pointers': 2});
    await app.emit('${pan}_update', const {'dx': 3.0});

    expect(turns, [0.5, 0.0]);
  });
}
