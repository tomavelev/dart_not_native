/// A gradient on a canvas: `paint.shader = gradient.createShader(rect)`.
/// A paint's shader used to be ignored, so a shape painted with one was drawn
/// in the paint's plain colour.
library;

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

List<Map<String, dynamic>> _paints(void Function(Canvas, Size) draw) {
  final app = AppTester.widget(
    CustomPaint(size: const Size(200, 100), painter: _Painter(draw)),
  );
  return [
    for (final paint in app.ofType('Canvas').single.props['paints'] as List)
      Map<String, dynamic>.from(paint as Map),
  ];
}

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);

void main() {
  test('a linear gradient is two points in the canvas, and its colours', () {
    final paints = _paints((canvas, size) {
      const rect = Rect.fromLTWH(20, 10, 100, 40);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            colors: [_red, _blue],
          ).createShader(rect),
      );
    });

    expect(paints.single['gradient'], {
      'type': 'linear',
      'from': [20.0, 30.0],
      'to': [120.0, 30.0],
      'colors': ['#ff0000', '#0000ff'],
    });
  });

  test('begin and end place it, and stops travel', () {
    final paints = _paints((canvas, size) {
      const rect = Rect.fromLTWH(0, 0, 200, 100);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_red, _blue],
            stops: [0.2, 0.9],
          ).createShader(rect),
      );
    });
    final gradient = paints.single['gradient'] as Map;

    expect(gradient['from'], [100.0, 0.0]);
    expect(gradient['to'], [100.0, 100.0]);
    expect(gradient['stops'], [0.2, 0.9]);
  });

  test('a radial gradient is a centre and a radius of the shorter side', () {
    final paints = _paints((canvas, size) {
      const rect = Rect.fromLTWH(0, 0, 200, 100);
      canvas.drawCircle(
        rect.center,
        40,
        Paint()
          ..shader = const RadialGradient(
            radius: 0.4,
            colors: [_red, _blue],
          ).createShader(rect),
      );
    });

    expect(paints.single['gradient'], {
      'type': 'radial',
      'center': [100.0, 50.0],
      'radius': 40.0,
      'colors': ['#ff0000', '#0000ff'],
    });
  });

  test('two gradients, and a plain paint, are three paints', () {
    final paints = _paints((canvas, size) {
      const a = Rect.fromLTWH(0, 0, 50, 50);
      const b = Rect.fromLTWH(60, 0, 50, 50);
      const gradient = LinearGradient(colors: [_red, _blue]);
      canvas
        ..drawRect(a, Paint()..shader = gradient.createShader(a))
        ..drawRect(b, Paint()..shader = gradient.createShader(b))
        ..drawRect(a, Paint())
        // The same gradient in the same place is the same paint.
        ..drawRect(a, Paint()..shader = gradient.createShader(a));
    });

    expect(paints, hasLength(3));
    expect(paints.where((paint) => paint.containsKey('gradient')), hasLength(2));
  });

  test('a paint with no shader, or one that is not a gradient, has none', () {
    final paints = _paints((canvas, size) {
      canvas
        ..drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint())
        ..drawRect(
          const Rect.fromLTWH(0, 0, 10, 10),
          Paint()
            ..color = _red
            ..shader = 'not a shader',
        );
    });

    expect(paints.any((paint) => paint.containsKey('gradient')), isFalse);
  });

  test('a sweep is its centre, where it starts, and stops as shares of a turn',
      () {
    final paints = _paints((canvas, size) {
      const rect = Rect.fromLTWH(0, 0, 200, 100);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const SweepGradient(
            colors: [_red, _blue],
            startAngle: 1,
            endAngle: 1 + 3.141592653589793,
          ).createShader(rect),
      );
    });

    final gradient = paints.single['gradient'] as Map;
    expect(gradient['type'], 'sweep');
    expect(gradient['center'], [100.0, 50.0]);
    expect(gradient['angle'], 1);
    expect(gradient['colors'], ['#ff0000', '#0000ff']);
    expect((gradient['stops'] as List)[0], 0);
    expect((gradient['stops'] as List)[1], closeTo(0.5, 1e-9));
  });

  test('a sweep\'s own stops are stretched over its share of the turn', () {
    final paints = _paints((canvas, size) {
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const SweepGradient(
            colors: [_red, _blue, _red],
            stops: [0, 0.25, 1],
          ).createShader(rect),
      );
    });

    expect((paints.single['gradient'] as Map)['stops'], [0.0, 0.25, 1.0]);
  });
}
