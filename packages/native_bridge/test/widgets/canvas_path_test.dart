/// A path's rounded rectangle and its arc to a point are written as the
/// curves that draw them, and a canvas can be clipped to a path.
library;

import 'dart:math' as math;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Painter extends CustomPainter {
  _Painter(this.draw);
  final void Function(Canvas canvas, Size size) draw;
  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);
  @override
  bool shouldRepaint(_Painter oldDelegate) => true;
}

List<List<Object?>> _commands(void Function(Canvas, Size) draw) {
  final app = AppTester.widget(
    CustomPaint(size: const Size(200, 100), painter: _Painter(draw)),
  );
  return [
    for (final command in app.ofType('Canvas').single.props['commands'] as List)
      List<Object?>.of(command as List),
  ];
}

List<List<Object?>> _segments(Path path) {
  final commands = _commands((canvas, _) => canvas.drawPath(path, Paint()));
  return [
    for (final segment in commands.single[1]! as List)
      List<Object?>.of(segment as List),
  ];
}

/// The point a segment ends on.
(double, double) _end(List<Object?> segment) => (
  segment[segment.length - 2]! as double,
  segment[segment.length - 1]! as double,
);

/// Where a cubic from [from] is half way along.
(double, double) _middle((double, double) from, List<Object?> c) {
  double at(int i) => c[i]! as double;
  return (
    (from.$1 + 3 * at(1) + 3 * at(3) + at(5)) / 8,
    (from.$2 + 3 * at(2) + 3 * at(4) + at(6)) / 8,
  );
}

void main() {
  group('addRRect', () {
    test('is four sides and four corners, closed', () {
      final segments = _segments(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(10, 20, 100, 60),
            const Radius.circular(10),
          ),
        ),
      );

      expect([for (final s in segments) s.first], [
        'M', 'L', 'C', 'L', 'C', 'L', 'C', 'L', 'C', 'Z', //
      ]);
      expect(segments[0], ['M', 20.0, 20.0]);
      expect(segments[1], ['L', 100.0, 20.0]);
      expect(_end(segments[2]), (110.0, 30.0));
    });

    test('a corner bulges as a quarter circle does', () {
      final segments = _segments(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 100, 100),
            const Radius.circular(20),
          ),
        ),
      );

      // The top right corner turns about (80, 20).
      final (x, y) = _middle(_end(segments[1]), segments[2]);
      expect(math.sqrt(math.pow(x - 80, 2) + math.pow(y - 20, 2)),
          closeTo(20, 0.05));
    });

    test('each corner has its own radius', () {
      final segments = _segments(
        Path()..addRRect(
          RRect.fromRectAndCorners(
            const Rect.fromLTWH(0, 0, 100, 100),
            topLeft: const Radius.circular(30),
            bottomRight: const Radius.circular(10),
          ),
        ),
      );

      expect(segments[0], ['M', 30.0, 0.0]);
      expect(segments[1], ['L', 100.0, 0.0], reason: 'a square top right');
      expect(segments[3], ['L', 100.0, 90.0]);
    });

    test('radii too big for a side are shrunk together', () {
      final segments = _segments(
        Path()..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, 100, 40),
            const Radius.circular(50),
          ),
        ),
      );

      expect(segments[0], ['M', 20.0, 0.0]);
      expect(segments[1], ['L', 80.0, 0.0]);
    });

    test('its bounds are the rectangle', () {
      final path = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(10, 20, 100, 60),
            const Radius.circular(10),
          ),
        );

      expect(path.getBounds(), const Rect.fromLTRB(10, 20, 110, 80));
    });
  });

  group('arcToPoint', () {
    test('a quarter turn is one curve that stays on the circle', () {
      final segments = _segments(
        Path()
          ..moveTo(100, 50)
          ..arcToPoint(const Offset(50, 100), radius: const Radius.circular(50)),
      );

      expect([for (final s in segments) s.first], ['M', 'C']);
      expect(_end(segments[1]), (50.0, 100.0));
      // Clockwise from the right of a circle about (50, 50) to its bottom.
      final (x, y) = _middle((100, 50), segments[1]);
      expect(math.sqrt(math.pow(x - 50, 2) + math.pow(y - 50, 2)),
          closeTo(50, 0.05));
      expect(x, greaterThan(50));
      expect(y, greaterThan(50));
    });

    test('anticlockwise goes round the other side', () {
      final segments = _segments(
        Path()
          ..moveTo(100, 50)
          ..arcToPoint(
            const Offset(50, 100),
            radius: const Radius.circular(50),
            clockwise: false,
          ),
      );

      // The short way anticlockwise turns about (100, 100).
      final (x, y) = _middle((100, 50), segments[1]);
      expect(math.sqrt(math.pow(x - 100, 2) + math.pow(y - 100, 2)),
          closeTo(50, 0.05));
    });

    test('the long way round is more than one curve', () {
      final segments = _segments(
        Path()
          ..moveTo(100, 50)
          ..arcToPoint(
            const Offset(50, 100),
            radius: const Radius.circular(50),
            largeArc: true,
          ),
      );

      expect(segments.length, 4, reason: 'three quarters of a turn');
      expect(_end(segments.last), (50.0, 100.0));
    });

    test('a half turn with radii too small still arrives', () {
      final segments = _segments(
        Path()
          ..moveTo(0, 0)
          ..arcToPoint(const Offset(100, 0), radius: const Radius.circular(10)),
      );

      expect(_end(segments.last), (100.0, 0.0));
      final (_, y) = _end(segments[1]);
      expect(y.abs(), closeTo(50, 0.05), reason: 'the radius grew to reach');
    });

    test('no radius is a straight line', () {
      final segments = _segments(
        Path()
          ..moveTo(0, 0)
          ..arcToPoint(const Offset(100, 0)),
      );

      expect(segments.last, ['L', 100.0, 0.0]);
    });

    test('the relative form starts from where the path is', () {
      final segments = _segments(
        Path()
          ..moveTo(100, 50)
          ..relativeArcToPoint(
            const Offset(-50, 50),
            radius: const Radius.circular(50),
          ),
      );

      expect(_end(segments.last), (50.0, 100.0));
    });
  });

  test('clipPath carries the path', () {
    final commands = _commands((canvas, _) {
      canvas.clipPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(10, 0)
          ..close(),
      );
    });

    expect(commands.single, [
      'clipPath',
      [
        ['M', 0.0, 0.0],
        ['L', 10.0, 0.0],
        ['Z'],
      ],
    ]);
  });

  test('a blur travels with its paint, and makes a paint of its own', () {
    final app = AppTester.widget(
      CustomPaint(
        size: const Size(200, 100),
        painter: _Painter((canvas, _) {
          const rect = Rect.fromLTWH(0, 0, 10, 10);
          canvas.drawRect(rect, Paint());
          canvas.drawRect(
            rect,
            Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }),
      ),
    );
    final paints = app.ofType('Canvas').single.props['paints'] as List;

    expect(paints, hasLength(2));
    expect((paints[0] as Map).containsKey('blur'), isFalse);
    expect((paints[1] as Map)['blur'], 6);
  });
}
