/// `Matrix4` is a matrix: calls compose in the order they are made, as in
/// Flutter, and a box is given the shift, turn and two scales read out of it.
library;

import 'dart:math' as math;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic>? _sent(Matrix4 matrix) {
  final app = AppTester.widget(
    Transform(transform: matrix, child: const Text('x')),
  );
  final box = app.nodes.firstWhere((n) => n.type == 'Box');
  return (box.props['transform'] as Map?)?.cast<String, dynamic>();
}

void main() {
  test('a scale after a translate leaves the translate as it was', () {
    final m = Matrix4.identity()
      ..translate(10.0, 20.0)
      ..scale(2.0);
    expect(m.getTranslation(), const Offset(10, 20));
    expect(_sent(m), {'scale': 2.0, 'dx': 10.0, 'dy': 20.0});
  });

  test('a translate after a scale is scaled, as in Flutter', () {
    final m = Matrix4.identity()
      ..scale(2.0)
      ..translate(10.0, 20.0);
    expect(m.getTranslation(), const Offset(20, 40));
  });

  test('a translate after a turn goes along the turned axes', () {
    final m = Matrix4.identity()
      ..rotateZ(math.pi / 2)
      ..translate(10.0, 0.0);
    expect(m.getTranslation().dx, closeTo(0, 1e-9));
    expect(m.getTranslation().dy, closeTo(10, 1e-9));
    expect(_sent(m)!['rotate'], closeTo(math.pi / 2, 1e-9));
  });

  test('two scales travel as two', () {
    expect(_sent(Matrix4.diagonal3Values(2, 3, 1)), {
      'scale': 2.0,
      'scaleY': 3.0,
    });
    final app = AppTester.widget(
      Transform.scale(scaleX: 2, scaleY: 0.5, child: const Text('x')),
    );
    expect(app.nodes.firstWhere((n) => n.type == 'Box').props['transform'], {
      'scale': 2.0,
      'scaleY': 0.5,
    });
  });

  test('entries, multiply, equality and the identity', () {
    final m = Matrix4.translationValues(5, 6, 0);
    expect(m.entry(0, 3), 5);
    expect(m.storage[13], 6);
    expect(Matrix4.identity().isIdentity(), isTrue);
    expect(_sent(Matrix4.identity()), isNull);
    final both = Matrix4.translationValues(1, 0, 0)
      ..multiply(Matrix4.translationValues(2, 0, 0));
    expect(both, Matrix4.translationValues(3, 0, 0));
    expect(Matrix4.diagonal3Values(2, 4, 1).getMaxScaleOnAxis(), 4);
  });
}
