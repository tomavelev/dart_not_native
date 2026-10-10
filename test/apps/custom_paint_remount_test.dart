/// A CustomPaint that leaves the tree and comes back is a new State, and the
/// renderer - which reports a size once, and again only when it changes -
/// has nothing new to tell it. It must still paint against the size the
/// surface has, not against the viewport it guesses at before any report.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _Fill extends CustomPainter {
  const _Fill();

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint());

  @override
  bool shouldRepaint(_Fill oldDelegate) => false;
}

class _Screen extends StatefulWidget {
  const _Screen();

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  bool loading = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          key: const ValueKey('toggle'),
          onPressed: () => setState(() => loading = !loading),
          child: const Text('toggle'),
        ),
        Expanded(
          child: loading
              ? const Center(child: Text('loading'))
              : const CustomPaint(size: Size.infinite, painter: _Fill()),
        ),
      ],
    ),
  );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Screen())));

  WidgetNode canvas() => tester.ofType('Canvas').single;

  /// The rectangle the painter filled: the surface it was told it has.
  List<Object?> filled() =>
      ((canvas().props['commands'] as List).single as List).sublist(1, 5);

  test('paints against the viewport until the renderer reports a size', () {
    expect(filled(), [0.0, 0.0, 390.0, 800.0]);
  });

  test('a surface that comes back keeps the size it was measured at', () async {
    final sizeEvent = canvas().props['sizeEventId'] as String;
    await tester.emit(sizeEvent, {'width': 300.0, 'height': 200.0});
    expect(filled(), [0.0, 0.0, 300.0, 200.0]);

    await tester.tap('toggle');
    expect(tester.ofType('Canvas'), isEmpty);
    await tester.tap('toggle');

    // Same box, same size: the renderer sends nothing, and nothing is needed.
    expect(canvas().props['sizeEventId'], sizeEvent);
    expect(filled(), [0.0, 0.0, 300.0, 200.0]);
  });

  test('a new report still wins over what was remembered', () async {
    final sizeEvent = canvas().props['sizeEventId'] as String;
    await tester.emit(sizeEvent, {'width': 300.0, 'height': 200.0});
    await tester.tap('toggle');
    await tester.tap('toggle');

    await tester.emit(sizeEvent, {'width': 320.0, 'height': 480.0});

    expect(filled(), [0.0, 0.0, 320.0, 480.0]);
  });
}
