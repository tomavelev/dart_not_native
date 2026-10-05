/// CustomPaint runs its painter during the build and sends what the Canvas
/// recorded: a list of commands and a table of the paints they use.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);

/// Draws a little of everything, and remembers the size it was given.
class _ShapesPainter extends CustomPainter {
  static Size? lastSize;

  @override
  void paint(Canvas canvas, Size size) {
    lastSize = size;
    // Three paints made separately that draw the same: one table entry.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _red,
    );
    canvas.drawCircle(const Offset(10, 20), 5, Paint()..color = _red);
    canvas.drawOval(Rect.fromLTWH(1, 2, 3, 4), Paint()..color = _red);

    final stroke = Paint()
      ..color = _blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, const Offset(30, 40), stroke);

    canvas.save();
    canvas.translate(5, 6);
    canvas.rotate(0.5);
    canvas.scale(2);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(10, 0)
      ..quadraticBezierTo(15, 5, 10, 10)
      ..close();
    canvas.drawPath(path, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapesPainter oldDelegate) => false;
}

/// Centres a label on x = 100 the way a Flutter painter does: measure, then
/// offset by half the width.
class _LabelPainter extends CustomPainter {
  static double? measuredWidth;
  static double? measuredHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final label = TextPainter(
      text: const TextSpan(
        text: 'Hello',
        style: TextStyle(fontSize: 20, color: _red),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    measuredWidth = label.width;
    measuredHeight = label.height;
    label.paint(canvas, Offset(100 - label.width / 2, 50));
  }

  @override
  bool shouldRepaint(_LabelPainter oldDelegate) => false;
}

AppTester _mount(Widget child) =>
    AppTester.mount(hostApp(Scaffold(body: child)));

WidgetNode _canvas(AppTester tester) => tester.ofType('Canvas').single;

List<List<Object?>> _commands(AppTester tester) =>
    (_canvas(tester).props['commands'] as List).cast<List<Object?>>();

void main() {
  group('CustomPaint', () {
    test('records what the painter drew, in order', () {
      final tester = _mount(
        CustomPaint(painter: _ShapesPainter(), size: const Size(200, 100)),
      );

      final node = _canvas(tester);
      expect(node.props['width'], 200.0);
      expect(node.props['height'], 100.0);
      expect(_ShapesPainter.lastSize, const Size(200, 100));

      final commands = _commands(tester);
      expect(commands.map((c) => c.first), [
        'rect',
        'circle',
        'oval',
        'line',
        'save',
        'translate',
        'rotate',
        'scale',
        'path',
        'restore',
      ]);
      expect(commands[0], ['rect', 0.0, 0.0, 200.0, 100.0, 0]);
      expect(commands[1], ['circle', 10.0, 20.0, 5.0, 0]);
      expect(commands[2], ['oval', 1.0, 2.0, 3.0, 4.0, 0]);
      expect(commands[3], ['line', 0.0, 0.0, 30.0, 40.0, 1]);
      expect(commands[5], ['translate', 5.0, 6.0]);
      expect(commands[6], ['rotate', 0.5]);
      // One factor scales both axes, as Flutter's optional sy does.
      expect(commands[7], ['scale', 2.0, 2.0]);
      expect(commands[8], [
        'path',
        [
          ['M', 0.0, 0.0],
          ['L', 10.0, 0.0],
          ['Q', 15.0, 5.0, 10.0, 10.0],
          ['Z'],
        ],
        1,
      ]);
    });

    test('paints that draw the same share one table entry', () {
      final tester = _mount(
        CustomPaint(painter: _ShapesPainter(), size: const Size(200, 100)),
      );

      final paints = (_canvas(tester).props['paints'] as List)
          .cast<Map<String, dynamic>>();
      expect(paints, hasLength(2));
      // A fill is the default and says nothing but its colour.
      expect(paints[0], {'color': '#ff0000'});
      expect(paints[1], {
        'color': '#0000ff',
        'style': 'stroke',
        'strokeWidth': 2.0,
        'cap': 'round',
      });
    });

    test('paints against the viewport until the renderer reports a size, '
        'then against that', () async {
      final tester = _mount(
        CustomPaint(painter: _ShapesPainter(), child: const SizedBox.expand()),
      );

      // Nothing has reported a viewport either, so it is the assumed one.
      expect(_ShapesPainter.lastSize, const Size(390, 800));
      expect(_commands(tester).first, ['rect', 0.0, 0.0, 390.0, 800.0, 0]);

      final sizeEvent = _canvas(tester).props['sizeEventId'] as String;
      await tester.emit(sizeEvent, {'width': 320.0, 'height': 240.0});

      expect(_ShapesPainter.lastSize, const Size(320, 240));
      expect(_commands(tester).first, ['rect', 0.0, 0.0, 320.0, 240.0, 0]);
    });

    test('a SizedBox.expand child means "fill the parent"', () {
      final tester = _mount(
        CustomPaint(painter: _ShapesPainter(), child: const SizedBox.expand()),
      );

      final node = _canvas(tester);
      expect(node.props['expand'], 'both');
      expect(node.props.containsKey('width'), isFalse);
      expect(node.props.containsKey('height'), isFalse);
      // The empty box was the instruction, not something to draw.
      expect(node.children, isEmpty);
    });

    test('any other child is drawn inside the canvas, which sizes to it', () {
      final tester = _mount(
        CustomPaint(
          painter: _ShapesPainter(),
          child: const Text('over the picture'),
        ),
      );

      final node = _canvas(tester);
      expect(node.props.containsKey('expand'), isFalse);
      expect(node.props.containsKey('width'), isFalse);
      expect(node.children!.single.props['content'], 'over the picture');
    });

    test('a ValueKey is the node id', () {
      final tester = _mount(
        CustomPaint(
          key: const ValueKey('board'),
          painter: _ShapesPainter(),
          size: const Size(10, 10),
        ),
      );

      expect(tester.get('board').type, 'Canvas');
    });
  });

  group('TextPainter', () {
    test('estimates its size from the font size and the characters', () {
      final latin = TextPainter(
        text: const TextSpan(text: 'Hello', style: TextStyle(fontSize: 20)),
      )..layout();
      expect(latin.width, closeTo(5 * 0.55 * 20, 1e-9));
      expect(latin.height, closeTo(1.2 * 20, 1e-9));

      // CJK and emoji are about twice as wide as a Latin letter.
      final wide = TextPainter(
        text: const TextSpan(text: '日本', style: TextStyle(fontSize: 20)),
      )..layout();
      expect(wide.width, closeTo(2 * 1.1 * 20, 1e-9));

      final twoLines = TextPainter(
        text: const TextSpan(text: 'a\nbc', style: TextStyle(fontSize: 10)),
      )..layout();
      expect(twoLines.width, closeTo(2 * 0.55 * 10, 1e-9));
      expect(twoLines.height, closeTo(2 * 1.2 * 10, 1e-9));
    });

    test('wraps at maxWidth and never reports wider than it', () {
      // Each word is 4 × 5.5 = 22 wide; two of them and a space do not fit
      // in 40.
      final wrapped = TextPainter(
        text: const TextSpan(
          text: 'aaaa bbbb',
          style: TextStyle(fontSize: 10),
        ),
      )..layout(maxWidth: 40);
      expect(wrapped.width, 40);
      expect(wrapped.height, closeTo(2 * 1.2 * 10, 1e-9));
    });

    test('sends the box it measured, so centred text stays centred', () {
      final tester = _mount(
        CustomPaint(painter: _LabelPainter(), size: const Size(200, 100)),
      );

      final command = _commands(tester).single;
      expect(command[0], 'text');
      expect(command[1], 'Hello');

      final width = _LabelPainter.measuredWidth!;
      final x = command[2] as double;
      final options = command[4] as Map<String, dynamic>;
      // The estimated box is [x, x + maxWidth], and its middle is the point
      // the painter aimed at. A renderer centring the real glyphs in that box
      // lands on the same point however wrong the estimate was.
      expect(options['maxWidth'], width);
      expect(options['align'], 'center');
      expect(x + (options['maxWidth'] as double) / 2, closeTo(100, 1e-9));
      expect(command[3], 50.0);
      expect(options['size'], 20.0);
      expect(options['color'], '#ff0000');
      expect(_LabelPainter.measuredHeight, closeTo(24, 1e-9));
    });
  });
}
