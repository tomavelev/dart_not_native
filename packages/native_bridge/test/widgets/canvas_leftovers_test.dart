/// What a canvas used to leave out: `dart:ui`'s own gradients
/// (`Gradient.linear` and its kin), tile modes other than clamp, blur styles
/// other than normal, and a path's even-odd fill.
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

({List<List<Object?>> commands, List<Map<String, dynamic>> paints}) _drawn(
  void Function(Canvas, Size) draw,
) {
  final app = AppTester.widget(
    CustomPaint(size: const Size(200, 100), painter: _Painter(draw)),
  );
  final props = app.ofType('Canvas').single.props;
  return (
    commands: [
      for (final command in props['commands'] as List)
        List<Object?>.from(command as List),
    ],
    paints: [
      for (final paint in props['paints'] as List)
        Map<String, dynamic>.from(paint as Map),
    ],
  );
}

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);

void main() {
  group('dart:ui gradients', () {
    test('Gradient.linear is its two points, as given', () {
      final drawn = _drawn((canvas, size) {
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 200, 100),
          Paint()
            ..shader = Gradient.linear(
              const Offset(10, 20),
              const Offset(110, 20),
              [_red, _blue],
              [0.2, 0.9],
            ),
        );
      });
      expect(drawn.paints.single['gradient'], {
        'type': 'linear',
        'from': [10.0, 20.0],
        'to': [110.0, 20.0],
        'colors': ['#ff0000', '#0000ff'],
        'stops': [0.2, 0.9],
      });
    });

    test('Gradient.radial is its centre and radius', () {
      final drawn = _drawn((canvas, size) {
        canvas.drawCircle(
          const Offset(50, 50),
          40,
          Paint()
            ..shader = Gradient.radial(const Offset(50, 50), 40, [_red, _blue]),
        );
      });
      expect(drawn.paints.single['gradient'], {
        'type': 'radial',
        'center': [50.0, 50.0],
        'radius': 40.0,
        'colors': ['#ff0000', '#0000ff'],
      });
    });

    test('Gradient.sweep is its share of the turn', () {
      final drawn = _drawn((canvas, size) {
        canvas.drawCircle(
          const Offset(50, 50),
          40,
          Paint()
            ..shader = Gradient.sweep(
              const Offset(50, 50),
              [_red, _blue],
              null,
              TileMode.clamp,
              0,
              math.pi,
            ),
        );
      });
      final gradient = drawn.paints.single['gradient'] as Map;
      expect(gradient['type'], 'sweep');
      expect(gradient['stops'], [0.0, 0.5]);
    });

    test('and is a gradient a box can wear too', () {
      final gradient = Gradient.linear(
        Offset.zero,
        const Offset(10, 0),
        [_red, _blue],
      );
      expect(
        AppTester.widget(
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(gradient: gradient),
          ),
        ).nodes.any((n) => n.props['gradient'] != null),
        isTrue,
      );
    });
  });

  group('tile modes', () {
    Map<String, dynamic> linear(TileMode mode) => _drawn((canvas, size) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 200, 100),
        Paint()
          ..shader = LinearGradient(
            colors: const [_red, _blue],
            tileMode: mode,
          ).createShader(const Rect.fromLTWH(90, 0, 20, 100)),
      );
    }).paints.single['gradient'] as Map<String, dynamic>;

    test('clamp is sent as it is', () {
      final gradient = linear(TileMode.clamp);
      expect(gradient['colors'], ['#ff0000', '#0000ff']);
      expect(gradient.containsKey('tile'), isFalse);
    });

    test('repeated is copies of it that reach across the canvas', () {
      final gradient = linear(TileMode.repeated);
      final from = gradient['from'] as List, to = gradient['to'] as List;
      expect(from[0] as num, lessThanOrEqualTo(-200));
      expect(to[0] as num, greaterThanOrEqualTo(400));
      final colors = gradient['colors'] as List;
      final stops = [for (final s in gradient['stops'] as List) s as num];
      // Red to blue, again and again: each copy whole, with a hard edge
      // where the next begins.
      expect(colors.take(4), ['#ff0000', '#ff0000', '#0000ff', '#0000ff']);
      expect(colors.skip(4).take(2), ['#ff0000', '#ff0000']);
      expect(stops.first, 0);
      expect(stops.last, 1);
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i], greaterThanOrEqualTo(stops[i - 1]));
      }
      expect(gradient.containsKey('tile'), isFalse);
    });

    test('mirror turns every other copy round', () {
      final colors = linear(TileMode.mirror)['colors'] as List;
      final copies = [
        for (var i = 0; i + 4 <= colors.length; i += 4)
          colors.sublist(i, i + 4).join(),
      ];
      expect(copies.toSet(), hasLength(2));
      expect(copies[0], isNot(copies[1]));
    });

    test('decal fades to clear just beyond each end', () {
      final gradient = linear(TileMode.decal);
      expect(gradient['colors'], [
        '#00ff0000',
        '#ff0000',
        '#0000ff',
        '#000000ff',
      ]);
    });

    test('a radial one repeats outwards only', () {
      final gradient = _drawn((canvas, size) {
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 200, 100),
          Paint()
            ..shader = Gradient.radial(
              const Offset(100, 50),
              10,
              [_red, _blue],
              null,
              TileMode.repeated,
            ),
        );
      }).paints.single['gradient'] as Map;
      expect(gradient['center'], [100.0, 50.0]);
      expect(gradient['radius'] as num, greaterThan(300));
      expect((gradient['colors'] as List).take(2), ['#ff0000', '#ff0000']);
    });

    test('a sweep comes round again', () {
      final gradient = _drawn((canvas, size) {
        canvas.drawCircle(
          const Offset(50, 50),
          40,
          Paint()
            ..shader = Gradient.sweep(
              const Offset(50, 50),
              [_red, _blue],
              null,
              TileMode.repeated,
              0,
              math.pi / 2,
            ),
        );
      }).paints.single['gradient'] as Map;
      expect(gradient['colors'], hasLength(8));
      expect(gradient['stops'], [0.0, 0.25, 0.25, 0.5, 0.5, 0.75, 0.75, 1.0]);
    });
  });

  group('blur styles', () {
    Paint blurred(BlurStyle style) => Paint()
      ..color = _red
      ..maskFilter = MaskFilter.blur(style, 4);

    test('normal is one blurred shape', () {
      final drawn = _drawn((canvas, size) {
        canvas.drawCircle(const Offset(50, 50), 20, blurred(BlurStyle.normal));
      });
      expect(drawn.commands.map((c) => c.first), ['circle']);
    });

    test('solid is the blur with the shape sharp over it', () {
      final drawn = _drawn((canvas, size) {
        canvas.drawCircle(const Offset(50, 50), 20, blurred(BlurStyle.solid));
      });
      expect(drawn.commands.map((c) => c.first), ['circle', 'circle']);
      expect(drawn.paints[drawn.commands[0].last! as int]['blur'], 4);
      expect(
        drawn.paints[drawn.commands[1].last! as int].containsKey('blur'),
        isFalse,
      );
    });

    test('inner is the blur kept within the shape', () {
      final drawn = _drawn((canvas, size) {
        canvas.drawRect(
          const Rect.fromLTWH(10, 10, 50, 50),
          blurred(BlurStyle.inner),
        );
      });
      expect(drawn.commands.map((c) => c.first), [
        'save',
        'clipPath',
        'rect',
        'restore',
      ]);
      expect(drawn.commands[1].length, 2, reason: 'a plain clip');
    });

    test('outer is the blur with the shape cut out of it', () {
      final drawn = _drawn((canvas, size) {
        canvas.drawOval(
          const Rect.fromLTWH(10, 10, 50, 30),
          blurred(BlurStyle.outer),
        );
      });
      expect(drawn.commands.map((c) => c.first), [
        'save',
        'clipPath',
        'oval',
        'restore',
      ]);
      expect(drawn.commands[1].last, 'evenOdd');
      final segments = drawn.commands[1][1] as List;
      expect(segments.map((s) => (s as List).first), ['R', 'O']);
    });

    test('a stroke asked for outer is blurred as normal', () {
      final drawn = _drawn((canvas, size) {
        canvas.drawLine(
          Offset.zero,
          const Offset(50, 50),
          blurred(BlurStyle.outer)..strokeWidth = 4,
        );
      });
      expect(drawn.commands.map((c) => c.first), ['line']);
    });
  });

  test('a paint\'s blend mode travels with it; source-over is not said', () {
    final drawn = _drawn((canvas, size) {
      canvas
        ..drawRect(
          const Rect.fromLTWH(0, 0, 10, 10),
          Paint()
            ..color = _red
            ..blendMode = BlendMode.multiply,
        )
        ..drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint()..color = _red);
    });
    expect(drawn.paints, hasLength(2), reason: 'a blend is a different paint');
    expect(drawn.paints.first['blend'], 'multiply');
    expect(drawn.paints.last.containsKey('blend'), isFalse);
  });

  test('saveLayer is a layer, with its opacity and blend', () {
    final drawn = _drawn((canvas, size) {
      canvas
        ..saveLayer(
          null,
          Paint()
            ..color = const Color(0x80000000)
            ..blendMode = BlendMode.screen,
        )
        ..drawCircle(const Offset(20, 20), 10, Paint())
        ..restore();
    });
    expect(drawn.commands.first.first, 'saveLayer');
    expect(drawn.commands.first[1], closeTo(0.5, 0.01));
    expect(drawn.commands.first[2], 'screen');
    expect(drawn.commands.last, ['restore']);
  });

  test('a path filled even-odd says so, and so does a clip', () {
    final drawn = _drawn((canvas, size) {
      final ring = Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(const Rect.fromLTWH(0, 0, 100, 100))
        ..addOval(const Rect.fromLTWH(25, 25, 50, 50));
      canvas
        ..save()
        ..clipPath(ring)
        ..drawPath(ring, Paint()..color = _red)
        ..drawPath(Path()..addRect(Rect.fromLTWH(0, 0, 9, 9)), Paint())
        ..restore();
    });
    expect(drawn.commands[1].last, 'evenOdd');
    expect(drawn.commands[2].last, 'evenOdd');
    expect(drawn.commands[3].length, 3, reason: 'non-zero is not said');
  });
}
